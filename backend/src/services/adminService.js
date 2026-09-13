/**
 * سرویس مدیریت سامانه.
 *
 * ── مرزِ اختیار ادمین، تصمیم محصولی است نه فنی ──────────────────────────
 * ادمین می‌تواند حساب‌ها و دستگاه‌ها را مدیریت کند و سلامت سامانه را ببیند،
 * اما **به موقعیت زنده یا تاریخچه‌ی مسیر هیچ کاربری دسترسی ندارد**. این
 * محصول برای حفظ استقلال افراد ساخته شده؛ اگر یک نقش سرتاسری بتواند موقعیت
 * همه را ببیند، همان چیزی را نقض کرده‌ایم که ادعای محافظت از آن را داریم.
 *
 * دسترسی به موقعیت فقط از یک مسیر ممکن است: رابطه‌ی سرپرستیِ فعال که خودِ
 * کاربر اصلی آن را با کد دعوت ساخته باشد.
 *
 * هر کنش تغییردهنده در این فایل، در جدول `audit_logs` ثبت می‌شود.
 */
import {
  ROLES,
  USER_STATUS,
  AUDIT_ACTIONS,
  ALL_ROLES,
  ALL_USER_STATUSES,
} from '../config/constants.js';
import adminRepository from '../repositories/adminRepository.js';
import logRepository from '../repositories/logRepository.js';
import telemetryService from './telemetryService.js';
import auditService from './auditService.js';
import * as fallEventRepository from '../repositories/fallEventRepository.js';
import { loadModel } from './fallDetection/classifier.js';
import { invalidateAccountState } from '../middleware/auth.js';
import { badRequest, notFound, conflict } from '../utils/errors.js';
import logger from '../utils/logger.js';

const log = logger.child({ module: 'admin' });

/**
 * بی‌اثر کردن کاراکترهای ویژه‌ی LIKE در عبارت جست‌وجو.
 * بدون این، جست‌وجوی «‎%‎» کل جدول را برمی‌گرداند و «‎_‎» به‌جای خودش،
 * «هر کاراکتری» معنا می‌دهد — نه تزریق SQL، ولی رفتار غلط.
 */
function escapeLike(value) {
  if (!value) return null;
  const trimmed = String(value).trim();
  if (trimmed === '') return null;
  return trimmed.replace(/[\\%_]/g, (ch) => `\\${ch}`).slice(0, 60);
}

/* ═══════════════════════════ کاربران ═══════════════════════════ */

export async function listUsers(filters = {}) {
  const params = {
    search: escapeLike(filters.search),
    role: filters.role ?? null,
    status: filters.status ?? null,
    limit: filters.limit ?? 50,
    offset: filters.offset ?? 0,
  };

  const [users, total] = await Promise.all([
    adminRepository.listUsers(params),
    adminRepository.countUsers(params),
  ]);

  return { users, total, limit: params.limit, offset: params.offset };
}

export async function getUser(userId) {
  const user = await adminRepository.getUser(userId);
  if (!user) throw notFound('کاربر یافت نشد.');
  return { user };
}

export async function listIdentityDocuments(filters = {}) {
  return { documents: await adminRepository.listIdentityDocuments(filters) };
}

export async function submitIdentityDocument(userId, documentType, imageUrl) {
  return { document: await adminRepository.createIdentityDocument(userId, documentType, imageUrl) };
}

export async function reviewIdentityDocument(id, status, actor, reason = null) {
  const document = await adminRepository.reviewIdentityDocument(id, status, actor.id, reason);
  if (!document) throw notFound('مدرک یافت نشد.');
  return { document };
}

/**
 * تعلیق حساب.
 * حساب معلق می‌تواند وارد شود اما هیچ عملیاتی انجام نمی‌دهد — این عمدی است:
 * کاربر باید پیام روشنِ «حساب شما معلق شده» ببیند، نه «شماره یا رمز نادرست».
 */
