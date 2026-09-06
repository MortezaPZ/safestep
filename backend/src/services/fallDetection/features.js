/**
 * استخراج ۱۴ ویژگی از پنجره‌ی ۳ ثانیه‌ای (۱۵۰ نمونه در ۵۰ هرتز).
 * شتاب بر حسب m/s² است و به g تبدیل می‌شود. الگوریتم باید با نسخه‌ی Dart یکی باشد.
 */
export const G = 9.80665;
export const WINDOW = 150;
export const HZ = 50;

function mag(x, y, z) {
  return Math.sqrt(x * x + y * y + z * z);
}

function mean(arr) {
  if (arr.length === 0) return 0;
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

function std(arr) {
  if (arr.length < 2) return 0;
  const m = mean(arr);
  const v = arr.reduce((s, x) => s + (x - m) ** 2, 0) / arr.length;
  return Math.sqrt(v);
}

function clip(i, n) {
  return Math.max(0, Math.min(n - 1, i));
}

/**
 * @param {{ax:number,ay:number,az:number}[]} acc
 * @param {{gx:number,gy:number,gz:number}[]} gyro
 * @returns {number[]}
 */
export function extractFeatures(acc, gyro) {
  const n = WINDOW;
  const a = acc.length >= n ? acc.slice(0, n) : acc;
  const g = gyro.length >= n ? gyro.slice(0, n) : gyro;
  const smv = a.map((s) => mag(s.ax, s.ay, s.az) / G);

  let peak = 0;
  for (let i = 1; i < smv.length; i += 1) {
    if (smv[i] > smv[peak]) peak = i;
  }

  const smvMax = smv[peak] ?? 0;
  const smvMin = Math.min(...smv);
  const smvMean = mean(smv);
  const smvStd = std(smv);
  const smvRange = smvMax - smvMin;
  const impactIndexRatio = peak / n;

  const preStart = clip(peak - Math.round(0.5 * HZ), smv.length);
  const preImpactMean = mean(smv.slice(preStart, peak));

  const postA = clip(peak + HZ, smv.length);
  const postB = clip(peak + 2 * HZ, smv.length);
  const postWin = smv.slice(postA, Math.max(postA + 1, postB));
  const postImpactMean = mean(postWin);
  const postImpactStd = std(postWin);

  const ffStart = clip(peak - Math.round(0.4 * HZ), smv.length);
  const freeFallMinBeforePeak = Math.min(...smv.slice(ffStart, peak === ffStart ? peak + 1 : peak));

  const gyroMag = g.map((s) => mag(s.gx, s.gy, s.gz));
  const gyroMax = Math.max(0, ...gyroMag);
  const gyroPost = gyroMag.slice(postA, Math.max(postA + 1, postB));
  const gyroMeanPost = mean(gyroPost);

  const first = a.slice(0, Math.round(0.5 * HZ));
  const last = a.slice(-Math.round(0.5 * HZ));
  const m1 = [
    mean(first.map((s) => s.ax)),
    mean(first.map((s) => s.ay)),
    mean(first.map((s) => s.az)),
  ];
  const m2 = [
    mean(last.map((s) => s.ax)),
    mean(last.map((s) => s.ay)),
    mean(last.map((s) => s.az)),
  ];
  const n1 = mag(...m1) || 1;
  const n2 = mag(...m2) || 1;
  const dot = (m1[0] / n1) * (m2[0] / n2) + (m1[1] / n1) * (m2[1] / n2) + (m1[2] / n1) * (m2[2] / n2);
  const orientationChangeDeg = (Math.acos(Math.min(1, Math.max(-1, dot))) * 180) / Math.PI;

  let zeroCrossingsSmv = 0;
  for (let i = 1; i < smv.length; i += 1) {
    const a0 = smv[i - 1] - 1;
    const a1 = smv[i] - 1;
    if ((a0 < 0 && a1 >= 0) || (a0 > 0 && a1 <= 0)) zeroCrossingsSmv += 1;
  }

  return [
    smvMax,
    smvMin,
    smvMean,
    smvStd,
    smvRange,
    impactIndexRatio,
    preImpactMean,
    postImpactMean,
    postImpactStd,
    freeFallMinBeforePeak,
    gyroMax,
    gyroMeanPost,
    orientationChangeDeg,
    zeroCrossingsSmv,
  ];
}

export function preScreen(features) {
  const smvMax = features[0];
  const freeFallMinBeforePeak = features[9];
  const orientationChangeDeg = features[12];
  return smvMax >= 2.3 && (freeFallMinBeforePeak <= 0.6 || orientationChangeDeg >= 45);
}

export default { extractFeatures, preScreen, G, WINDOW, HZ };
