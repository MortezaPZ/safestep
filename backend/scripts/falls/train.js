/**
 * آموزش KNN و SVM خطی (Pegasos) روی CSV ویژگی‌ها.
 * هستهٔ RBF پیاده‌سازی نشد؛ مدل خطی برای پایان‌نامه کافی و قابل توضیح است.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateDataset, toCsv } from './generate_synthetic.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DATA_CSV = path.join(ROOT, 'data/falls/dataset.csv');
const MODEL_PATH = path.join(ROOT, 'src/services/fallDetection/model.json');
const REPORT_PATH = path.resolve(ROOT, '../docs/phase3/02-training-report.md');

export function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((l) => l && !l.startsWith('#'));
  const rows = [];
  for (const line of lines.slice(1)) {
    const parts = line.split(',').map(Number);
    if (parts.length < 15 || parts.some((n) => Number.isNaN(n))) continue;
    rows.push({ label: parts[0], features: parts.slice(1, 15) });
  }
  return rows;
}

function stats(rows) {
  const dim = 14;
  const mean = Array(dim).fill(0);
  for (const r of rows) for (let i = 0; i < dim; i += 1) mean[i] += r.features[i];
  for (let i = 0; i < dim; i += 1) mean[i] /= rows.length;
  const std = Array(dim).fill(0);
  for (const r of rows) {
    for (let i = 0; i < dim; i += 1) {
      const d = r.features[i] - mean[i];
      std[i] += d * d;
    }
  }
  for (let i = 0; i < dim; i += 1) std[i] = Math.sqrt(std[i] / rows.length) || 1;
  return { mean, std };
}

function zscore(features, mean, std) {
  return features.map((v, i) => (v - mean[i]) / (std[i] || 1));
}

function confusion(truth, pred) {
  let tp = 0;
  let fp = 0;
  let tn = 0;
  let fn = 0;
  for (let i = 0; i < truth.length; i += 1) {
    if (truth[i] === 1 && pred[i] === 1) tp += 1;
    else if (truth[i] === 0 && pred[i] === 1) fp += 1;
    else if (truth[i] === 0 && pred[i] === 0) tn += 1;
    else fn += 1;
  }
  const precision = tp + fp === 0 ? 0 : tp / (tp + fp);
  const recall = tp + fn === 0 ? 0 : tp / (tp + fn);
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall);
  const accuracy = (tp + tn) / truth.length;
  return { tp, fp, tn, fn, precision, recall, f1, accuracy };
}

function stratifiedFolds(rows, k = 5) {
  const pos = rows.filter((r) => r.label === 1);
  const neg = rows.filter((r) => r.label === 0);
  const folds = Array.from({ length: k }, () => []);
  pos.forEach((r, i) => folds[i % k].push(r));
  neg.forEach((r, i) => folds[i % k].push(r));
  return folds;
}

function knnPredict(train, testZ, k) {
  return testZ.map((z) => {
    const dists = train.map((p) => {
      let d = 0;
      for (let i = 0; i < z.length; i += 1) {
        const diff = z[i] - p.z[i];
        d += diff * diff;
      }
      return { d, label: p.label };
    });
    dists.sort((a, b) => a.d - b.d);
    const fall = dists.slice(0, k).filter((x) => x.label === 1).length;
    return fall >= k / 2 ? 1 : 0;
  });
}

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

function trainSvm(train, lambda, epochs = 40, seed = 1) {
  const n = train.length;
  const dim = 14;
  const random = seededRandom(seed);
  let w = Array(dim).fill(0);
  let b = 0;
  let t = 0;
  const shuffled = [...train];
  for (let e = 0; e < epochs; e += 1) {
    for (let i = shuffled.length - 1; i > 0; i -= 1) {
      const j = Math.floor(random() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    for (const p of shuffled) {
      t += 1;
      const eta = 1 / (lambda * t);
      const y = p.label === 1 ? 1 : -1;
      let margin = b;
      for (let i = 0; i < dim; i += 1) margin += w[i] * p.z[i];
      if (y * margin < 1) {
        for (let i = 0; i < dim; i += 1) w[i] = (1 - eta * lambda) * w[i] + eta * y * p.z[i];
        b += eta * y;
      } else {
        for (let i = 0; i < dim; i += 1) w[i] = (1 - eta * lambda) * w[i];
      }
    }
  }
  return { w, b };
}

function svmPredict(model, zs) {
  return zs.map((z) => {
    let m = model.b;
    for (let i = 0; i < z.length; i += 1) m += model.w[i] * z[i];
    return m >= 0 ? 1 : 0;
  });
}

/**
 * Out-of-fold sweep for the deployed OR rule over SVM margin and KNN vote.
 * Scaling is fitted on each training fold, so each score is produced without
 * using that row's label or feature distribution to fit its fold.
 */