export async function suspendUser(userId, reason, actor, req) {
  const target = await adminRepository.getUser(userId);
  if (!target) throw notFound('کاربر یافت نشد.');

  if (target.id === actor.id) {
    throw badRequest('نمی‌توانید حساب خودتان را معلق کنید.');
  }

  if (target.role === ROLES.ADMIN && (await adminRepository.countActiveAdmins(userId)) === 0) {
    throw conflict('این تنها مدیر فعال سامانه است و نمی‌توان معلقش کرد.');
  }

  const user = await adminRepository.setUserStatus(userId, USER_STATUS.SUSPENDED, reason ?? null);
  // تعلیق باید فوری اثر کند، نه پس از انقضای حافظه‌ی نهان
  invalidateAccountState(userId);

  await auditService.record({
    action: AUDIT_ACTIONS.USER_SUSPEND,
    actor,
    entityType: 'user',
    entityId: userId,
    metadata: { reason: reason ?? null, previousStatus: target.status },
    req,
  });

  log.warn('حساب کاربری معلق شد', { userId, by: actor.id });
  return { user };
}

export async function activateUser(userId, actor, req) {
  const target = await adminRepository.getUser(userId);
  if (!target) throw notFound('کاربر یافت نشد.');

  const user = await adminRepository.setUserStatus(userId, USER_STATUS.ACTIVE);
  invalidateAccountState(userId);

  await auditService.record({
    action: AUDIT_ACTIONS.USER_ACTIVATE,
    actor,
    entityType: 'user',
    entityId: userId,
    metadata: { previousStatus: target.status },
    req,
  });

  log.info('حساب کاربری فعال شد', { userId, by: actor.id });
  return { user };
}

/**
 * حذف نرم.
 * ردیف کاربر باقی می‌ماند چون لاگ‌های سنجش و هشدارها به آن ارجاع دارند و
 * حذف سختش یعنی از دست رفتن داده‌ی ارزیابی. برای «حذف واقعیِ داده‌ی
 * موقعیت»، مسیر جداگانه‌ای وجود دارد که خودِ کاربر آن را اجرا می‌کند.
 */
export async function deleteUser(userId, actor, req) {
  const target = await adminRepository.getUser(userId);
  if (!target) throw notFound('کاربر یافت نشد.');

  if (target.id === actor.id) {
    throw badRequest('نمی‌توانید حساب خودتان را حذف کنید.');
  }

  if (target.role === ROLES.ADMIN && (await adminRepository.countActiveAdmins(userId)) === 0) {
    throw conflict('این تنها مدیر فعال سامانه است و نمی‌توان حذفش کرد.');
  }

  const user = await adminRepository.setUserStatus(userId, USER_STATUS.DELETED);
  invalidateAccountState(userId);

  await auditService.record({
    action: AUDIT_ACTIONS.USER_DELETE,
    actor,
    entityType: 'user',
    entityId: userId,
    metadata: { role: target.role },
    req,
  });

  log.warn('حساب کاربری حذف (نرم) شد', { userId, by: actor.id });
  return { user };
}

export async function changeRole(userId, role, actor, req) {
  if (!ALL_ROLES.includes(role)) throw badRequest('نقش نامعتبر است.');

  const target = await adminRepository.getUser(userId);
  if (!target) throw notFound('کاربر یافت نشد.');

  if (target.role === role) return { user: target };

  // برداشتن نقش ادمین از آخرین ادمین، سامانه را بدون مدیر رها می‌کند
  if (
    target.role === ROLES.ADMIN &&
    role !== ROLES.ADMIN &&
    (await adminRepository.countActiveAdmins(userId)) === 0
  ) {
    throw conflict('این تنها مدیر فعال سامانه است؛ ابتدا مدیر دیگری تعریف کنید.');
  }

  const user = await adminRepository.setUserRole(userId, role);
  invalidateAccountState(userId);

  await auditService.record({
    action: AUDIT_ACTIONS.USER_ROLE_CHANGE,
    actor,
    entityType: 'user',
    entityId: userId,
    metadata: { from: target.role, to: role },
    req,
  });

  log.warn('نقش کاربر تغییر کرد', { userId, from: target.role, to: role, by: actor.id });
  return { user };
}

/* ═══════════════════════════ دستگاه‌ها ═══════════════════════════ */

export async function listDevices(filters = {}) {
  const params = {
    userId: filters.userId ?? null,
    platform: filters.platform ?? null,
    includeRevoked: Boolean(filters.includeRevoked),
    limit: filters.limit ?? 50,
    offset: filters.offset ?? 0,
  };

  const [devices, total] = await Promise.all([
    adminRepository.listDevices(params),
    adminRepository.countDevices(params),
  ]);

  return { devices, total, limit: params.limit, offset: params.offset };
}

