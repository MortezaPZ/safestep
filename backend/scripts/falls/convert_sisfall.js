/**
 * تبدیل فایل‌های خام SisFall به CSV ویژگی.
 * اگر پوشه‌ی raw موجود نباشد، بدون خطا خارج می‌شود.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractFeatures, WINDOW } from '../../src/services/fallDetection/features.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RAW = path.join(ROOT, 'data/falls/raw/SisFall');
const OUT = path.join(ROOT, 'data/falls/dataset.csv');

function parseTxt(text) {
  const acc = [];
  const gyro = [];
  for (const line of text.split(/\r?\n/)) {
    const p = line.trim().split(/[,\s]+/).map(Number);
    if (p.length < 6 || p.some((n) => Number.isNaN(n))) continue;
    acc.push({ ax: p[0], ay: p[1], az: p[2] });
    gyro.push({ gx: p[3], gy: p[4], gz: p[5] });
  }
  return { acc, gyro };
}

function windows(series) {
  const out = [];
  for (let i = 0; i + WINDOW <= series.acc.length; i += WINDOW) {
    out.push({
      acc: series.acc.slice(i, i + WINDOW),
      gyro: series.gyro.slice(i, i + WINDOW),
    });
  }
  return out;
}

export function convertIfPresent() {
  if (!fs.existsSync(RAW)) {
    process.stdout.write('SisFall raw folder missing; skip.\n');
    return null;
  }
  const rows = ['label,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14'];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) {
        walk(full);
        continue;
      }
      if (!name.toLowerCase().endsWith('.txt')) continue;
      const series = parseTxt(fs.readFileSync(full, 'utf8'));
      const isFall = /fall|F\d/i.test(name);
      for (const w of windows(series)) {
        const f = extractFeatures(w.acc, w.gyro);
        rows.push([isFall ? 1 : 0, ...f.map((x) => Number(x.toFixed(6)))].join(','));
      }
    }
  };
  walk(RAW);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, rows.join('\n'), 'utf8');
  return OUT;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) convertIfPresent();