export function sweepRuleThresholds(rows, {
  k = 5,
  lambda = 1e-2,
  marginThresholds = [-1, -0.5, 0, 0.5, 1, 1.5, 2],
  agreeThresholds = [0.5, 0.6, 0.7, 0.8, 0.9, 1],
} = {}) {
  if (!Array.isArray(rows) || rows.length < 5) {
    throw new Error('At least five labeled feature rows are required for a five-fold sweep.');
  }

  const folds = stratifiedFolds(rows, 5);
  const outOfFold = [];
  for (let foldIndex = 0; foldIndex < folds.length; foldIndex += 1) {
    const test = folds[foldIndex];
    const trainRows = folds.flatMap((fold, index) => (index === foldIndex ? [] : fold));
    const { mean, std } = stats(trainRows);
    const train = trainRows.map((row) => ({
      label: row.label,
      z: zscore(row.features, mean, std),
    }));
    const svm = trainSvm(train, lambda, 40, 0x5eed + foldIndex);

    for (const row of test) {
      const z = zscore(row.features, mean, std);
      let margin = svm.b;
      for (let i = 0; i < z.length; i += 1) margin += svm.w[i] * z[i];

      const neighbors = train
        .map((point) => {
          let distance = 0;
          for (let i = 0; i < z.length; i += 1) distance += (z[i] - point.z[i]) ** 2;
          return { distance, label: point.label };
        })
        .sort((a, b) => a.distance - b.distance)
        .slice(0, k);
      const agreeRatio = neighbors.filter((point) => point.label === 1).length / neighbors.length;
      outOfFold.push({ label: row.label, margin, agreeRatio });
    }
  }

  return marginThresholds.flatMap((marginThreshold) =>
    agreeThresholds.map((agreeThreshold) => {
      let tp = 0;
      let fp = 0;
      let fn = 0;
      let tn = 0;
      for (const row of outOfFold) {
        const bothModelsVoteFall = row.margin >= 0 && row.agreeRatio >= 0.5;
        const predicted = bothModelsVoteFall ||
          row.margin > marginThreshold || row.agreeRatio >= agreeThreshold;
        if (predicted && row.label === 1) tp += 1;
        else if (predicted) fp += 1;
        else if (row.label === 1) fn += 1;
        else tn += 1;
      }
      const precision = tp + fp ? tp / (tp + fp) : 0;
      const sensitivity = tp + fn ? tp / (tp + fn) : 0;
      const accuracy = (tp + tn) / outOfFold.length;
      const f1 = precision + sensitivity ? 2 * precision * sensitivity / (precision + sensitivity) : 0;
      return {
        marginThreshold,
        agreeThreshold,
        sensitivity,
        falsePositiveRate: fp + tn ? fp / (fp + tn) : 0,
        precision,
        accuracy,
        f1,
        tp,
        fp,
        fn,
        tn,
        source: 'stratified-5-fold-out-of-fold',
      };
    }),
  );
}

