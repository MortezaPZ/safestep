/**
 * پروکسی کاشی نقشه.
 *
 * مرورگر و گوشی در ایران اغلب به tile.openstreetmap.org مستقیم وصل نمی‌شوند.
 * سرور محلی کاشی را می‌گیرد و با همان مبدأ اپ برمی‌گرداند.
 */

const UA = 'Hamghadam/1.0 (local demo; map tiles)';

function sources(z, x, y) {
  return [
    `https://tile.openstreetmap.org/${z}/${x}/${y}.png`,
    `https://a.basemaps.cartocdn.com/rastertiles/voyager/${z}/${x}/${y}.png`,
  ];
}

export function isValidTileCoord(z, x, y) {
  if (!/^\d+$/.test(z) || !/^\d+$/.test(x) || !/^\d+$/.test(y)) return false;
  const zi = Number(z);
  const xi = Number(x);
  const yi = Number(y);
  if (zi < 0 || zi > 19) return false;
  const max = 2 ** zi;
  return xi >= 0 && yi >= 0 && xi < max && yi < max;
}

export async function fetchTilePng(z, x, y) {
  let lastStatus = 0;
  for (const url of sources(z, x, y)) {
    try {
      const res = await fetch(url, {
        headers: { 'User-Agent': UA, Accept: 'image/png,image/*' },
        signal: AbortSignal.timeout(8000),
      });
      lastStatus = res.status;
      if (!res.ok) continue;
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length < 32) continue;
      return buf;
    } catch {
      /* منبع بعدی */
    }
  }
  const error = new Error('tile upstream failed');
  error.status = lastStatus || 502;
  throw error;
}
