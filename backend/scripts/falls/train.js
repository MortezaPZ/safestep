/**
 * Train the deployed KNN and linear Pegasos classifier from labeled feature rows.
 * Subject-aware datasets use nested grouped cross-validation; scaling is fitted
 * only on each training partition. Legacy rows without subject IDs use
 * deterministic stratified folds and are labeled as such in the report.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateDataset, toCsv } from './generate_synthetic.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DATA_CSV = path.join(ROOT, 'data/falls/dataset.csv');
const MODEL_PATH = path.join(ROOT, 'src/services/fallDetection/model.json');
const REPORT_PATH = path.resolve(ROOT, '../docs/phase3/02-training-report.md');
const KNN_CANDIDATES = [3, 5, 7, 9];
const SVM_CANDIDATES = [1e-3, 1e-2, 1e-1];
const FEATURE_COUNT = 14;
const SEED = 0x5eed;

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

export function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim() && !line.startsWith('#'));
  if (lines.length < 2) return [];
  const header = lines[0].split(',').map((value) => value.trim().toLowerCase());
  const labelIndex = header.indexOf('label');
  const subjectIndex = header.indexOf('subject_id');
  const recordingIndex = header.indexOf('recording_id');
  const featureIndexes = Array.from({ length: FEATURE_COUNT }, (_, i) => header.indexOf('f' + (i + 1)));
  const hasNamedFeatures = featureIndexes.every((index) => index >= 0);
  const rows = [];

  for (const line of lines.slice(1)) {
    const parts = line.split(',').map((value) => value.trim());
    const labelAt = labelIndex >= 0 ? labelIndex : 0;
    const indexes = hasNamedFeatures
      ? featureIndexes
      : Array.from({ length: FEATURE_COUNT }, (_, i) => labelAt + i + 1);
    const label = Number(parts[labelAt]);
    const features = indexes.map((index) => Number(parts[index]));
    if (![0, 1].includes(label) || features.some((value) => !Number.isFinite(value))) continue;
    const row = { label, features };
    if (subjectIndex >= 0 && parts[subjectIndex]) row.subjectId = parts[subjectIndex];
    if (recordingIndex >= 0 && parts[recordingIndex]) row.recordingId = parts[recordingIndex];
    rows.push(row);
  }
  return rows;
}

function stats(rows) {
  if (rows.length === 0) throw new Error('Cannot fit feature scaling on an empty training partition.');
  const mean = Array(FEATURE_COUNT).fill(0);
  for (const row of rows) {
    for (let i = 0; i < FEATURE_COUNT; i += 1) mean[i] += row.features[i];
  }
  for (let i = 0; i < FEATURE_COUNT; i += 1) mean[i] /= rows.length;
  const std = Array(FEATURE_COUNT).fill(0);
  for (const row of rows) {
    for (let i = 0; i < FEATURE_COUNT; i += 1) {
      std[i] += (row.features[i] - mean[i]) ** 2;
    }
  }
  for (let i = 0; i < FEATURE_COUNT; i += 1) std[i] = Math.sqrt(std[i] / rows.length) || 1;
  return { mean, std };
}

function zscore(features, mean, std) {
  return features.map((value, i) => (value - mean[i]) / (std[i] || 1));
}

function confusion(truth, predicted) {
  let tp = 0;
  let fp = 0;
  let tn = 0;
  let fn = 0;
  for (let i = 0; i < truth.length; i += 1) {
    if (truth[i] === 1 && predicted[i] === 1) tp += 1;
    else if (truth[i] === 0 && predicted[i] === 1) fp += 1;
    else if (truth[i] === 0 && predicted[i] === 0) tn += 1;
    else fn += 1;
  }
  const precision = tp + fp ? tp / (tp + fp) : 0;
  const recall = tp + fn ? tp / (tp + fn) : 0;
  const f1 = precision + recall ? 2 * precision * recall / (precision + recall) : 0;
  return {
    tp, fp, tn, fn, precision, recall, f1,
    accuracy: truth.length ? (tp + tn) / truth.length : 0,
    falsePositiveRate: fp + tn ? fp / (fp + tn) : 0,
  };
}

function stratifiedFolds(rows, count = 5, seed = SEED) {
  const random = seededRandom(seed);
  const folds = Array.from({ length: count }, () => []);
  for (const label of [0, 1]) {
    const group = rows.filter((row) => row.label === label);
    for (let i = group.length - 1; i > 0; i -= 1) {
      const j = Math.floor(random() * (i + 1));
      [group[i], group[j]] = [group[j], group[i]];
    }
    group.forEach((row, i) => folds[i % count].push(row));
  }
  return folds;
}

export function groupFolds(rows, count = 5, seed = SEED) {
  const bySubject = new Map();
  for (const row of rows) {
    if (!row.subjectId) throw new Error('Subject-grouped validation requires subject_id for every row.');
    if (!bySubject.has(row.subjectId)) bySubject.set(row.subjectId, []);
    bySubject.get(row.subjectId).push(row);
  }
  if (bySubject.size < count) {
    throw new Error('Need at least ' + count + ' distinct subjects for grouped cross-validation; found ' + bySubject.size + '.');
  }

  const random = seededRandom(seed);
  const groups = [...bySubject.entries()].map(([subjectId, subjectRows]) => ({
    subjectId,
    rows: subjectRows,
    positive: subjectRows.filter((row) => row.label === 1).length,
    negative: subjectRows.filter((row) => row.label === 0).length,
    tie: random(),
  }));
  groups.sort((a, b) =>
    Math.max(b.positive, b.negative) - Math.max(a.positive, a.negative) ||
    b.rows.length - a.rows.length ||
    a.tie - b.tie,
  );

  const folds = Array.from({ length: count }, () => ({ rows: [], positive: 0, negative: 0 }));
  const totalPositive = rows.filter((row) => row.label === 1).length;
  const totalNegative = rows.length - totalPositive;
  const positiveTarget = Math.max(1, totalPositive / count);
  const negativeTarget = Math.max(1, totalNegative / count);
  const rowTarget = rows.length / count;

  for (const group of groups) {
    let bestIndex = 0;
    let bestScore = Infinity;
    const tieOrder = Array.from({ length: count }, (_, index) => index)
      .sort(() => random() - 0.5);
    for (const index of tieOrder) {
      const fold = folds[index];
      const pos = fold.positive + group.positive;
      const neg = fold.negative + group.negative;
      const size = fold.rows.length + group.rows.length;
      const score =
        ((pos - positiveTarget) / positiveTarget) ** 2 +
        ((neg - negativeTarget) / negativeTarget) ** 2 +
        ((size - rowTarget) / rowTarget) ** 2;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    folds[bestIndex].rows.push(...group.rows);
    folds[bestIndex].positive += group.positive;
    folds[bestIndex].negative += group.negative;
  }
  return folds.map((fold) => fold.rows);
}

function makeFolds(rows, count, seed) {
  const hasSubjects = rows.every((row) => Boolean(row.subjectId));
  return hasSubjects ? groupFolds(rows, count, seed) : stratifiedFolds(rows, count, seed);
}

function trainSvm(train, lambda, epochs = 40, seed = SEED) {
  const random = seededRandom(seed);
  const w = Array(FEATURE_COUNT).fill(0);
  let b = 0;
  let step = 0;
  for (let epoch = 0; epoch < epochs; epoch += 1) {
    const shuffled = [...train];
    for (let i = shuffled.length - 1; i > 0; i -= 1) {
      const j = Math.floor(random() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    for (const point of shuffled) {
      step += 1;
      const eta = 1 / (lambda * step);
      const y = point.label === 1 ? 1 : -1;
      let margin = b;
      for (let i = 0; i < FEATURE_COUNT; i += 1) margin += w[i] * point.z[i];
      if (y * margin < 1) {
        for (let i = 0; i < FEATURE_COUNT; i += 1) {
          w[i] = (1 - eta * lambda) * w[i] + eta * y * point.z[i];
        }
        b += eta * y;
      } else {
        for (let i = 0; i < FEATURE_COUNT; i += 1) w[i] *= 1 - eta * lambda;
      }
    }
  }
  return { w, b };
}

function svmMargin(model, features) {
  return model.b + features.reduce((sum, value, i) => sum + model.w[i] * value, 0);
}

function nearestFallRatio(train, feature, k) {
  const nearest = [];
  for (const point of train) {
    let distance = 0;
    for (let i = 0; i < FEATURE_COUNT; i += 1) {
      distance += (feature[i] - point.z[i]) ** 2;
    }
    let insertAt = nearest.findIndex((item) => distance < item.distance);
    if (insertAt < 0) insertAt = nearest.length;
    if (insertAt >= k) continue;
    nearest.splice(insertAt, 0, { distance, label: point.label });
    if (nearest.length > k) nearest.pop();
  }
  return nearest.length
    ? nearest.filter((item) => item.label === 1).length / nearest.length
    : 0;
}

function selectParameters(rows, foldCount, seed) {
  const folds = makeFolds(rows, foldCount, seed);
  const knnResults = new Map(KNN_CANDIDATES.map((k) => [k, { truth: [], predicted: [] }]));
  const svmResults = new Map(SVM_CANDIDATES.map((lambda) => [lambda, { truth: [], predicted: [] }]));

  for (let foldIndex = 0; foldIndex < folds.length; foldIndex += 1) {
    const test = folds[foldIndex];
    const trainRows = folds.flatMap((fold, index) => index === foldIndex ? [] : fold);
    const { mean, std } = stats(trainRows);
    const train = trainRows.map((row) => ({ label: row.label, z: zscore(row.features, mean, std) }));
    const testZ = test.map((row) => zscore(row.features, mean, std));
    for (const k of KNN_CANDIDATES) {
      knnResults.get(k).truth.push(...test.map((row) => row.label));
    }

    const maxK = Math.max(...KNN_CANDIDATES);
    const neighborLabels = testZ.map((feature) => {
      const nearest = [];
      for (const point of train) {
        let distance = 0;
        for (let i = 0; i < FEATURE_COUNT; i += 1) {
          distance += (feature[i] - point.z[i]) ** 2;
        }
        let insertAt = nearest.findIndex((item) => distance < item.distance);
        if (insertAt < 0) insertAt = nearest.length;
        if (insertAt < maxK) {
          nearest.splice(insertAt, 0, { distance, label: point.label });
          if (nearest.length > maxK) nearest.pop();
        }
      }
      return nearest.map((item) => item.label);
    });
    for (const k of KNN_CANDIDATES) {
      const result = knnResults.get(k);
      for (const labels of neighborLabels) {
        const vote = labels.slice(0, k).filter((label) => label === 1).length;
        result.predicted.push(vote >= k / 2 ? 1 : 0);
      }
    }

    for (const lambda of SVM_CANDIDATES) {
      const svm = trainSvm(train, lambda, 40, seed + foldIndex + Math.round(lambda * 1e6));
      const result = svmResults.get(lambda);
      result.truth.push(...test.map((row) => row.label));
      result.predicted.push(...testZ.map((features) => svmMargin(svm, features) >= 0 ? 1 : 0));
    }
  }

  const bestK = [...knnResults.entries()]
    .map(([k, result]) => ({ k, ...confusion(result.truth, result.predicted) }))
    .sort((a, b) => b.f1 - a.f1 || b.accuracy - a.accuracy || a.k - b.k)[0].k;
  const bestLambda = [...svmResults.entries()]
    .map(([lambda, result]) => ({ lambda, ...confusion(result.truth, result.predicted) }))
    .sort((a, b) => b.f1 - a.f1 || b.accuracy - a.accuracy || a.lambda - b.lambda)[0].lambda;
  return { k: bestK, lambda: bestLambda };
}

function evaluateScores(scores, predicate) {
  return confusion(scores.map((row) => row.label), scores.map((row) => predicate(row) ? 1 : 0));
}

function thresholdSweep(scores, source) {
  const marginThresholds = [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2];
  const agreeThresholds = [0.5, 0.6, 0.7, 0.8, 0.9, 1];
  return marginThresholds.flatMap((marginThreshold) => agreeThresholds.map((agreeThreshold) => {
    const metrics = evaluateScores(scores, (row) =>
      row.bothModelsVoteFall ||
      row.margin > marginThreshold ||
      row.agreeRatio >= agreeThreshold,
    );
    return {
      marginThreshold,
      agreeThreshold,
      ...metrics,
      source,
    };
  }));
}

export function trainFromRows(rows) {
  if (!Array.isArray(rows) || rows.length < 5) {
    throw new Error('At least five labeled feature rows are required.');
  }
  if (rows.some((row) => ![0, 1].includes(row.label) ||
      !Array.isArray(row.features) || row.features.length !== FEATURE_COUNT ||
      row.features.some((value) => !Number.isFinite(value)))) {
    throw new Error('Every row must contain a binary label and fourteen finite features.');
  }

  const subjectGrouped = rows.every((row) => Boolean(row.subjectId));
  const outerCount = 5;
  const outerFolds = makeFolds(rows, outerCount, SEED);
  const outerScores = [];

  for (let outerIndex = 0; outerIndex < outerFolds.length; outerIndex += 1) {
    const test = outerFolds[outerIndex];
    const trainRows = outerFolds.flatMap((fold, index) => index === outerIndex ? [] : fold);
    const groups = new Set(trainRows.map((row) => row.subjectId).filter(Boolean)).size;
    const innerCount = subjectGrouped ? Math.min(4, groups) : 4;
    const selected = selectParameters(trainRows, innerCount, SEED + outerIndex * 101);
    const scaling = stats(trainRows);
    const train = trainRows.map((row) => ({
      label: row.label,
      z: zscore(row.features, scaling.mean, scaling.std),
    }));
    const svm = trainSvm(train, selected.lambda, 40, SEED + outerIndex * 1009);

    for (const row of test) {
      const z = zscore(row.features, scaling.mean, scaling.std);
      const margin = svmMargin(svm, z);
      const agreeRatio = nearestFallRatio(train, z, selected.k);
      outerScores.push({
        label: row.label,
        margin,
        agreeRatio,
        bothModelsVoteFall: margin >= 0 && agreeRatio >= 0.5,
      });
    }
  }

  const finalGroups = new Set(rows.map((row) => row.subjectId).filter(Boolean)).size;
  const finalTuneFolds = subjectGrouped ? Math.min(5, finalGroups) : 5;
  const selected = selectParameters(rows, finalTuneFolds, SEED + 9001);
  const scaling = stats(rows);
  const prepared = rows.map((row) => ({
    label: row.label,
    z: zscore(row.features, scaling.mean, scaling.std),
    features: row.features,
  }));
  const finalSvm = trainSvm(prepared, selected.lambda, 40, SEED + 1701);
  const knnPoints = prepared.map((row) => [row.z, row.label]);
  const cvKnn = evaluateScores(outerScores, (row) => row.agreeRatio >= 0.5);
  const cvSvm = evaluateScores(outerScores, (row) => row.margin >= 0);
  const cvEnsemble = evaluateScores(outerScores, (row) =>
    row.bothModelsVoteFall || row.margin > 1 || row.agreeRatio >= 0.8,
  );
  const sweep = thresholdSweep(
    outerScores,
    subjectGrouped ? 'subject-grouped-nested-5-fold-out-of-fold-diagnostic' : 'stratified-nested-5-fold-out-of-fold-diagnostic',
  );

  return {
    version: '1.1.0',
    trainedAt: new Date().toISOString(),
    datasetKind: 'unknown',
    kernel: 'linear',
    training: {
      seed: SEED,
      folds: 5,
      foldStrategy: subjectGrouped ? 'subject-grouped nested cross-validation' : 'stratified nested cross-validation',
      hyperparameterSelection: 'four-fold inner cross-validation; scaling refit inside every fold',
      rowCount: rows.length,
      subjectCount: subjectGrouped ? finalGroups : null,
    },
    standardization: scaling,
    knn: { k: selected.k, points: knnPoints },
    svm: { w: finalSvm.w, b: finalSvm.b, lambda: selected.lambda },
    cv: {
      foldStrategy: subjectGrouped ? 'subject-grouped nested 5-fold out-of-fold' : 'stratified nested 5-fold out-of-fold',
      knn: {
        accuracy: cvKnn.accuracy, precision: cvKnn.precision, recall: cvKnn.recall, f1: cvKnn.f1,
        confusion: { tp: cvKnn.tp, fp: cvKnn.fp, tn: cvKnn.tn, fn: cvKnn.fn },
      },
      svm: {
        accuracy: cvSvm.accuracy, precision: cvSvm.precision, recall: cvSvm.recall, f1: cvSvm.f1,
        confusion: { tp: cvSvm.tp, fp: cvSvm.fp, tn: cvSvm.tn, fn: cvSvm.fn },
      },
      ensemble: {
        accuracy: cvEnsemble.accuracy, precision: cvEnsemble.precision, recall: cvEnsemble.recall, f1: cvEnsemble.f1,
        confusion: { tp: cvEnsemble.tp, fp: cvEnsemble.fp, tn: cvEnsemble.tn, fn: cvEnsemble.fn },
      },
    },
    thresholdSweep: sweep,
    ensemble: 'svm_then_knn',
  };
}

function faPct(value) {
  return (value * 100).toFixed(2) + '٪';
}

function writeReport(model, rowCount) {
  const cv = model.cv;
  const report = [
    '# گزارش آموزش تشخیص سقوط',
    '',
    'این گزارش خودکار است. برای دادهٔ واقعی، فقط پس از اجرای دوباره روی دادهٔ منبع واقعی معتبر است.',
    '',
    '## داده',
    '',
    '- نوع داده: ' + model.datasetKind,
    '- تعداد ردیف ویژگی: ' + rowCount,
    '- راهبرد fold: ' + model.training.foldStrategy,
    '- بذر ثابت: ' + model.training.seed,
    '- تنظیم ابرپارامترها: چهار fold داخلی؛ میانگین و انحراف معیار فقط از بخش آموزش هر fold محاسبه می‌شوند.',
    '',
    '## اعتبارسنجی بیرونی پنج‌لایه',
    '',
    '| مدل | دقت | صحت | بازخوانی | F1 | ماتریس TP/FP/FN/TN |',
    '| --- | ---: | ---: | ---: | ---: | --- |',
    '| KNN (k=' + model.knn.k + ') | ' + faPct(cv.knn.accuracy) + ' | ' + faPct(cv.knn.precision) + ' | ' + faPct(cv.knn.recall) + ' | ' + faPct(cv.knn.f1) + ' | ' + JSON.stringify(cv.knn.confusion) + ' |',
    '| SVM خطی | ' + faPct(cv.svm.accuracy) + ' | ' + faPct(cv.svm.precision) + ' | ' + faPct(cv.svm.recall) + ' | ' + faPct(cv.svm.f1) + ' | ' + JSON.stringify(cv.svm.confusion) + ' |',
    '| قاعدهٔ ترکیبی | ' + faPct(cv.ensemble.accuracy) + ' | ' + faPct(cv.ensemble.precision) + ' | ' + faPct(cv.ensemble.recall) + ' | ' + faPct(cv.ensemble.f1) + ' | ' + JSON.stringify(cv.ensemble.confusion) + ' |',
    '',
    'قانون ترکیبی: هر دو مدل مثبت، یا margin > 1، یا agreeRatio >= 0.8.',
    'CSV جاروب آستانه‌ها مقایسهٔ تشخیصی روی پیش‌بینی‌های بیرونی است و برای انتخاب آستانهٔ نهایی باید مجموعهٔ آزمون مستقل داشته باشید.',
    '',
  ].join('\n');
  fs.mkdirSync(path.dirname(REPORT_PATH), { recursive: true });
  fs.writeFileSync(REPORT_PATH, report, 'utf8');
}

export function runTrain() {
  let datasetKind = 'real';
  let rows;
  if (fs.existsSync(DATA_CSV)) {
    const source = fs.readFileSync(DATA_CSV, 'utf8');
    rows = parseCsv(source);
    if (source.includes('# SYNTHETIC')) datasetKind = 'synthetic';
  } else {
    const generated = generateDataset({ perClass: 2000 });
    fs.mkdirSync(path.dirname(DATA_CSV), { recursive: true });
    fs.writeFileSync(DATA_CSV, toCsv(generated), 'utf8');
    rows = generated;
    datasetKind = 'synthetic';
  }
  const model = trainFromRows(rows);
  model.datasetKind = datasetKind;
  fs.writeFileSync(MODEL_PATH, JSON.stringify(model), 'utf8');
  writeReport(model, rows.length);
  return model;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const model = runTrain();
  process.stdout.write('trained nested CV: knn=' + model.cv.knn.f1.toFixed(3) +
    ' svm=' + model.cv.svm.f1.toFixed(3) + ' ensemble=' + model.cv.ensemble.f1.toFixed(3) + '\n');
}
