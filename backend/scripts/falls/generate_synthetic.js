/**
 * شبیه‌ساز فیزیک‌محور پنجره‌های سقوط / فعالیت روزمره.
 * بذر ثابت تا خروجی آموزش تکرارپذیر باشد.
 */
import { extractFeatures, G, WINDOW, HZ } from '../../src/services/fallDetection/features.js';

const SEED = 20260906;

function mulberry32(seed) {
  let s = seed >>> 0;
  return () => {
    s += 0x6d2b79f5;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randn(rand) {
  const u = Math.max(1e-12, rand());
  const v = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

function rotate(v, yaw, pitch) {
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  const x1 = v[0] * cy - v[1] * sy;
  const y1 = v[0] * sy + v[1] * cy;
  const z1 = v[2];
  return [x1 * cp + z1 * sp, y1, -x1 * sp + z1 * cp];
}

function windowFromSmv(smvG, gyroMag, gravityStart, gravityEnd, rand) {
  const acc = [];
  const gyro = [];
  for (let i = 0; i < WINDOW; i += 1) {
    const t = i / (WINDOW - 1);
    const gVec = [
      gravityStart[0] * (1 - t) + gravityEnd[0] * t,
      gravityStart[1] * (1 - t) + gravityEnd[1] * t,
      gravityStart[2] * (1 - t) + gravityEnd[2] * t,
    ];
    const gn = Math.hypot(...gVec) || 1;
    const scale = (smvG[i] * G) / gn;
    acc.push({
      ax: gVec[0] * scale + randn(rand) * 0.05 * G,
      ay: gVec[1] * scale + randn(rand) * 0.05 * G,
      az: gVec[2] * scale + randn(rand) * 0.05 * G,
    });
    const gm = gyroMag[i] + Math.abs(randn(rand)) * 0.05;
    gyro.push({ gx: gm * 0.6, gy: gm * 0.3, gz: gm * 0.4 });
  }
  return { acc, gyro };
}

export function generateFallWindow(rand) {
  const smv = new Array(WINDOW).fill(1);
  const gyro = new Array(WINDOW).fill(0.2);
  const ffDur = Math.round((0.3 + rand() * 0.2) * HZ);
  const peak = 50 + Math.floor(rand() * 8);
  const ffStart = peak - ffDur;
  const dip = 0.3 + rand() * 0.3;
    const impact = 3.2 + rand() * 2.5;
  for (let i = Math.max(0, ffStart); i < peak; i += 1) smv[i] = dip;
  smv[peak] = impact;
  smv[Math.min(WINDOW - 1, peak + 1)] = 1.4 + rand() * 0.3;
  for (let i = peak + 2; i < WINDOW; i += 1) smv[i] = 0.95 + rand() * 0.08;
  gyro[peak] = 8 + rand() * 6;
  for (let i = peak + HZ; i < WINDOW; i += 1) gyro[i] = 0.05 + rand() * 0.05;

  const yaw0 = rand() * Math.PI * 2;
  const start = rotate([0, 0, 1], yaw0, 0);
  const end = rotate([0, 0, 1], yaw0 + (0.4 + rand() * 0.6) * Math.PI, 0.3 + rand() * 0.5);
  return windowFromSmv(smv, gyro, start, end, rand);
}

function generateWalk(rand) {
  const smv = [];
  const gyro = [];
  for (let i = 0; i < WINDOW; i += 1) {
    smv.push(1.15 + 0.25 * Math.sin((i / HZ) * 2 * Math.PI * 1.7));
    gyro.push(1.2 + 0.4 * Math.abs(Math.sin((i / HZ) * 2 * Math.PI * 1.7)));
  }
  const g = rotate([0, 0, 1], rand() * 0.2, 0.05);
  return windowFromSmv(smv, gyro, g, g, rand);
}

function generateSit(rand) {
  const smv = new Array(WINDOW).fill(1);
  const gyro = new Array(WINDOW).fill(0.4);
  const peak = 40;
  for (let i = 20; i < 55; i += 1) smv[i] = 1.2 + 0.5 * ((i - 20) / 35);
  smv[peak] = 1.55 + rand() * 0.2;
  for (let i = 55; i < WINDOW; i += 1) smv[i] = 1.02;
  const g = rotate([0, 0, 1], 0, 0.1);
  const g2 = rotate([0, 0, 1], 0.15, 0.2);
  return windowFromSmv(smv, gyro, g, g2, rand);
}

function generateJump(rand) {
  const smv = new Array(WINDOW).fill(1);
  const gyro = new Array(WINDOW).fill(0.8);
  const peak = 40;
  smv[peak] = 1.7 + rand() * 0.35;
  smv[peak - 4] = 0.75;
  for (let i = peak + 8; i < WINDOW; i += 1) smv[i] = 1.05;
  const g = rotate([0, 0, 1], rand(), 0);
  return windowFromSmv(smv, gyro, g, g, rand);
}

function generateLieSlow(rand) {
  const smv = new Array(WINDOW).fill(1);
  const gyro = new Array(WINDOW).fill(0.3);
  for (let i = 0; i < WINDOW; i += 1) smv[i] = 1 + 0.08 * Math.sin(i / 20);
  const g = rotate([0, 0, 1], 0, 0);
  const g2 = rotate([0, 0, 1], 0.2, 0.35);
  return windowFromSmv(smv, gyro, g, g2, rand);
}

function generatePick(rand) {
  const smv = new Array(WINDOW).fill(1);
  const gyro = new Array(WINDOW).fill(0.6);
  for (let i = 30; i < 80; i += 1) smv[i] = 1.15 + 0.2 * Math.sin((i - 30) / 8);
  const g = rotate([0, 0, 1], 0, 0.15);
  return windowFromSmv(smv, gyro, g, g, rand);
}

const ADL = [generateWalk, generateSit, generateJump, generateLieSlow, generatePick];

export function generateDataset({ perClass = 2000, seed = SEED } = {}) {
  const rand = mulberry32(seed);
  const rows = [];
  for (let i = 0; i < perClass; i += 1) {
    const fall = generateFallWindow(rand);
    rows.push({ label: 1, features: extractFeatures(fall.acc, fall.gyro), ...fall });
    const adl = ADL[i % ADL.length](rand);
    rows.push({ label: 0, features: extractFeatures(adl.acc, adl.gyro), ...adl });
  }
  return rows;
}

export function toCsv(rows) {
  const header = '# SYNTHETIC\nlabel,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14';
  const lines = rows.map((r) => [r.label, ...r.features.map((x) => Number(x.toFixed(6)))].join(','));
  return [header, ...lines].join('\n');
}

export function fixtureVectors() {
  const rand = mulberry32(1);
  const fall = generateFallWindow(rand);
  const walk = generateWalk(rand);
  return {
    g: G,
    window: WINDOW,
    hz: HZ,
    cases: [
      {
        name: 'synthetic_fall',
        acc: fall.acc,
        gyro: fall.gyro,
        features: extractFeatures(fall.acc, fall.gyro),
      },
      {
        name: 'synthetic_walk',
        acc: walk.acc,
        gyro: walk.gyro,
        features: extractFeatures(walk.acc, walk.gyro),
      },
    ],
  };
}

export function cannedFallFeatures() {
  const rand = mulberry32(42);
  const w = generateFallWindow(rand);
  return extractFeatures(w.acc, w.gyro);
}
