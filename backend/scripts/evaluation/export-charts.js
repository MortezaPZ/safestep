/**
 * داده‌ی نمودارهای ارزیابی.
 * منحنی ROC روی dataset.csv است که مصنوعی است؛ آزمون SisFall نیست.
 * هشدار کاذب حصار از موتور همان محصول با نویز GPS روی مرز محاسبه شده است.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { predict } from '../../src/services/fallDetection/classifier.js';
import { evaluateTransition } from '../../src/services/geofenceEngine.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, '../../../docs/evaluation');
fs.mkdirSync(outDir, { recursive: true });

function writeCsv(name, rows) {
  const file = path.join(outDir, name);
  fs.writeFileSync(file, `${rows.join('\n')}\n`, 'utf8');
  return file;
}

const csvPath = path.resolve(here, '../../data/falls/dataset.csv');
let syntheticRocSummary = null;
if (fs.existsSync(csvPath)) {
  const lines = fs.readFileSync(csvPath, 'utf8').trim().split(/\r?\n/).slice(1);
  const scored = [];
  for (const line of lines) {
    const cols = line.split(',');
    const label = Number(cols[0]);
    const features = cols.slice(1, 15).map(Number);
    if (features.length !== 14 || features.some((n) => Number.isNaN(n))) continue;
    const result = predict(features);
    scored.push({ label, confidence: result.confidence });
  }

  const positives = scored.filter((row) => row.label === 1).length;
  const negatives = scored.length - positives;
  const roc = ['threshold,tpr,fpr,tp,fp,fn,tn,source'];
  for (let step = 0; step <= 20; step += 1) {
    const threshold = step / 20;
    let tp = 0;
    let fp = 0;
    let fn = 0;
    let tn = 0;
    for (const row of scored) {
      const predicted = row.confidence >= threshold ? 1 : 0;
      if (predicted === 1 && row.label === 1) tp += 1;
      else if (predicted === 1 && row.label === 0) fp += 1;
      else if (predicted === 0 && row.label === 1) fn += 1;
      else tn += 1;
    }
    const tpr = positives ? tp / positives : 0;
    const fpr = negatives ? fp / negatives : 0;
    roc.push([threshold.toFixed(2), tpr.toFixed(4), fpr.toFixed(4), tp, fp, fn, tn, 'synthetic-dataset.csv'].join(','));
  }

  let auc = 0;
  const points = roc.slice(1).map((line) => line.split(',').map(Number));
  const ordered = [...points].sort((a, b) => a[2] - b[2]);
  for (let i = 1; i < ordered.length; i += 1) {
    const dx = ordered[i][2] - ordered[i - 1][2];
    auc += dx * (ordered[i][1] + ordered[i - 1][1]) / 2;
  }
  writeCsv('roc-threshold.csv', roc);
  syntheticRocSummary = `samples=${scored.length} auc≈${auc.toFixed(3)} positives=${positives} negatives=${negatives}`;
} else {
  process.stdout.write('Synthetic dataset not packaged; skipped roc-threshold.csv regeneration.\n');
}

const fence = ['hysteresis_m,debounce_count,false_exit_count,true_exit_count,source'];
const debounceCount = 1;
for (const hysteresisM of [0, 10, 25, 40]) {
  let state = { state: 'inside', consecutiveCount: 0, pendingState: null };
  let falseExits = 0;
  const radius = 150;
  for (let i = 0; i < 240; i += 1) {
    const noise = ((i * 13) % 31) - 15;
    const distance = radius + noise;
    const next = evaluateTransition(state, distance, radius, { hysteresisM, debounceCount, cooldownSec: 0 });
    if (next.event === 'exit') falseExits += 1;
    state = next;
  }
  let walk = { state: 'inside', consecutiveCount: 0, pendingState: null };
  let trueExits = 0;
  for (let i = 0; i < 30; i += 1) {
    const distance = radius - 40 + i * 4;
    const next = evaluateTransition(walk, distance, radius, { hysteresisM, debounceCount, cooldownSec: 0 });
    if (next.event === 'exit') trueExits += 1;
    walk = next;
  }
  fence.push([hysteresisM, debounceCount, falseExits, trueExits, 'geofence-engine-simulation'].join(','));
}

const model = (await import('../../src/services/fallDetection/classifier.js')).loadModel();
const prototypes = model.knn.points;
const k = model.knn.k;
function looConfidence(index) {
  const [vec, label] = prototypes[index];
  const dists = [];
  for (let j = 0; j < prototypes.length; j += 1) {
    if (j === index) continue;
    const other = prototypes[j][0];
    let d = 0;
    for (let i = 0; i < vec.length; i += 1) {
      const diff = vec[i] - other[i];
      d += diff * diff;
    }
    dists.push([Math.sqrt(d), prototypes[j][1]]);
  }
  dists.sort((a, b) => a[0] - b[0]);
  const nearest = dists.slice(0, k);
  const agree = nearest.filter((item) => item[1] === 1).length / nearest.length;
  return { label, confidence: agree };
}
const loo = prototypes.map((_, index) => looConfidence(index));
const looPos = loo.filter((row) => row.label === 1).length;
const looNeg = loo.length - looPos;
const looRows = ['threshold,tpr,fpr,tp,fp,fn,tn,source'];
for (let step = 0; step <= 20; step += 1) {
  const threshold = step / 20;
  let tp = 0;
  let fp = 0;
  let fn = 0;
  let tn = 0;
  for (const row of loo) {
    const predicted = row.confidence >= threshold ? 1 : 0;
    if (predicted === 1 && row.label === 1) tp += 1;
    else if (predicted === 1 && row.label === 0) fp += 1;
    else if (predicted === 0 && row.label === 1) fn += 1;
    else tn += 1;
  }
  looRows.push([
    threshold.toFixed(2),
    (looPos ? tp / looPos : 0).toFixed(4),
    (looNeg ? fp / looNeg : 0).toFixed(4),
    tp, fp, fn, tn,
    'sisfall-prototypes-leave-one-out',
  ].join(','));
}
writeCsv('roc-sisfall-loo.csv', looRows);
writeCsv('geofence-false-alarms.csv', fence);
if (syntheticRocSummary) process.stdout.write(`${syntheticRocSummary}\n`);
