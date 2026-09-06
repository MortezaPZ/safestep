/**
 * تعریف تمام مسیرهای API نسخه‌ی ۱.
 *
 * هر مسیر سه چیز را صریح اعلام می‌کند: احراز هویت، اعتبارسنجی ورودی و
 * محدودیت نرخ. با یک نگاه به این فایل می‌توان دید هر endpoint چه چیزی
 * می‌خواهد و چه کسی اجازه‌ی صدا زدنش را دارد.
 */
import { Router } from 'express';
import { z } from 'zod';

import * as authController from '../controllers/authController.js';
import {
  guardianship,
  location,
  safeZone,
  alert,
  sos,
  settings,
  device,
  simulator,
} from '../controllers/index.js';

import * as admin from '../controllers/adminController.js';
import { requireAuth, requireAdmin } from '../middleware/auth.js';
import { validate, schemas } from '../middleware/validate.js';
import { authLimiter, sosLimiter, inviteLimiter, generalLimiter } from '../middleware/rateLimit.js';
import {
  ALL_ALERT_TYPES,
  ALL_ROLES,
  ALL_USER_STATUSES,
  SELF_SIGNUP_ROLES,
  LOCATION_PROVIDERS,
  AUDIT_ACTIONS,
  PLATFORMS,
  ALL_ZONE_SHAPES,
} from '../config/constants.js';

const router = Router();

/* ═══════════════════════════ احراز هویت ═══════════════════════════ */

router.post(
  '/auth/register',
  authLimiter,
  validate({
    body: z.object({
      phone: schemas.phone,
      password: schemas.password,
      fullName: schemas.fullName,
      // نقش ادمین عمداً در این فهرست نیست: هیچ‌کس نمی‌تواند خودش را مدیر
      // سامانه ثبت کند. ادمین فقط با اسکریپت سرور یا توسط ادمین موجود ساخته می‌شود.
      role: z.enum(SELF_SIGNUP_ROLES).default('primary'),
    }),
  }),
  authController.register,
);

router.post(
  '/auth/login',
  authLimiter,
  validate({
    body: z.object({
      phone: schemas.phone,
      password: z.string().min(1, 'رمز عبور را وارد کنید.'),
    }),
  }),
  authController.login,
);

router.post(
  '/auth/refresh',
  validate({ body: z.object({ refreshToken: z.string().min(10, 'توکن معتبر نیست.') }) }),
  authController.refresh,
);

router.post(
  '/auth/logout',
  validate({ body: z.object({ refreshToken: z.string().optional() }) }),
  authController.logout,
);

router.post('/auth/logout-all', requireAuth, authController.logoutAll);
router.get('/auth/me', requireAuth, authController.me);

/* ═══════════════════════ سرپرستی و کد دعوت ═══════════════════════ */

router.post(
  '/guardianships/invites',
  requireAuth,
  inviteLimiter,
  validate({ body: z.object({ permissions: schemas.permissions }) }),
  guardianship.createInvite,
);

router.get('/guardianships/invites', requireAuth, guardianship.listInvites);

router.delete(
  '/guardianships/invites/:id',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  guardianship.cancelInvite,
);

router.post(
  '/guardianships/redeem',
  requireAuth,
  inviteLimiter,
  validate({ body: z.object({ code: schemas.inviteCode }) }),
  guardianship.redeem,
);

router.get('/guardianships', requireAuth, guardianship.list);

router.patch(
  '/guardianships/:id',
  requireAuth,
  validate({
    params: z.object({ id: schemas.uuid }),
    body: z.object({ permissions: schemas.permissions }),
  }),
  guardianship.updatePermissions,
);

router.delete(
  '/guardianships/:id',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  guardianship.revoke,
);

/* ═══════════════════════════ موقعیت ═══════════════════════════ */

router.post(
  '/locations/ping',
  requireAuth,
  generalLimiter,
  validate({
    body: z.object({
      lat: schemas.lat,
      lng: schemas.lng,
      accuracyM: z.number().min(0).max(10_000).optional(),
      speedMps: z.number().min(0).max(200).optional(),
      headingDeg: z.number().min(0).max(360).optional(),
      batteryLevel: z.number().int().min(0).max(100).optional(),
      isSimulated: z.boolean().default(false),
      // شناسه‌ی یکتای سمت کلاینت — پایه‌ی بی‌اثرسازی تکرار در صف آفلاین
      clientUuid: schemas.uuid.optional(),
      provider: z.enum(LOCATION_PROVIDERS).optional(),
      isQueuedReplay: z.boolean().default(false),
      recordedAt: z.coerce.date().optional(),
    }),
  }),
  location.ping,
);

