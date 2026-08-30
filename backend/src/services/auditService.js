/**
 * سرویس حسابرسی — «چه کسی چه کاری کرد».
 *
 * برخلاف تله‌متری، این یکی بافر نمی‌شود و مستقیم نوشته می‌شود: تعداد این
 * رویدادها کم است و از دست رفتنشان هنگام خاموش شدن ناگهانی سرور، دقیقاً
 * همان حالتی است که یک لاگ حسابرسی باید جلویش را بگیرد.
 *
 * اما نوشتن آن هرگز عملیات اصلی را نمی‌شکند: اگر ثبت لاگ شکست بخورد،
 * خطا بلعیده و در کنسول ثبت می‌شود. کاربری که حسابش را معلق کرده‌ایم نباید
 * به‌خاطر خطای جدول لاگ، پیام «خطای سرور» ببیند.
 */
import logRepository from '../repositories/logRepository.js';
import { hashIp } from './telemetryService.js';
import logger from '../utils/logger.js';

const log = logger.child({ module: 'audit' });

/** کلیدهایی که هرگز نباید در metadata لاگ حسابرسی بنشینند. */
const FORBIDDEN_KEYS = new Set([
  'lat', 'lng', 'latitude', 'longitude', 'centerLat', 'centerLng',
  'password', 'passwordHash', 'token', 'accessToken', 'refreshToken',
  'code', 'codeHash', 'pushToken',
]);

/**
 * پاک‌سازی metadata پیش از نوشتن.
 * این تابع، اجرایی‌کننده‌ی قاعده‌ی «هیچ مختصات و هیچ رازی در لاگ» است —
 * تکیه بر یادآوریِ برنامه‌نویس کافی نیست، چون یک بار فراموشی یعنی نشت دائمی.
 */
function sanitize(metadata) {
  if (!metadata || typeof metadata !== 'object') return {};
  const out = {};
  for (const [key, value] of Object.entries(metadata)) {
    if (FORBIDDEN_KEYS.has(key)) continue;
    if (value === null || value === undefined) continue;
    if (typeof value === 'object') {
      out[key] = Array.isArray(value) ? value.slice(0, 20) : sanitize(value);
    } else {
      out[key] = typeof value === 'string' ? value.slice(0, 500) : value;
    }
  }
  return out;
}

/**
 * ثبت یک رویداد حسابرسی.
 *
 * @param {object} params
 * @param {string}  params.action یکی از AUDIT_ACTIONS
 * @param {object}  [params.actor] ‎{ id, role }‎ — معمولاً همان req.user
 * @param {string}  [params.entityType]
 * @param {string}  [params.entityId]
 * @param {object}  [params.metadata]
 * @param {object}  [params.req] درخواست، برای استخراج IP و شناسه‌ی درخواست
 */
export async function record({ action, actor, entityType, entityId, metadata, req }) {
  try {
    await logRepository.insertAuditLog({
      actorUserId: actor?.id ?? null,
      actorRole: actor?.role ?? null,
      action,
      entityType: entityType ?? null,
      entityId: entityId ?? null,
      metadata: sanitize(metadata),
      ipHash: req ? hashIp(req.ip) : null,
      requestId: req?.requestId ?? null,
    });
  } catch (error) {
    log.warn('ثبت لاگ حسابرسی شکست خورد', { action, error: error.message });
  }
}

/** نسخه‌ی «فراموشش کن» — وقتی نتیجه‌ی ثبت اهمیتی برای مسیر جاری ندارد. */
export function recordAsync(params) {
  record(params).catch(() => {});
}

export default { record, recordAsync };
