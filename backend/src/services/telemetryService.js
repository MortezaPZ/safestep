/**
 * سرویس تله‌متری — بافر نوشتنِ لاگ‌های سنجش.
 *
 * ── چرا بافر، و نه نوشتن مستقیم ─────────────────────────────────────────
 * این سرویس روی مسیر داغِ هر درخواست قرار دارد. اگر هر درخواست یک INSERT
 * اضافه بزند، به هر پاسخ چند میلی‌ثانیه اضافه می‌شود — یعنی ابزار اندازه‌گیری،
 * خودِ چیزی را که می‌سنجد خراب می‌کند. به‌جای آن رکوردها در حافظه جمع و
 * به‌صورت دسته‌ای نوشته می‌شوند.
 *
 * ── قواعد ایمنی این بافر ────────────────────────────────────────────────
 *   • سقف اندازه دارد: اگر دیتابیس کند یا قطع شود، حافظه پر نمی‌شود و
 *     قدیمی‌ترین رکوردها کنار گذاشته می‌شوند. لاگ سنجش، هرگز نباید سرویس
 *     اصلی را از کار بیندازد.
 *   • خطای نوشتن لاگ هرگز به کاربر نمی‌رسد؛ فقط در لاگ کنسول ثبت می‌شود.
 *   • در حالت تست خاموش است تا تست‌ها با تایمر پس‌زمینه درگیر نشوند.
 */
import crypto from 'node:crypto';
import env from '../config/env.js';
import logRepository from '../repositories/logRepository.js';
import logger from '../utils/logger.js';

const log = logger.child({ module: 'telemetry' });

/** حداکثر رکورد در حافظه پیش از آنکه قدیمی‌ترین‌ها کنار گذاشته شوند. */
const MAX_BUFFER = 2000;
/** فاصله‌ی تخلیه‌ی خودکار بافر. */
const FLUSH_INTERVAL_MS = 5000;
/** حداکثر رکورد در هر INSERT — تا تعداد پارامترها از سقف Postgres رد نشود. */
const MAX_BATCH = 200;

const buffers = {
  requests: [],
  locations: [],
  deliveries: [],
};

let flushTimer = null;
let flushing = false;
let dropped = 0;

/** آیا نوشتن لاگ فعال است؟ در تست خاموش، مگر آنکه صریحاً روشن شود. */
let enabled = !env.isTest;

/** روشن/خاموش کردن دستی — تست‌های تله‌متری از این استفاده می‌کنند. */
export function setEnabled(value) {
  enabled = Boolean(value);
  if (!enabled) stop();
}

function push(bucket, entry) {
  if (!enabled) return;
  const buffer = buffers[bucket];
  if (buffer.length >= MAX_BUFFER) {
    buffer.shift();
    dropped += 1;
    // هشدار فقط یک بار در هر ۱۰۰۰ رکورد دورریخته، تا خودِ لاگ سیل نشود
    if (dropped % 1000 === 1) {
      log.warn('بافر تله‌متری پر شد؛ رکوردهای قدیمی کنار گذاشته می‌شوند', { dropped });
    }
  }
  buffer.push(entry);
  ensureTimer();
}

function ensureTimer() {
  if (flushTimer || !enabled) return;
  flushTimer = setInterval(() => {
    flush().catch(() => {});
  }, FLUSH_INTERVAL_MS);
  // تایمر نباید مانع خاموش شدن پردازه شود
  if (typeof flushTimer.unref === 'function') flushTimer.unref();
}

/* ═══════════════════════════ ثبت رکورد ═══════════════════════════ */

/** یک درخواست HTTP کامل‌شده. */
export function recordRequest(entry) {
  push('requests', entry);
}

/** یک پینگ موقعیت پردازش‌شده. */
export function recordLocation(entry) {
  push('locations', entry);
}

