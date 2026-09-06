import { describe, it, expect } from 'vitest';
import { extractFeatures, preScreen } from '../src/services/fallDetection/features.js';
import { G } from '../src/services/fallDetection/features.js';
import { fixtureVectors } from '../scripts/falls/generate_synthetic.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const vectorsPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../data/falls/vectors.json');

describe('استخراج ویژگی سقوط', () => {
  it('بردار ثابت با استخراج‌کننده یکی است', () => {
    const fixtures = fixtureVectors();
    for (const c of fixtures.cases) {
      const got = extractFeatures(c.acc, c.gyro);
      expect(got).toHaveLength(14);
      for (let i = 0; i < 14; i += 1) {
        expect(Math.abs(got[i] - c.features[i])).toBeLessThan(1e-6);
      }
    }
  });

  it('فایل vectors.json با استخراج‌کننده هم‌خوان است', () => {
    const raw = JSON.parse(fs.readFileSync(vectorsPath, 'utf8'));
    for (const c of raw.cases) {
      const got = extractFeatures(c.acc, c.gyro);
      for (let i = 0; i < 14; i += 1) {
        expect(Math.abs(got[i] - c.features[i])).toBeLessThan(1e-6);
      }
    }
  });

  it('پیش‌غربال سقوط شدید را نگه می‌دارد', () => {
    expect(preScreen([3, 0.2, 1, 0.5, 2.8, 0.3, 0.4, 1, 0.05, 0.4, 5, 0.1, 80, 4])).toBe(true);
  });

  it('پیش‌غربال پیاده‌روی را رد می‌کند', () => {
    expect(preScreen([1.4, 0.9, 1.1, 0.1, 0.5, 0.2, 1.1, 1.1, 0.1, 0.95, 1, 0.8, 5, 20])).toBe(false);
  });

  it('پیش‌غربال با تغییر وضعیت بدون افت آزاد را می‌پذیرد', () => {
    expect(preScreen([2.5, 0.8, 1.2, 0.4, 1.7, 0.4, 1, 1, 0.1, 0.9, 2, 0.2, 50, 3])).toBe(true);
  });

  it('پنجره‌ی ناقص هم ۱۴ عدد می‌دهد', () => {
    const acc = Array.from({ length: 10 }, () => ({ ax: 0, ay: 0, az: G }));
    const gyro = Array.from({ length: 10 }, () => ({ gx: 0, gy: 0, gz: 0 }));
    expect(extractFeatures(acc, gyro)).toHaveLength(14);
  });

  it('شاخص قله بین ۰ و ۱ است', () => {
    const fixtures = fixtureVectors();
    const f = extractFeatures(fixtures.cases[0].acc, fixtures.cases[0].gyro);
    expect(f[5]).toBeGreaterThanOrEqual(0);
    expect(f[5]).toBeLessThanOrEqual(1);
  });

  it('smvRange برابر max منهای min است', () => {
    const fixtures = fixtureVectors();
    const f = extractFeatures(fixtures.cases[0].acc, fixtures.cases[0].gyro);
    expect(Math.abs(f[4] - (f[0] - f[1]))).toBeLessThan(1e-9);
  });
});
