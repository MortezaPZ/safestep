/**
 * میان‌افزار لاگ درخواست.
 *
 * به هر درخواست یک شناسه‌ی یکتا می‌دهد، زمان پردازش را اندازه می‌گیرد و پس
 * از ارسال پاسخ، یک ردیف در بافر تله‌متری می‌گذارد.
 *
 * ── چند تصمیم که اهمیت دارند ────────────────────────────────────────────
 *
 * ۱) اندازه‌گیری با `process.hrtime.bigint` انجام می‌شود نه `Date.now`.
 *    دقت Date.now روی ویندوز حدود ۱۵ میلی‌ثانیه است؛ برای پاسخی که خودش
 *    ۳ میلی‌ثانیه طول می‌کشد، یعنی عددِ گزارش‌شده بی‌معناست. این عدد قرار
 *    است در فصل ارزیابی پایان‌نامه بنشیند، پس باید درست باشد.
 *
 * ۲) ثبت روی رویداد `finish` انجام می‌شود، یعنی پس از آنکه پاسخ کامل
 *    فرستاده شد — نه هنگام صدا زدن `res.json`.
 *
 * ۳) مسیر ذخیره‌شده، «الگوی مسیر» است نه مسیر واقعی: ‎/api/v1/alerts/:id‎
 *    و نه ‎/api/v1/alerts/9f3c…‎ — تا شناسه‌ی هیچ کاربر و هیچ هشداری در
 *    لاگ ننشیند. اگر الگو در دسترس نبود (مثلاً ۴۰۴)، مسیر خام با جایگزینیِ
 *    شناسه‌ها ذخیره می‌شود.
 *
 * ۴) مسیرهای پرتکرار و کم‌ارزش (فایل‌های ایستا و ‎/health‎) لاگ نمی‌شوند؛
 *    وگرنه جدول از داده‌ای پر می‌شود که هیچ سؤالی را جواب نمی‌دهد.
 */
import crypto from 'node:crypto';
import telemetryService from '../services/telemetryService.js';

/** کلاینت‌های شناخته‌شده. هر مقدار دیگری نادیده گرفته می‌شود تا هدر دلخواه در لاگ ننشیند. */
const KNOWN_CLIENTS = new Set(['flutter-android', 'flutter-ios', 'web', 'admin', 'test']);

/** الگوهایی که در لاگ ثبت نمی‌شوند. */
const SKIP_PREFIXES = ['/health', '/favicon', '/css/', '/js/', '/vendor/', '/assets/'];

const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g;
const LONG_NUM_RE = /\/\d{4,}/g;

/** پاک‌سازی مسیر خام از شناسه‌ها، برای وقتی الگوی مسیر در دسترس نیست. */
function scrubPath(pathname) {
  return String(pathname).replace(UUID_RE, ':id').replace(LONG_NUM_RE, '/:n');
}

/**
 * الگوی مسیر.
 *
 * از `req.originalUrl` ساخته می‌شود و نه از `req.baseUrl + req.route.path`.
 * دلیلش یک رفتار ظریف در Express است: وقتی خطایی از داخل روتر بیرون می‌زند
 * (مثلاً ۴۰۱ یا ۴۰۴)، `req.baseUrl` هنگام خروج از روتر به مقدار قبلی
 * برگردانده می‌شود و مسیر بدون پیشوند `/api/v1` ثبت می‌شود — یعنی همان
 * درخواست، بسته به موفق یا ناموفق بودنش، زیر دو نامِ متفاوت لاگ می‌شد و
 * تجمیعِ سنجه‌ها بی‌معنا می‌گشت.
 *
 * شناسه‌ها با جایگزینی الگویی حذف می‌شوند، پس خروجی همان الگوی مستندشده
 * است: ‎/api/v1/alerts/:id/read‎.
 */
function routePattern(req) {
  const pathname = (req.originalUrl || req.url || req.path).split('?')[0];
  return scrubPath(pathname) || '/';
}

const shouldSkip = (pathname) => SKIP_PREFIXES.some((p) => pathname.startsWith(p));

const toInt = (value) => {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n) : null;
};

export function requestLog(req, res, next) {
  // شناسه‌ی درخواست: اگر کلاینت خودش فرستاده و معتبر بود همان استفاده می‌شود
  // تا بتوان یک عملیات را از اپ تا دیتابیس دنبال کرد.
  const incoming = req.headers['x-request-id'];
  req.requestId =
    typeof incoming === 'string' && /^[0-9a-fA-F-]{36}$/.test(incoming)
      ? incoming
      : crypto.randomUUID();

  res.setHeader('X-Request-Id', req.requestId);

  if (shouldSkip(req.path)) return next();

  const startedAt = process.hrtime.bigint();

  res.on('finish', () => {
    const latencyMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
    const clientHeader = String(req.headers['x-client'] ?? '').toLowerCase();

    telemetryService.recordRequest({
      requestId: req.requestId,
      userId: req.user?.id ?? null,
      method: req.method,
      route: routePattern(req),
      statusCode: res.statusCode,
      // گرد کردن به بالا: پاسخ زیر یک میلی‌ثانیه نباید صفر گزارش شود
      latencyMs: Math.max(1, Math.round(latencyMs)),
      requestBytes: toInt(req.headers['content-length']),
      responseBytes: toInt(res.getHeader('content-length')),
      // کد خطا را میان‌افزار خطا اینجا گذاشته است
      errorCode: res.locals?.errorCode ?? null,
      clientKind: KNOWN_CLIENTS.has(clientHeader) ? clientHeader : null,
      ipHash: telemetryService.hashIp(req.ip),
    });
  });

  return next();
}

export default requestLog;