/**
 * تخلیه‌ی صف آفلاین اپ.
 * سقف ۲۰۰ نقطه در هر درخواست: با بازه‌ی پیش‌فرض ۳۰ ثانیه یعنی حدود ۱۰۰
 * دقیقه قطعی اینترنت در یک درخواست جبران می‌شود، و هم‌زمان اندازه‌ی بدنه
 * زیر سقف ۲۵۶ کیلوبایتِ سرور می‌ماند.
 */
router.post(
  '/locations/batch',
  requireAuth,
  generalLimiter,
  validate({
    body: z.object({
      pings: z
        .array(
          z.object({
            lat: schemas.lat,
            lng: schemas.lng,
            accuracyM: z.number().min(0).max(10_000).optional(),
            speedMps: z.number().min(0).max(200).optional(),
            headingDeg: z.number().min(0).max(360).optional(),
            batteryLevel: z.number().int().min(0).max(100).optional(),
            isSimulated: z.boolean().default(false),
            clientUuid: schemas.uuid.optional(),
            provider: z.enum(LOCATION_PROVIDERS).optional(),
            isQueuedReplay: z.boolean().optional(),
            recordedAt: z.coerce.date(),
          }),
        )
        .min(1, 'حداقل یک نقطه باید ارسال شود.')
        .max(200, 'در هر درخواست حداکثر ۲۰۰ نقطه پذیرفته می‌شود.'),
    }),
  }),
  location.batch,
);

router.get('/locations/status', requireAuth, location.ownStatus);
router.get('/locations/watching', requireAuth, location.watchList);

router.get(
  '/locations/current',
  requireAuth,
  validate({ query: z.object({ userId: schemas.uuid.optional() }) }),
  location.current,
);

router.get(
  '/locations/history',
  requireAuth,
  validate({
    query: z.object({
      userId: schemas.uuid.optional(),
      from: schemas.isoDate,
      to: schemas.isoDate,
      limit: schemas.numericQuery(1, 5000, 2000),
    }),
  }),
  location.history,
);

router.get(
  '/locations/history/days',
  requireAuth,
  validate({ query: z.object({ userId: schemas.uuid.optional() }) }),
  location.historyDays,
);

router.delete(
  '/locations/history',
  requireAuth,
  validate({
    query: z.object({
      from: schemas.isoDate.optional(),
      to: schemas.isoDate.optional(),
    }),
  }),
  location.deleteHistory,
);

router.put(
  '/locations/sharing',
  requireAuth,
  validate({ body: z.object({ enabled: z.boolean() }) }),
  location.setSharing,
);

/* ═══════════════════════ محدوده‌های امن ═══════════════════════ */

const latLngPair = z.union([
  z.tuple([schemas.lat, schemas.lng]),
  z.object({ lat: schemas.lat, lng: schemas.lng }),
]);

const scheduleSchema = z.object({
  timezone: z.string().min(1).max(64).optional(),
  windows: z.array(z.object({
    days: z.array(z.number().int().min(0).max(6)).min(1),
    from: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
    to: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  })).min(1),
}).optional().nullable();

const safeZoneBody = {
  name: z.string().trim().min(1, 'نام محدوده را وارد کنید.').max(60, 'نام بیش از حد طولانی است.'),
  shape: z.enum(ALL_ZONE_SHAPES).optional(),
  centerLat: schemas.lat.optional(),
  centerLng: schemas.lng.optional(),
  radiusM: schemas.radiusM.optional(),
  polygon: z.array(latLngPair).min(3).max(60).optional(),
  schedule: scheduleSchema,
  alertOnEnter: z.boolean().optional(),
  alertOnExit: z.boolean().optional(),
  dwellAlertMinutes: z.number().int().min(1).max(1440).optional().nullable(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'کد رنگ معتبر نیست.').optional(),
  icon: z.string().max(32).optional(),
};

