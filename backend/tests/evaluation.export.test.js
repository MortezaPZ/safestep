import { expect, it } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { parseSyntheticCsv } from '../scripts/evaluation/synthetic-roc.js';

it('accepts only complete synthetic rows and does not treat SisFall as synthetic', () => {
  const header = 'label,' + Array.from({ length: 14 }, (_, i) => `f${i + 1}`).join(',');
  const valid = `# SYNTHETIC\n${header}\n0,${Array(14).fill(0).join(',')}\n1,${Array(14).fill(1).join(',')}\n`;
  expect(parseSyntheticCsv(valid)).toHaveLength(2);
  expect(parseSyntheticCsv(valid.replace('# SYNTHETIC\n', ''))).toBeNull();
  expect(parseSyntheticCsv(valid.replace('0,0,0', '0,,0'))).toBeNull();
  expect(parseSyntheticCsv('subject_id,recording_id,label,' + header + '\nSA01,F01,1,' + Array(15).fill(1).join(','))).toBeNull();
});

it('preserves historical and synthetic ROC files for an incompatible input', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'safestep-roc-test-'));
  const input = path.join(dir, 'sisfall.csv');
  const roc = path.join(dir, 'roc-threshold.csv');
  const historical = path.join(dir, 'roc-sisfall-loo.csv');
  const fence = path.join(dir, 'geofence-false-alarms.csv');
  try {
    fs.writeFileSync(input, 'subject_id,recording_id,label,f1\nSA01,F01,1,2\n');
    fs.writeFileSync(roc, 'original synthetic ROC');
    fs.writeFileSync(historical, 'historical model ROC');
    const child = spawnSync(process.execPath, ['scripts/evaluation/export-charts.js'], {
      env: { ...process.env, EVALUATION_OUTPUT_DIR: dir, EVALUATION_DATASET_CSV: input },
      encoding: 'utf8', timeout: 15000,
    });
    expect(child.status).toBe(0);
    expect(fs.readFileSync(roc, 'utf8')).toBe('original synthetic ROC');
    expect(fs.readFileSync(historical, 'utf8')).toBe('historical model ROC');
    expect(fs.existsSync(fence)).toBe(true);
  } finally {
    for (const file of [input, roc, historical, fence]) if (fs.existsSync(file)) fs.unlinkSync(file);
    fs.rmdirSync(dir);
  }
});