/** تحویل یک هشدار به یک گیرنده روی یک کانال. */
export function recordDelivery(entry) {
  push('deliveries', entry);
}

/**
 * ثبت مشاهده‌ی هشدار توسط گیرنده.
 * این یکی مستقیم نوشته می‌شود (نه بافر) چون UPDATE است و تعدادش کم.
 */
export async function acknowledgeAlert(alertId, recipientUserId) {
  if (!enabled) return 0;
  try {
    return await logRepository.acknowledgeDelivery(alertId, recipientUserId);
  } catch (error) {
    log.warn('ثبت مشاهده‌ی هشدار شکست خورد', { error: error.message });
    return 0;
  }
}

/* ═══════════════════════════ تخلیه ═══════════════════════════ */

async function drain(bucket, writer) {
  const buffer = buffers[bucket];
  if (buffer.length === 0) return 0;

  const batch = buffer.splice(0, MAX_BATCH);
  try {
    return await writer(batch);
  } catch (error) {
    // رکوردهای ناموفق دور ریخته می‌شوند، نه اینکه دوباره صف شوند: اگر دیتابیس
    // مشکل ساختاری داشته باشد، صف‌کردن مجدد یک حلقه‌ی بی‌پایان می‌سازد.
    log.warn('نوشتن دسته‌ی تله‌متری شکست خورد', { bucket, size: batch.length, error: error.message });
    return 0;
  }
}

/** تخلیه‌ی فوری بافرها. هنگام خاموش شدن سرور هم صدا زده می‌شود. */
export async function flush() {
  if (flushing) return { requests: 0, locations: 0, deliveries: 0 };
  flushing = true;
  try {
    const requests = await drain('requests', logRepository.insertRequestLogs);
    const locations = await drain('locations', logRepository.insertLocationTelemetry);
    const deliveries = await drain('deliveries', logRepository.insertAlertDeliveries);
    return { requests, locations, deliveries };
  } finally {
    flushing = false;
  }
}

/** تخلیه‌ی کامل تا خالی شدن بافر — برای خاموش شدن تمیز و برای تست‌ها. */
export async function flushAll() {
  let guard = 0;
  while (
    (buffers.requests.length > 0 ||
      buffers.locations.length > 0 ||
      buffers.deliveries.length > 0) &&
    guard < 100
  ) {
    // eslint-disable-next-line no-await-in-loop
    await flush();
    guard += 1;
  }
}

/** توقف تایمر پس‌زمینه. */
export function stop() {
  if (flushTimer) {
    clearInterval(flushTimer);
    flushTimer = null;
  }
}

/** وضعیت بافر — در ‎/health و پنل ادمین نمایش داده می‌شود. */
export function status() {
  return {
    enabled,
    pending:
      buffers.requests.length + buffers.locations.length + buffers.deliveries.length,
    dropped,
  };
}

/* ═══════════════════════════ کمکی ═══════════════════════════ */

/**
 * هش IP با HMAC و کلید سرور.
 *
 * IP خام ذخیره نمی‌شود چون داده‌ی شخصی است و لاگ عمر طولانی دارد. با HMAC
 * همچنان می‌توان فهمید «چند درخواست از یک مبدأ آمده»، ولی خودِ IP از روی
 * دیتابیس قابل بازیابی نیست. SHA ساده کافی نبود: فضای IPv4 آن‌قدر کوچک است
 * که کل آن در چند دقیقه قابل جدول‌سازی است — کلید سرور همان چیزی است که
 * این حمله را ناممکن می‌کند.
 */
export function hashIp(ip) {
  if (!ip) return null;
  return crypto
    .createHmac('sha256', env.auth.invitePepper)
    .update(String(ip))
    .digest('hex')
    .slice(0, 64);
}

export default {
  recordRequest,
  recordLocation,
  recordDelivery,
  acknowledgeAlert,
  flush,
  flushAll,
  stop,
  status,
  hashIp,
  setEnabled,
};