const safeZoneCreate = z.object(safeZoneBody).superRefine((val, ctx) => {
  const shape = val.shape ?? 'circle';
  if (shape === 'polygon' && !val.polygon) {
    ctx.addIssue({ code: 'custom', message: 'برای چندضلعی آرایه‌ی رأس لازم است.', path: ['polygon'] });
  }
  if (shape === 'circle' && (val.centerLat == null || val.centerLng == null || val.radiusM == null)) {
    ctx.addIssue({ code: 'custom', message: 'برای دایره مرکز و شعاع لازم است.', path: ['radiusM'] });
  }
});

router.get('/safe-zones', requireAuth, safeZone.list);

router.post(
  '/safe-zones',
  requireAuth,
  validate({ body: safeZoneCreate }),
  safeZone.create,
);

router.post(
  '/safe-zones/preview',
  requireAuth,
  validate({
    body: z.object({
      shape: z.enum(ALL_ZONE_SHAPES).optional(),
      centerLat: schemas.lat.optional(),
      centerLng: schemas.lng.optional(),
      radiusM: schemas.radiusM.optional(),
      polygon: z.array(latLngPair).min(3).max(60).optional(),
    }),
  }),
  safeZone.preview,
);

router.patch(
  '/safe-zones/:id',
  requireAuth,
  validate({
    params: z.object({ id: schemas.uuid }),
    body: z.object({
      name: safeZoneBody.name.optional(),
      shape: z.enum(ALL_ZONE_SHAPES).optional(),
      centerLat: schemas.lat.optional(),
      centerLng: schemas.lng.optional(),
      radiusM: schemas.radiusM.optional(),
      polygon: z.array(latLngPair).min(3).max(60).optional(),
      schedule: scheduleSchema,
      alertOnEnter: z.boolean().optional(),
      alertOnExit: z.boolean().optional(),
      dwellAlertMinutes: z.number().int().min(1).max(1440).optional().nullable(),
      isActive: z.boolean().optional(),
      color: safeZoneBody.color,
      icon: safeZoneBody.icon,
    }),
  }),
  safeZone.update,
);

router.delete(
  '/safe-zones/:id',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  safeZone.remove,
);

/* ═══════════════════════════ هشدارها ═══════════════════════════ */

router.get(
  '/alerts',
  requireAuth,
  validate({
    query: z.object({
      userId: schemas.uuid.optional(),
      types: z
        .string()
        .optional()
        .refine(
          (v) => !v || v.split(',').every((t) => ALL_ALERT_TYPES.includes(t.trim())),
          { message: 'نوع هشدار نامعتبر است.' },
        ),
      unreadOnly: z
        .union([z.string(), z.boolean()])
        .optional()
        .transform((v) => v === true || v === 'true'),
      limit: schemas.numericQuery(1, 500, 100),
      before: schemas.isoDate.optional(),
    }),
  }),
  alert.list,
);

router.post(
  '/alerts/:id/read',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  alert.markRead,
);

router.post('/alerts/read-all', requireAuth, alert.markAllRead);

router.post(
  '/alerts/:id/resolve',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  alert.resolve,
);

/* ═══════════════════════════ SOS ═══════════════════════════ */

router.post(
  '/sos',
  requireAuth,
  sosLimiter,
  validate({
    body: z.object({
      lat: schemas.lat.optional(),
      lng: schemas.lng.optional(),
      accuracyM: z.number().min(0).max(10_000).optional(),
      batteryLevel: z.number().int().min(0).max(100).optional(),
      isSimulated: z.boolean().default(false),
      note: z.string().max(280, 'یادداشت بیش از حد طولانی است.').optional(),
    }),
  }),
  sos.trigger,
);

router.get('/sos/contacts', requireAuth, sos.contacts);
router.get('/sos/config', requireAuth, sos.config);

router.get(
  '/sos/active',
  requireAuth,
  validate({ query: z.object({ userId: schemas.uuid.optional() }) }),
  sos.active,
);

/* ═══════════════════════════ تنظیمات ═══════════════════════════ */

router.get('/settings', requireAuth, settings.get);

