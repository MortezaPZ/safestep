/**
 * Convert raw SisFall recordings into labeled 3-second feature windows.
 *
 * SisFall files are sampled at 200 Hz and contain nine semicolon-terminated
 * values per row: ADXL345 acceleration (x/y/z), ITG-3200 angular rate (x/y/z),
 * then MMA8451Q acceleration (x/y/z). This pipeline uses the first, wider-range
 * ADXL345 sensor and the gyroscope, converts to m/s^2 and rad/s, then averages
 * each block of four samples to produce 50 Hz input for features.js.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractFeatures, G, WINDOW } from '../../src/services/fallDetection/features.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RAW = path.join(ROOT, 'data/falls/raw/SisFall');
const OUT = path.join(ROOT, 'data/falls/dataset.csv');
const SOURCE_HZ = 200;
const TARGET_HZ = 50;
const DECIMATION = SOURCE_HZ / TARGET_HZ;
const ADXL345_LSB_PER_G = 256;
const ITG3200_LSB_PER_DEGREE_PER_SECOND = 14.375;
const CSV_HEADER = [
  'subject_id', 'recording_id', 'label',
  ...Array.from({ length: 14 }, (_, index) => 'f' + (index + 1)),
].join(',');

export function parseTxt(text) {
  const samples = [];
  let malformed = 0;
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const values = trimmed.replace(/;+$/, '').split(/[,\s]+/).filter(Boolean).map(Number);
    if (values.length !== 9 || values.some((value) => !Number.isFinite(value))) {
      malformed += 1;
      continue;
    }
    const accScale = G / ADXL345_LSB_PER_G;
    const gyroScale = Math.PI / (180 * ITG3200_LSB_PER_DEGREE_PER_SECOND);
    samples.push({
      acc: {
        ax: values[0] * accScale,
        ay: values[1] * accScale,
        az: values[2] * accScale,
      },
      gyro: {
        gx: values[3] * gyroScale,
        gy: values[4] * gyroScale,
        gz: values[5] * gyroScale,
      },
    });
  }
  return { samples, malformed };
}

export function downsampleTo50Hz(samples) {
  const output = [];
  for (let start = 0; start + DECIMATION <= samples.length; start += DECIMATION) {
    const group = samples.slice(start, start + DECIMATION);
    const average = (select) =>
      group.reduce((sum, sample) => sum + select(sample), 0) / group.length;
    output.push({
      acc: {
        ax: average((sample) => sample.acc.ax),
        ay: average((sample) => sample.acc.ay),
        az: average((sample) => sample.acc.az),
      },
      gyro: {
        gx: average((sample) => sample.gyro.gx),
        gy: average((sample) => sample.gyro.gy),
        gz: average((sample) => sample.gyro.gz),
      },
    });
  }
  return output;
}

function magnitude(sample) {
  return Math.hypot(sample.acc.ax, sample.acc.ay, sample.acc.az);
}

export function selectWindowStarts(samples, label) {
  if (samples.length < WINDOW) return [];
  const maxStart = samples.length - WINDOW;
  if (label === 1) {
    let peakIndex = 0;
    for (let index = 1; index < samples.length; index += 1) {
      if (magnitude(samples[index]) > magnitude(samples[peakIndex])) peakIndex = index;
    }
    const centered = peakIndex - Math.floor(WINDOW / 2);
    return [Math.max(0, Math.min(maxStart, centered))];
  }
  if (samples.length < WINDOW * 2) return [];
  const first = Math.floor((samples.length - WINDOW * 2) / 2);
  return [first, first + WINDOW];
}

function resolveSubjectId(filePath, stem) {
  const names = [stem, ...filePath.split(path.sep).reverse()];
  for (const name of names) {
    const match = name.match(/^(SA|SE)(\d{2})/i);
    if (match) return match[0].toUpperCase();
  }
  return null;
}

export function convertRecording(filePath, text) {
  const stem = path.basename(filePath, path.extname(filePath));
  const label = /F\d{2}/i.test(stem) ? 1 : /D\d{2}/i.test(stem) ? 0 : null;
  const subjectId = resolveSubjectId(filePath, stem);
  if (label === null || !subjectId) return { rows: [], malformed: 0, skipped: true };

  const parsed = parseTxt(text);
  const samples = downsampleTo50Hz(parsed.samples);
  const starts = selectWindowStarts(samples, label);
  const rows = starts.map((start) => {
    const window = samples.slice(start, start + WINDOW);
    const features = extractFeatures(
      window.map((sample) => sample.acc),
      window.map((sample) => sample.gyro),
    );
    return [
      subjectId,
      stem,
      label,
      ...features.map((value) => Number(value.toFixed(6))),
    ];
  });
  return { rows, malformed: parsed.malformed, skipped: false, label, subjectId };
}

export function convertIfPresent() {
  if (!fs.existsSync(RAW)) {
    process.stdout.write('SisFall raw folder missing; conversion skipped.\n');
    return null;
  }
  const rows = [CSV_HEADER];
  const counts = { fallFiles: 0, adlFiles: 0, windows: 0, malformedLines: 0, skippedFiles: 0 };
  const walk = (directory) => {
    for (const name of fs.readdirSync(directory).sort()) {
      const fullPath = path.join(directory, name);
      if (fs.statSync(fullPath).isDirectory()) {
        walk(fullPath);
        continue;
      }
      if (!name.toLowerCase().endsWith('.txt')) continue;
      const result = convertRecording(fullPath, fs.readFileSync(fullPath, 'utf8'));
      counts.malformedLines += result.malformed;
      if (result.skipped) {
        counts.skippedFiles += 1;
        continue;
      }
      if (result.label === 1) counts.fallFiles += 1;
      else counts.adlFiles += 1;
      counts.windows += result.rows.length;
      rows.push(...result.rows.map((row) => row.join(',')));
    }
  };
  walk(RAW);
  if (counts.windows === 0) throw new Error('No usable SisFall recordings produced feature windows.');
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, rows.join('\n') + '\n', 'utf8');
  process.stdout.write(
    'Converted ' + counts.fallFiles + ' fall files and ' + counts.adlFiles +
    ' ADL files into ' + counts.windows + ' windows at 50 Hz; skipped ' +
    counts.skippedFiles + ' files and ' + counts.malformedLines + ' malformed lines.\n',
  );
  return OUT;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) convertIfPresent();
