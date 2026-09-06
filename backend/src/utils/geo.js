/**
 * توابع محاسبات جغرافیایی — خالص (pure) و مستقل از فریم‌ورک تا کاملاً تست‌پذیر باشند.
 * هیچ وابستگی به Express، دیتابیس یا PostGIS ندارد.
 */

/** شعاع میانگین کره‌ی زمین بر حسب متر (مدل کروی WGS-84). */
export const EARTH_RADIUS_M = 6_371_008.8;

const toRad = (deg) => (deg * Math.PI) / 180;
const toDeg = (rad) => (rad * 180) / Math.PI;

/**
 * اعتبارسنجی یک مختصات. مقادیر خارج از بازه‌ی معتبر باید زودهنگام رد شوند،
 * وگرنه خطای بی‌سروصدا تا موتور Geofence نشت می‌کند.
 */
export function isValidCoordinate(lat, lng) {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

export function assertValidCoordinate(lat, lng) {
  if (!isValidCoordinate(lat, lng)) {
    throw new RangeError(`مختصات نامعتبر است: lat=${lat}, lng=${lng}`);
  }
}

/**
 * فاصله‌ی دایره‌ی بزرگ بین دو نقطه بر حسب متر — فرمول Haversine.
 *
 * چرا Haversine و نه فاصله‌ی اقلیدسی: در عرض جغرافیایی تهران (~۳۵.۷ درجه)
 * یک درجه طول جغرافیایی حدود ۹۰ کیلومتر و یک درجه عرض حدود ۱۱۱ کیلومتر است.
 * محاسبه‌ی اقلیدسی روی درجات، خطای بیش از ۲۰٪ در جهت شرقی‌غربی تولید می‌کند
 * که برای محدوده‌ای با شعاع ۱۵۰ متر یعنی ۳۰ متر خطا — بیشتر از خودِ هیسترزیس.
 *
 * @returns {number} فاصله بر حسب متر
 */
export function haversineDistance(lat1, lng1, lat2, lng2) {
  assertValidCoordinate(lat1, lng1);
  assertValidCoordinate(lat2, lng2);

  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δφ = toRad(lat2 - lat1);
  const Δλ = toRad(lng2 - lng1);

  const sinHalfΔφ = Math.sin(Δφ / 2);
  const sinHalfΔλ = Math.sin(Δλ / 2);

  const a = sinHalfΔφ * sinHalfΔφ + Math.cos(φ1) * Math.cos(φ2) * sinHalfΔλ * sinHalfΔλ;
  // clamp برای جلوگیری از خطای ممیز شناور در نقاط تقریباً متقارن
  const c = 2 * Math.atan2(Math.sqrt(Math.min(1, a)), Math.sqrt(Math.max(0, 1 - a)));

  return EARTH_RADIUS_M * c;
}

/**
 * زاویه‌ی سمت (bearing) اولیه از نقطه‌ی ۱ به نقطه‌ی ۲، بر حسب درجه (۰..۳۶۰).
 * برای چرخاندن آیکون کاربر روی نقشه در جهت حرکت استفاده می‌شود.
 */
export function bearing(lat1, lng1, lat2, lng2) {
  assertValidCoordinate(lat1, lng1);
  assertValidCoordinate(lat2, lng2);

  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δλ = toRad(lng2 - lng1);

  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x = Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);

  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

/**
 * محاسبه‌ی نقطه‌ی مقصد از یک نقطه‌ی مبدأ، با فاصله و زاویه‌ی مشخص.
 * شبیه‌ساز موقعیت از این تابع برای درون‌یابی روی مسیر استفاده می‌کند.
 */
export function destinationPoint(lat, lng, distanceM, bearingDeg) {
  assertValidCoordinate(lat, lng);

  const δ = distanceM / EARTH_RADIUS_M;
  const θ = toRad(bearingDeg);
  const φ1 = toRad(lat);
  const λ1 = toRad(lng);

  const sinφ2 = Math.sin(φ1) * Math.cos(δ) + Math.cos(φ1) * Math.sin(δ) * Math.cos(θ);
  const φ2 = Math.asin(Math.min(1, Math.max(-1, sinφ2)));
  const λ2 =
    λ1 +
    Math.atan2(
      Math.sin(θ) * Math.sin(δ) * Math.cos(φ1),
      Math.cos(δ) - Math.sin(φ1) * sinφ2,
    );

  return {
    lat: toDeg(φ2),
    lng: ((toDeg(λ2) + 540) % 360) - 180, // نرمال‌سازی به بازه‌ی ‎-180..180
  };
}

/**
 * مرکز ثقل مجموعه‌ای از نقاط.
 * برای پنجره‌های کوچک (چند صد متر) میانگین ساده‌ی مختصات خطای ناچیزی دارد
 * و نسبت به میانگین برداری سه‌بعدی بسیار ارزان‌تر است. مرز نصف‌النهار ۱۸۰ درجه
 * در دامنه‌ی این محصول (ایران) رخ نمی‌دهد و عمداً مدیریت نشده است.
 */
export function centroid(points) {
  if (!Array.isArray(points) || points.length === 0) {
    throw new Error('محاسبه‌ی مرکز ثقل روی مجموعه‌ی خالی ممکن نیست');
  }
  let sumLat = 0;
  let sumLng = 0;
  for (const p of points) {
    assertValidCoordinate(p.lat, p.lng);
    sumLat += p.lat;
    sumLng += p.lng;
  }
  return { lat: sumLat / points.length, lng: sumLng / points.length };
}

/**
 * بیشترین فاصله‌ی نقاط از مرکز ثقل — «شعاع پراکندگی».
 * سنجه‌ی اصلی تشخیص توقف طولانی: اگر همه‌ی پینگ‌های یک پنجره‌ی زمانی
 * درون دایره‌ای به این شعاع بمانند، یعنی کاربر عملاً حرکتی نکرده است.
 */
export function dispersionRadius(points) {
  const c = centroid(points);
  let max = 0;
  for (const p of points) {
    const d = haversineDistance(c.lat, c.lng, p.lat, p.lng);
    if (d > max) max = d;
  }
  return { center: c, radiusM: max };
}

/** طول کل یک مسیر (مجموع فاصله‌ی نقاط متوالی) بر حسب متر. */
export function pathLength(points) {
  if (!Array.isArray(points) || points.length < 2) return 0;
  let total = 0;
  for (let i = 1; i < points.length; i += 1) {
    total += haversineDistance(
      points[i - 1].lat,
      points[i - 1].lng,
      points[i].lat,
      points[i].lng,
    );
  }
  return total;
}

/**
 * درون‌یابی خطی بین دو نقطه با ضریب t در بازه‌ی ‎[0,1]‎.
 * برای فاصله‌های کوتاه (< چند کیلومتر) اختلافش با درون‌یابی کروی زیر یک متر است.
 */
export function interpolate(from, to, t) {
  const clamped = Math.min(1, Math.max(0, t));
  return {
    lat: from.lat + (to.lat - from.lat) * clamped,
    lng: from.lng + (to.lng - from.lng) * clamped,
  };
}

/** گرد کردن مختصات برای نمایش/لاگ — پیش‌فرض ۵ رقم اعشار ≈ دقت ۱ متر. */
export function roundCoord(value, digits = 5) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function toMetersLocal(lat0, lng0, lat, lng) {
  const x = toRad(lng - lng0) * EARTH_RADIUS_M * Math.cos(toRad(lat0));
  const y = toRad(lat - lat0) * EARTH_RADIUS_M;
  return { x, y };
}

function ring(points) {
  return points.map((p) => (Array.isArray(p) ? { lat: p[0], lng: p[1] } : p));
}

/**
 * نقطه داخل چندضلعی — پرتوی افقی (ray casting).
 * نقطه روی یال به‌صورت داخل شمارش می‌شود تا لرزش مرز هشدار جعلی نسازد.
 */
export function pointInPolygon(point, polygon) {
  const verts = ring(polygon);
  if (verts.length < 3) return false;
  const { lat, lng } = point;
  let inside = false;
  for (let i = 0, j = verts.length - 1; i < verts.length; j = i, i += 1) {
    const yi = verts[i].lat;
    const xi = verts[i].lng;
    const yj = verts[j].lat;
    const xj = verts[j].lng;
    const intersect =
      (yi > lat) !== (yj > lat) &&
      lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function distPointToSegmentM(p, a, b) {
  const pa = toMetersLocal(p.lat, p.lng, a.lat, a.lng);
  const pb = toMetersLocal(p.lat, p.lng, b.lat, b.lng);
  const abx = pb.x - pa.x;
  const aby = pb.y - pa.y;
  const len2 = abx * abx + aby * aby;
  let t = 0;
  if (len2 > 0) {
    t = Math.max(0, Math.min(1, (-pa.x * abx + -pa.y * aby) / len2));
  }
  const fx = pa.x + t * abx;
  const fy = pa.y + t * aby;
  return Math.sqrt(fx * fx + fy * fy);
}

/**
 * کمینه فاصله تا یال‌های چندضلعی.
 * پای عمود در تصویر equirectangular حول نقطه محاسبه می‌شود؛ برای محدوده‌های
 * کوچک‌تر از حدود ۵ کیلومتر خطا چند متر است.
 */
export function distanceToPolygonEdgeM(point, polygon) {
  const verts = ring(polygon);
  if (verts.length < 2) return Infinity;
  let min = Infinity;
  for (let i = 0; i < verts.length; i += 1) {
    const a = verts[i];
    const b = verts[(i + 1) % verts.length];
    const d = distPointToSegmentM(point, a, b);
    if (d < min) min = d;
  }
  return min;
}

export function polygonCentroid(polygon) {
  const verts = ring(polygon);
  return centroid(verts);
}

export function polygonPerimeterM(polygon) {
  const verts = ring(polygon);
  if (verts.length < 2) return 0;
  let total = 0;
  for (let i = 0; i < verts.length; i += 1) {
    const a = verts[i];
    const b = verts[(i + 1) % verts.length];
    total += haversineDistance(a.lat, a.lng, b.lat, b.lng);
  }
  return total;
}

/** مساحت تقریبی با فرمول گاوس روی تصویر محلی (متر مربع). */
export function polygonAreaM2(polygon) {
  const verts = ring(polygon);
  if (verts.length < 3) return 0;
  const c = centroid(verts);
  let sum = 0;
  for (let i = 0; i < verts.length; i += 1) {
    const a = toMetersLocal(c.lat, c.lng, verts[i].lat, verts[i].lng);
    const b = toMetersLocal(c.lat, c.lng, verts[(i + 1) % verts.length].lat, verts[(i + 1) % verts.length].lng);
    sum += a.x * b.y - b.x * a.y;
  }
  return Math.abs(sum) / 2;
}

export function inscribedRadiusEstimateM(polygon) {
  const verts = ring(polygon);
  if (verts.length < 3) return 0;
  const c = centroid(verts);
  return distanceToPolygonEdgeM(c, verts);
}

/** فاصله علامت‌دار تا مرز: منفی داخل، مثبت بیرون. */
export function signedDistanceToZoneM(point, zone) {
  if (zone.shape === 'polygon' && zone.polygon) {
    const edge = distanceToPolygonEdgeM(point, zone.polygon);
    return pointInPolygon(point, zone.polygon) ? -edge : edge;
  }
  const d = haversineDistance(point.lat, point.lng, zone.centerLat, zone.centerLng);
  return d - zone.radiusM;
}
