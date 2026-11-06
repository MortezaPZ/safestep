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
import { parseSyntheticCsv } from './synthetic-roc.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = process.env.EVALUATION_OUTPUT_DIR
  ? path.resolve(process.env.EVALUATION_OUTPUT_DIR)
  : path.resolve(here, '../../../docs/evaluation');
fs.mkdirSync(outDir, { recursive: true });

function writeCsv(name, rows) {
  const file = path.join(outDir, name);
  fs.writeFileSync(file, `${rows.join('\n')}\n`, 'utf8');
  return file;
}

const csvPath = process.env.EVALUATION_DATASET_CSV
  ? path.resolve(process.env.EVALUATION_DATASET_CSV)
  : path.resolve(here, '../../data/falls/dataset.csv');
let syntheticRocSummary = null;
const syntheticRows = fs.existsSync(csvPath) ? parseSyntheticCsv(fs.readFileSync(csvPath, 'utf8')) : null;
if (syntheticRows) {
  const scored = syntheticRows.map(({ label, features }) => ({ label, confidence: predict(features).confidence }));

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
  process.stdout.write('Synthetic dataset missing or invalid; skipped roc-threshold.csv regeneration.\n');
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

// roc-sisfall-loo.csv is a historical artifact tied to an older model.
// Replacing it with a different model would falsify its documented provenance.
writeCsv('geofence-false-alarms.csv', fence);
if (syntheticRocSummary) process.stdout.write(`${syntheticRocSummary}\n`);