router.patch(
  '/settings',
  requireAuth,
  validate({
    body: z.object({
      locationSharingEnabled: z.boolean().optional(),
      longStopMinutes: z.number().int().min(1).max(240).optional(),
      longStopRadiusM: z.number().int().min(5).max(500).optional(),
      alertTypes: z.array(z.enum(ALL_ALERT_TYPES)).optional(),
      theme: z.enum(['light', 'dark', 'system']).optional(),
      language: z.enum(['fa', 'en']).optional(),
      pingIntervalSec: z.number().int().min(5).max(900).optional(),
      backgroundTrackingEnabled: z.boolean().optional(),
      // ترجیحات دسترس‌پذیری روی سرور نگهداری می‌شوند تا با تعویض گوشی از دست نروند
      textScale: z.number().min(0.8).max(2).optional(),
      highContrastEnabled: z.boolean().optional(),
      hapticFeedbackEnabled: z.boolean().optional(),
      locationRetentionDays: z.number().int().min(0).max(3650).optional(),
      adaptivePingEnabled: z.boolean().optional(),
      pingIntervalStationarySec: z.number().int().min(30).max(1800).optional(),
    }),
  }),
  settings.update,
);

/**
 * پیکربندی کلاینت.
 * اپ این را هنگام راه‌اندازی می‌خواند تا بازه‌ی ارسال موقعیت و آستانه‌ها از
 * سرور بیایند، نه از ثابت‌های داخل بیلد — تغییرشان نباید انتشار نسخه‌ی
 * جدید در فروشگاه را لازم کند.
 */
router.get('/config/client', requireAuth, settings.clientConfig);

/* ═══════════════════════════ دستگاه‌ها ═══════════════════════════ */

router.post(
  '/devices',
  requireAuth,
  validate({
    body: z.object({
      platform: z.enum(PLATFORMS),
      pushToken: z.string().max(512).optional(),
      deviceName: z.string().max(80).optional(),
      batteryLevel: z.number().int().min(0).max(100).optional(),
      // شناسه‌ی پایدار نصب: با تعویض توکن FCM، ردیف تکراری ساخته نشود
      installId: schemas.uuid.optional(),
      appVersion: z.string().max(24).optional(),
      osVersion: z.string().max(48).optional(),
      model: z.string().max(64).optional(),
    }),
  }),
  device.register,
);

router.get('/devices', requireAuth, device.list);

router.delete(
  '/devices/:id',
  requireAuth,
  validate({ params: z.object({ id: schemas.uuid }) }),
  device.remove,
);

/* ═══════════════════ شبیه‌ساز موقعیت (حالت نمایش) ═══════════════════ */

router.get('/simulator/routes', requireAuth, simulator.routes);

router.post(
  '/simulator/start',
  requireAuth,
  validate({
    body: z.object({
      routeId: z.string().min(1, 'مسیر را انتخاب کنید.'),
      speedMultiplier: z.number().min(1).max(40).default(8),
      batteryLevel: z.number().int().min(0).max(100).default(78),
    }),
  }),
  simulator.start,
);

router.post('/simulator/stop', requireAuth, simulator.stop);
router.get('/simulator/status', requireAuth, simulator.status);

/* ═══════════════════════ پنل مدیریت (فقط ادمین) ═══════════════════════ */

/**
 * تمام مسیرهای زیر دو گارد دارند: احراز هویت، و سپس نقش ادمین.
 *
 * آنچه در این بخش **نیست** به‌اندازه‌ی آنچه هست اهمیت دارد: هیچ مسیری برای
 * دیدن موقعیت زنده یا تاریخچه‌ی مسیرِ کاربران وجود ندارد. ادمین سامانه را
 * مدیریت می‌کند، نه افراد را. دسترسی به موقعیت فقط از راه رابطه‌ی سرپرستی
 * ممکن است — رابطه‌ای که خودِ کاربر اصلی آن را ساخته باشد.
 */

const adminPaging = {
  limit: schemas.numericQuery(1, 200, 50),
  offset: schemas.numericQuery(0, 100000, 0),
};

router.get('/admin/overview', requireAuth, requireAdmin, admin.overview);