export async function revokeDevice(deviceId, actor, req) {
  const device = await adminRepository.revokeDevice(deviceId);
  if (!device) throw notFound('دستگاه یافت نشد یا قبلاً ابطال شده است.');

  await auditService.record({
    action: AUDIT_ACTIONS.DEVICE_REVOKE,
    actor,
    entityType: 'device',
    entityId: deviceId,
    metadata: { platform: device.platform, ownerId: device.userId },
    req,
  });

  log.warn('دستگاه ابطال شد', { deviceId, by: actor.id });
  return { device };
}

/* ═══════════════════════════ لاگ‌ها ═══════════════════════════ */

export async function requestLogs(filters = {}) {
  // بافر تخلیه می‌شود تا ادمین آخرین درخواست‌ها را ببیند، نه تصویری ۵ ثانیه قدیمی
  await telemetryService.flush();

  const params = {
    from: filters.from ?? null,
    to: filters.to ?? null,
    route: escapeLike(filters.route),
    minStatus: filters.minStatus ?? null,
    userId: filters.userId ?? null,
    limit: filters.limit ?? 100,
    offset: filters.offset ?? 0,
  };

  const [logs, total] = await Promise.all([
    logRepository.listRequestLogs(params),
    logRepository.countRequestLogs(params),
  ]);

  return { logs, total, limit: params.limit, offset: params.offset };
}

export async function auditLogs(filters = {}) {
  const params = {
    from: filters.from ?? null,
    to: filters.to ?? null,
    action: filters.action ?? null,
    actorUserId: filters.actorUserId ?? null,
    limit: filters.limit ?? 100,
    offset: filters.offset ?? 0,
  };

  const [logs, total] = await Promise.all([
    logRepository.listAuditLogs(params),
    logRepository.countAuditLogs(params),
  ]);

  return { logs, total, limit: params.limit, offset: params.offset };
}

/* ═══════════════════════════ سنجه‌ها ═══════════════════════════ */

/**
 * جدول ارزیابی سامانه — همان اعدادی که در فصل نتایج پایان‌نامه گزارش می‌شوند.
 *
 * @param {{from?: Date, to?: Date}} range
 */
export async function metrics(range = {}) {
  await telemetryService.flush();

  const window = { from: range.from ?? null, to: range.to ?? null };

  const [requests, location, deliveries, slowest, series, falls] = await Promise.all([
    logRepository.requestMetrics(window),
    logRepository.locationMetrics(window),
    logRepository.deliveryMetrics(window),
    logRepository.slowestRoutes({ ...window, limit: 10 }),
    logRepository.dailyRequestSeries({ days: 7 }),
    fallEventRepository.metrics(),
  ]);

  let model = { version: null, datasetKind: null };
  try {
    const loaded = loadModel();
    model = { version: loaded.version, datasetKind: loaded.datasetKind };
  } catch {
    // مدل هنوز آموزش ندیده
  }

  return {
    range: {
      from: window.from ? new Date(window.from).toISOString() : null,
      to: window.to ? new Date(window.to).toISOString() : null,
    },
    requests,
    location,
    deliveries,
    slowestRoutes: slowest,
    dailySeries: series,
    buffer: telemetryService.status(),
    fallDetection: {
      ...falls,
      modelVersion: model.version,
      datasetKind: model.datasetKind,
    },
  };
}

/** نمای کلی صفحه‌ی نخست پنل. */
export async function overview() {
  const [stats, alerts] = await Promise.all([
    adminRepository.overview(),
    adminRepository.recentAlerts(20),
  ]);
  return { stats, recentAlerts: alerts };
}

/** پاک‌سازی لاگ‌های قدیمی‌تر از تعداد روز مشخص. */
export async function purgeLogs(days, actor, req) {
  const n = Number(days);
  if (!Number.isFinite(n) || n < 1 || n > 3650) {
    throw badRequest('تعداد روز باید عددی بین ۱ و ۳۶۵۰ باشد.');
  }

  const result = await logRepository.purgeOlderThan(n);

  await auditService.record({
    action: 'admin.logs.purge',
    actor,
    entityType: 'logs',
    metadata: { days: n, ...result },
    req,
  });

  log.warn('لاگ‌های قدیمی پاک شدند', { days: n, ...result, by: actor.id });
  return result;
}

export const VALID_ROLES = ALL_ROLES;
export const VALID_STATUSES = ALL_USER_STATUSES;

export default {
  listUsers,
  getUser,
  suspendUser,
  activateUser,
  deleteUser,
  changeRole,
  listDevices,
  revokeDevice,
  requestLogs,
  auditLogs,
  metrics,
  overview,
  purgeLogs,
};
