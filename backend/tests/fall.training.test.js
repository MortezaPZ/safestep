import { describe, expect, it } from 'vitest';
import path from 'node:path';
import { groupFolds, parseCsv, trainFromRows } from '../scripts/falls/train.js';
import {
  convertRecording,
  downsampleTo50Hz,
  parseTxt,
  selectWindowStarts,
} from '../scripts/falls/convert_sisfall.js';
import { thresholdSweepCsv } from '../scripts/falls/train_sisfall.js';

describe('SisFall conversion', () => {
  it('parses nine-channel rows with trailing semicolons and converts physical units', () => {
    const parsed = parseTxt('256,0,0,14.375,0,0,0,0,0;\n');
    expect(parsed.malformed).toBe(0);
    expect(parsed.samples).toHaveLength(1);
    expect(parsed.samples[0].acc.ax).toBeCloseTo(9.80665, 5);
    expect(parsed.samples[0].gyro.gx).toBeCloseTo(Math.PI / 180, 5);
  });

  it('downsamples four 200 Hz samples into one averaged 50 Hz sample', () => {
    const samples = Array.from({ length: 4 }, (_, index) => ({
      acc: { ax: index, ay: 0, az: 0 },
      gyro: { gx: index * 2, gy: 0, gz: 0 },
    }));
    expect(downsampleTo50Hz(samples)).toEqual([{
      acc: { ax: 1.5, ay: 0, az: 0 },
      gyro: { gx: 3, gy: 0, gz: 0 },
    }]);
  });

  it('centers one fall window on the impact and takes two spaced ADL windows', () => {
    const samples = Array.from({ length: 450 }, () => ({
      acc: { ax: 0, ay: 0, az: 9.80665 },
      gyro: { gx: 0, gy: 0, gz: 0 },
    }));
    samples[225].acc.az = 4 * 9.80665;
    expect(selectWindowStarts(samples, 1)).toEqual([150]);
    expect(selectWindowStarts(samples, 0)).toEqual([75, 225]);
  });

  it('keeps subject and recording identifiers in converted feature rows', () => {
    const lines = Array.from({ length: 1200 }, (_, index) => {
      const impact = index === 600 ? 1024 : 256;
      return '0,0,' + impact + ',0,0,0,0,0,0;';
    }).join('\n');
    const result = convertRecording('SA03F01T01.txt', lines);
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0][0]).toBe('SA03');
    expect(result.rows[0][1]).toBe('SA03F01T01');
    expect(result.rows[0][2]).toBe(1);
    expect(result.rows[0]).toHaveLength(17);
  });

  it('uses the subject folder when a SisFall filename disagrees with its folder', () => {
    const lines = Array.from({ length: 1200 }, () => '0,0,256,0,0,0,0,0,0;').join('\n');
    const result = convertRecording(path.join('SA15', 'D17_SE15_R01.txt'), lines);

    expect(result.rows).toHaveLength(2);
    expect(result.rows[0][0]).toBe('SA15');
    expect(result.rows[0][1]).toBe('D17_SE15_R01');
  });

  it('uses out-of-fold recall for the sensitivity column in the threshold CSV', () => {
    const output = thresholdSweepCsv([{
      marginThreshold: 0,
      agreeThreshold: 0.5,
      recall: 0.8,
      falsePositiveRate: 0.1,
      precision: 0.9,
      accuracy: 0.85,
      f1: 0.8471,
      tp: 8,
      fp: 1,
      fn: 2,
      tn: 9,
      source: 'test',
    }]);

    expect(output.split('\n')[1]).toBe('0,0.5,0.8000,0.1000,0.9000,0.8500,0.8471,8,1,2,9,test');
  });
});

describe('nested subject-grouped training', () => {
  const rows = Array.from({ length: 8 * 4 }, (_, index) => {
    const subjectId = 'S' + String(Math.floor(index / 4)).padStart(2, '0');
    const label = index % 2;
    return {
      subjectId,
      recordingId: subjectId + '-R' + index,
      label,
      features: Array.from({ length: 14 }, (_, feature) =>
        label * 2 + feature * 0.01 + Number(subjectId.slice(1)) * 0.001),
    };
  });

  it('keeps every subject wholly inside one fold', () => {
    const folds = groupFolds(rows, 5, 123);
    const assignments = new Map();
    folds.forEach((fold, foldIndex) => fold.forEach((row) => {
      const existing = assignments.get(row.subjectId);
      expect(existing === undefined || existing === foldIndex).toBe(true);
      assignments.set(row.subjectId, foldIndex);
    }));
    expect(folds.flat()).toHaveLength(rows.length);
  });

  it('parses subject metadata and reports out-of-fold ensemble metrics', () => {
    const parsed = parseCsv([
      'subject_id,recording_id,label,' + Array.from({ length: 14 }, (_, i) => 'f' + (i + 1)).join(','),
      'SA01,F01,1,' + Array(14).fill('0.5').join(','),
    ].join('\n'));
    expect(parsed[0].subjectId).toBe('SA01');
    expect(parsed[0].recordingId).toBe('F01');

    const model = trainFromRows(rows);
    expect(model.training.foldStrategy).toContain('subject-grouped');
    expect(model.cv.ensemble.confusion).toEqual(expect.objectContaining({ tp: expect.any(Number) }));
    expect(model.thresholdSweep).toHaveLength(48);
    expect(model.knn.points).toHaveLength(rows.length);
  });
});
