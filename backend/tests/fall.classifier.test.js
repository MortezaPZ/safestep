import { describe, it, expect } from 'vitest';
import { generateDataset, cannedFallFeatures } from '../scripts/falls/generate_synthetic.js';
import { trainFromRows } from '../scripts/falls/train.js';
import { predict, standardize } from '../src/services/fallDetection/classifier.js';

describe('دسته‌بند SVM و KNN', () => {
  const rows = generateDataset({ perClass: 120, seed: 7 });
  const model = trainFromRows(rows);

  it('F1 اعتبارسنجی KNN روی دادهٔ مصنوعی حداقل ۰٫۹ است', () => {
    expect(model.cv.knn.f1).toBeGreaterThanOrEqual(0.9);
  });

  it('F1 اعتبارسنجی SVM روی دادهٔ مصنوعی حداقل ۰٫۹ است', () => {
    expect(model.cv.svm.f1).toBeGreaterThanOrEqual(0.9);
  });

  it('پنجرهٔ سقوط مصنوعی را سقوط تشخیص می‌دهد', () => {
    const p = predict(cannedFallFeatures(), model);
    expect(p.isFall).toBe(true);
    expect(p.modelName).toBe('svm+knn');
    expect(p.votes.svm).toHaveProperty('margin');
    expect(p.votes.knn).toHaveProperty('agreeRatio');
  });

  it('نمونهٔ ADL مجموعه را سقوط نمی‌داند', () => {
    const adl = rows.find((r) => r.label === 0);
    const p = predict(adl.features, model);
    expect(p.isFall).toBe(false);
  });

  it('استانداردسازی طول ۱۴ دارد', () => {
    expect(standardize(cannedFallFeatures(), model)).toHaveLength(14);
  });

  it('اطمینان بین ۰ و ۱ است', () => {
    const p = predict(cannedFallFeatures(), model);
    expect(p.confidence).toBeGreaterThanOrEqual(0);
    expect(p.confidence).toBeLessThanOrEqual(1);
  });
});