export function trainFromRows(rows) {
  const { mean, std } = stats(rows);
  const prepared = rows.map((r) => ({ label: r.label, z: zscore(r.features, mean, std), features: r.features }));
  const folds = stratifiedFolds(prepared, 5);

  const knnScores = [];
  for (const k of [3, 5, 7, 9]) {
    const truths = [];
    const preds = [];
    for (let i = 0; i < folds.length; i += 1) {
      const test = folds[i];
      const train = folds.flatMap((f, j) => (j === i ? [] : f));
      truths.push(...test.map((t) => t.label));
      preds.push(...knnPredict(train, test.map((t) => t.z), k));
    }
    knnScores.push({ k, ...confusion(truths, preds) });
  }
  knnScores.sort((a, b) => b.f1 - a.f1);
  const bestKnn = knnScores[0];

  const svmScores = [];
  for (const lambda of [1e-3, 1e-2, 1e-1]) {
    const truths = [];
    const preds = [];
    for (let i = 0; i < folds.length; i += 1) {
      const test = folds[i];
      const train = folds.flatMap((f, j) => (j === i ? [] : f));
      const model = trainSvm(train, lambda);
      truths.push(...test.map((t) => t.label));
      preds.push(...svmPredict(model, test.map((t) => t.z)));
    }
    svmScores.push({ lambda, ...confusion(truths, preds) });
  }
  svmScores.sort((a, b) => b.f1 - a.f1);
  const bestSvmCv = svmScores[0];
  const finalSvm = trainSvm(prepared, bestSvmCv.lambda);

  const subsample = prepared
    .filter((_, i) => i % Math.ceil(prepared.length / 1500) === 0)
    .slice(0, 1500)
    .map((p) => [p.z, p.label]);

  const model = {
    version: '1.0.0',
    trainedAt: new Date().toISOString(),
    datasetKind: 'synthetic',
    kernel: 'linear',
    standardization: { mean, std },
    knn: { k: bestKnn.k, points: subsample },
    svm: { w: finalSvm.w, b: finalSvm.b, lambda: bestSvmCv.lambda },
    cv: {
      knn: {
        accuracy: bestKnn.accuracy,
        precision: bestKnn.precision,
        recall: bestKnn.recall,
        f1: bestKnn.f1,
        confusion: { tp: bestKnn.tp, fp: bestKnn.fp, tn: bestKnn.tn, fn: bestKnn.fn },
      },
      svm: {
        accuracy: bestSvmCv.accuracy,
        precision: bestSvmCv.precision,
        recall: bestSvmCv.recall,
        f1: bestSvmCv.f1,
        confusion: { tp: bestSvmCv.tp, fp: bestSvmCv.fp, tn: bestSvmCv.tn, fn: bestSvmCv.fn },
      },
    },
    ensemble: 'svm_then_knn',
  };
  return model;
}

function faPct(x) {
  return `${(x * 100).toFixed(1)}٪`;
}

function writeReport(model, n) {
  const knn = model.cv.knn;
  const svm = model.cv.svm;
  const md = `# گزارش آموزش تشخیص سقوط

این گزارش به‌صورت خودکار با \`npm run train:fall\` تولید شده است.

## داده

- نوع: **داده‌ی مصنوعی** (برچسب \`# SYNTHETIC\` در CSV)
- تعداد نمونه: ${n}
- هستهٔ SVM: خطی (Pegasos). SVM با هستهٔ RBF پیاده‌سازی نشد.

## اعتبارسنجی متقاطع پنج‌لایه

| مدل | دقت | صحت | بازخوانی | F1 |
| --- | --- | --- | --- | --- |
| KNN (k=${model.knn.k}) | ${faPct(knn.accuracy)} | ${faPct(knn.precision)} | ${faPct(knn.recall)} | ${faPct(knn.f1)} |
| SVM خطی | ${faPct(svm.accuracy)} | ${faPct(svm.precision)} | ${faPct(svm.recall)} | ${faPct(svm.f1)} |

ماتریس درهم‌ریختگی KNN: TP=${knn.confusion.tp} FP=${knn.confusion.fp} TN=${knn.confusion.tn} FN=${knn.confusion.fn}

ماتریس درهم‌ریختگی SVM: TP=${svm.confusion.tp} FP=${svm.confusion.fp} TN=${svm.confusion.tn} FN=${svm.confusion.fn}

نسخهٔ مدل: \`${model.version}\` — زمان آموزش: ${model.trainedAt}
`;
  fs.mkdirSync(path.dirname(REPORT_PATH), { recursive: true });
  fs.writeFileSync(REPORT_PATH, md, 'utf8');
}

export function runTrain() {
  let datasetKind = 'real';
  let rows;
  if (fs.existsSync(DATA_CSV)) {
    const text = fs.readFileSync(DATA_CSV, 'utf8');
    rows = parseCsv(text);
    if (text.includes('# SYNTHETIC')) datasetKind = 'synthetic';
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
  process.stdout.write(`trained f1 knn=${model.cv.knn.f1.toFixed(3)} svm=${model.cv.svm.f1.toFixed(3)}\n`);
}