router.get(
  '/admin/users',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      search: z.string().max(60).optional(),
      role: z.enum(ALL_ROLES).optional(),
      status: z.enum(ALL_USER_STATUSES).optional(),
      ...adminPaging,
    }),
  }),
  admin.listUsers,
);

router.get(
  '/admin/users/:id',
  requireAuth,
  requireAdmin,
  validate({ params: z.object({ id: schemas.uuid }) }),
  admin.getUser,
);

router.post(
  '/admin/users/:id/suspend',
  requireAuth,
  requireAdmin,
  validate({
    params: z.object({ id: schemas.uuid }),
    body: z.object({ reason: z.string().trim().max(200).optional() }),
  }),
  admin.suspendUser,
);

router.post(
  '/admin/users/:id/activate',
  requireAuth,
  requireAdmin,
  validate({ params: z.object({ id: schemas.uuid }) }),
  admin.activateUser,
);

router.delete(
  '/admin/users/:id',
  requireAuth,
  requireAdmin,
  validate({ params: z.object({ id: schemas.uuid }) }),
  admin.deleteUser,
);

router.patch(
  '/admin/users/:id/role',
  requireAuth,
  requireAdmin,
  validate({
    params: z.object({ id: schemas.uuid }),
    body: z.object({ role: z.enum(ALL_ROLES) }),
  }),
  admin.changeRole,
);

router.get(
  '/admin/devices',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      userId: schemas.uuid.optional(),
      platform: z.enum(PLATFORMS).optional(),
      includeRevoked: z
        .union([z.string(), z.boolean()])
        .optional()
        .transform((v) => v === true || v === 'true'),
      ...adminPaging,
    }),
  }),
  admin.listDevices,
);

router.post(
  '/admin/devices/:id/revoke',
  requireAuth,
  requireAdmin,
  validate({ params: z.object({ id: schemas.uuid }) }),
  admin.revokeDevice,
);

router.get(
  '/admin/logs/requests',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      from: schemas.isoDate.optional(),
      to: schemas.isoDate.optional(),
      route: z.string().max(120).optional(),
      // فیلتر اختیاری است، پس نمی‌توان از numericQuery با مقدار پیش‌فرض استفاده کرد
      minStatus: z
        .union([z.string(), z.number()])
        .optional()
        .transform((v) => (v === undefined || v === '' ? null : Number(v)))
        .refine((v) => v === null || (Number.isFinite(v) && v >= 100 && v <= 599), {
          message: 'کد وضعیت باید عددی بین ۱۰۰ و ۵۹۹ باشد.',
        }),
      userId: schemas.uuid.optional(),
      limit: schemas.numericQuery(1, 500, 100),
      offset: schemas.numericQuery(0, 100000, 0),
    }),
  }),
  admin.requestLogs,
);

router.get(
  '/admin/logs/audit',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      from: schemas.isoDate.optional(),
      to: schemas.isoDate.optional(),
      action: z.enum(Object.values(AUDIT_ACTIONS)).optional(),
      actorUserId: schemas.uuid.optional(),
      limit: schemas.numericQuery(1, 500, 100),
      offset: schemas.numericQuery(0, 100000, 0),
    }),
  }),
  admin.auditLogs,
);

router.post(
  '/admin/logs/purge',
  requireAuth,
  requireAdmin,
  validate({ body: z.object({ olderThanDays: z.number().int().min(1).max(3650) }) }),
  admin.purgeLogs,
);

/** جدول ارزیابی سامانه — دقت موقعیت‌یابی و تأخیر سیستم. */
router.get(
  '/admin/metrics',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      from: schemas.isoDate.optional(),
      to: schemas.isoDate.optional(),
    }),
  }),
  admin.metrics,
);

router.get(
  '/admin/notifications/outbox',
  requireAuth,
  requireAdmin,
  validate({
    query: z.object({
      status: z.enum(['pending', 'sent', 'failed', 'abandoned']).optional(),
      limit: z.coerce.number().int().min(1).max(200).optional(),
      offset: z.coerce.number().int().min(0).optional(),
    }),
  }),
  admin.listOutbox,
);

router.post(
  '/admin/notifications/outbox/:id/retry',
  requireAuth,
  requireAdmin,
  validate({
    params: z.object({ id: z.coerce.number().int().positive() }),
  }),
  admin.retryOutbox,
);

export default router;
