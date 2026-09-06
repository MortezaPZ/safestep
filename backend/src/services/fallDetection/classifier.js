import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cannedFallFeatures } from '../../../scripts/falls/generate_synthetic.js';

const MODEL_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  'model.json',
);

let cached = null;

export function loadModel() {
  if (cached) return cached;
  const raw = fs.readFileSync(MODEL_PATH, 'utf8');
  cached = JSON.parse(raw);
  return cached;
}

export function standardize(features, model = loadModel()) {
  const mean = model.standardization.mean;
  const std = model.standardization.std;
  return features.map((v, i) => {
    const s = std[i] === 0 ? 1 : std[i];
    return (v - mean[i]) / s;
  });
}

function sigmoid(x) {
  return 1 / (1 + Math.exp(-x));
}

function knnPredict(z, model) {
  const k = model.knn.k;
  const dists = model.knn.points.map(([vec, label]) => {
    let d = 0;
    for (let i = 0; i < z.length; i += 1) {
      const diff = z[i] - vec[i];
      d += diff * diff;
    }
    return { d, label };
  });
  dists.sort((a, b) => a.d - b.d);
  const neighbors = dists.slice(0, k);
  const fallVotes = neighbors.filter((n) => n.label === 1).length;
  const agreeRatio = fallVotes / k;
  const label = agreeRatio >= 0.5 ? 1 : 0;
  return { label, agreeRatio };
}

function svmPredict(z, model) {
  let margin = model.svm.b;
  for (let i = 0; i < z.length; i += 1) margin += model.svm.w[i] * z[i];
  return { label: margin >= 0 ? 1 : 0, margin };
}

/**
 * @param {number[]} features
 */
export function predict(features, model = loadModel()) {
  const z = standardize(features, model);
  const svm = svmPredict(z, model);
  const knn = knnPredict(z, model);
  const bothFall = svm.label === 1 && knn.label === 1;
  const isFall = bothFall || svm.margin > 1.0 || knn.agreeRatio >= 0.8;
  const confidence = (sigmoid(svm.margin) + knn.agreeRatio) / 2;
  return {
    isFall,
    confidence: Math.min(1, Math.max(0, confidence)),
    votes: {
      svm: { label: svm.label === 1 ? 'fall' : 'adl', margin: svm.margin },
      knn: { label: knn.label === 1 ? 'fall' : 'adl', agreeRatio: knn.agreeRatio },
    },
    modelName: 'svm+knn',
    modelVersion: model.version,
  };
}

export function cannedPositiveFeatures() {
  return cannedFallFeatures();
}

export default { predict, loadModel, standardize, cannedPositiveFeatures };
