/**
 * کنترلرهای سرپرستی، موقعیت، محدوده، هشدار، تنظیمات، دستگاه و شبیه‌ساز.
 *
 * این کنترلرها کوتاه‌اند چون تمام منطق در لایه‌ی سرویس است؛ وظیفه‌ی اینجا
 * فقط استخراج ورودی از درخواست و برگرداندن پاسخ است.
 */
import guardianshipService from '../services/guardianshipService.js';
import locationService from '../services/locationService.js';
import safeZoneService from '../services/safeZoneService.js';
import alertService from '../services/alertService.js';
import sosService from '../services/sosService.js';
import simulatorService from '../services/simulatorService.js';
import fallService from '../services/fallService.js';
import { cannedPositiveFeatures } from '../services/fallDetection/classifier.js';
import { forbidden } from '../utils/errors.js';
import * as userRepository from '../repositories/userRepository.js';
import * as deviceRepository from '../repositories/deviceRepository.js';
import { asyncHandler } from '../middleware/error.js';
import { randomUUID } from 'node:crypto';
import env from '../config/env.js';
import { WS_EVENTS, ALL_ALERT_TYPES } from '../config/constants.js';

/** ساخت پاسخ پیکربندی کلاینت از روی تنظیمات کاربر و محیط سرور. */
function buildClientConfig(settingsRow) {
  return {
    apiVersion: 'v1',
    tracking: {
      // اپ با این بازه پینگ می‌فرستد؛ کاربر می‌تواند در تنظیمات تغییرش دهد
      pingIntervalSec: settingsRow?.pingIntervalSec ?? 30,
      backgroundTrackingEnabled: settingsRow?.backgroundTrackingEnabled ?? true,
      // سقف دسته‌ی صف آفلاین، هم‌راستا با اعتبارسنجی مسیر /locations/batch
      maxBatchSize: 200,
      // پس از این مدت سکوت، سرور موقعیت را «قطع‌شده» می‌داند
      gpsLostAfterSec: env.gpsLostAfterSec,
    },
    geofence: {
      hysteresisM: env.geofence.hysteresisM,
      debounceCount: env.geofence.debounceCount,
      cooldownSec: env.geofence.cooldownSec,
    },
    adaptivePing: {
      enabled: settingsRow?.adaptivePingEnabled !== false,
      movingIntervalSec: settingsRow?.pingIntervalSec ?? 30,
      stationaryIntervalSec: settingsRow?.pingIntervalStationarySec ?? 120,
      stationarySpeedMps: 0.5,
      stationaryAfterSec: 300,
    },
    accessibility: {
      textScale: settingsRow?.textScale ?? 1,
      highContrastEnabled: settingsRow?.highContrastEnabled ?? false,
      hapticFeedbackEnabled: settingsRow?.hapticFeedbackEnabled ?? true,
    },
    alerts: { types: ALL_ALERT_TYPES },
    realtime: { events: WS_EVENTS },
    features: {
      demoMode: env.demo.enabled,
      // فازهای بعد؛ اپ از همین پرچم‌ها می‌فهمد چه چیزی هنوز فعال نیست
      pushNotifications: Boolean(
        env.notification.fcmServiceAccountPath || env.notification.fcmServiceAccountJson,
      ),
      fallDetection: true,
      fallCountdownSec: settingsRow?.fallCountdownSec ?? 30,
      fallDetectionEnabled: settingsRow?.fallDetectionEnabled !== false,
    },
  };
}

/* ─────────────────────────── سرپرستی ─────────────────────────── */

export const guardianship = {
  createInvite: asyncHandler(async (req, res) => {
    const result = await guardianshipService.createInvite(req.user.id, req.body.permissions);
    res.status(201).json(result);
  }),

  listInvites: asyncHandler(async (req, res) => {
    res.json({ invites: await guardianshipService.listInvites(req.user.id) });
  }),

  cancelInvite: asyncHandler(async (req, res) => {
    res.json(await guardianshipService.cancelInvite(req.params.id, req.user.id));
  }),

  redeem: asyncHandler(async (req, res) => {
    const result = await guardianshipService.redeemInvite(req.body.code, req.user.id);
    res.status(201).json(result);
  }),

  list: asyncHandler(async (req, res) => {
    res.json(await guardianshipService.listAll(req.user.id));
  }),

  updatePermissions: asyncHandler(async (req, res) => {
    const result = await guardianshipService.updatePermissions(
      req.params.id,
      req.user.id,
      req.body.permissions,
    );
    res.json(result);
  }),

  revoke: asyncHandler(async (req, res) => {
    res.json(await guardianshipService.revoke(req.params.id, req.user.id));
  }),
};

/* ─────────────────────────── موقعیت ─────────────────────────── */

export const location = {
  ping: asyncHandler(async (req, res) => {
    const result = await locationService.ingestPing(req.user.id, req.body);
    res.status(201).json(result);
  }),

  current: asyncHandler(async (req, res) => {
    const subjectId = req.query.userId ?? req.user.id;
    res.json(await locationService.getCurrentLocation(req.user.id, subjectId));
  }),

  ownStatus: asyncHandler(async (req, res) => {
    res.json(await locationService.getOwnStatus(req.user.id));
  }),

  watchList: asyncHandler(async (req, res) => {
    res.json({ watching: await locationService.getWatchList(req.user.id) });
  }),

  history: asyncHandler(async (req, res) => {
    const subjectId = req.query.userId ?? req.user.id;
    const { from, to, limit } = req.query;
    res.json(await locationService.getHistory(req.user.id, subjectId, { from, to, limit }));
  }),

  historyDays: asyncHandler(async (req, res) => {
    const subjectId = req.query.userId ?? req.user.id;
    res.json({ days: await locationService.getHistoryDays(req.user.id, subjectId) });
  }),

  deleteHistory: asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    res.json(await locationService.deleteHistory(req.user.id, { from, to }));
  }),

  batch: asyncHandler(async (req, res) => {
    const result = await locationService.ingestBatch(req.user.id, { pings: req.body.pings });
    res.status(201).json(result);
  }),

  setSharing: asyncHandler(async (req, res) => {
    const settings = await locationService.setLocationSharing(req.user.id, req.body.enabled);
    res.json({ settings });
  }),
};

/* ─────────────────────── محدوده‌های امن ─────────────────────── */

export const safeZone = {
  list: asyncHandler(async (req, res) => {
    res.json({ zones: await safeZoneService.list(req.user.id) });
  }),

  create: asyncHandler(async (req, res) => {
    res.status(201).json(await safeZoneService.create(req.user.id, req.body));
  }),

  update: asyncHandler(async (req, res) => {
    res.json(await safeZoneService.update(req.params.id, req.user.id, req.body));
  }),

  remove: asyncHandler(async (req, res) => {
    res.json(await safeZoneService.remove(req.params.id, req.user.id));
  }),

  preview: asyncHandler(async (req, res) => {
    res.json(await safeZoneService.preview(req.user.id, req.body));
  }),
};

/* ─────────────────────────── هشدارها ─────────────────────────── */

export const alert = {
  list: asyncHandler(async (req, res) => {
    const { types, unreadOnly, limit, before, userId } = req.query;
    res.json(
      await alertService.listAlerts(req.user.id, {
        types: types ? String(types).split(',').filter(Boolean) : undefined,
        unreadOnly,
        limit,
        before,
        subjectId: userId,
      }),
    );
  }),

  markRead: asyncHandler(async (req, res) => {
    res.json(await alertService.markRead(req.params.id, req.user.id));
  }),

  markAllRead: asyncHandler(async (req, res) => {
    res.json(await alertService.markAllRead(req.user.id));
  }),

  resolve: asyncHandler(async (req, res) => {
    res.json(await alertService.resolveAlert(req.params.id, req.user.id));
  }),
};

/* ─────────────────────────── SOS ─────────────────────────── */

export const sos = {
  trigger: asyncHandler(async (req, res) => {
    const result = await sosService.triggerSos(req.user.id, req.body ?? {});
    res.status(201).json(result);
  }),

  contacts: asyncHandler(async (req, res) => {
    res.json(await sosService.emergencyContacts(req.user.id));
  }),

  config: asyncHandler(async (_req, res) => {
    res.json(sosService.sosConfig());
  }),

  active: asyncHandler(async (req, res) => {
    const subjectId = req.query.userId ?? req.user.id;
    res.json({ alert: await sosService.activeSos(subjectId) });
  }),
};

/* ─────────────────────────── تنظیمات ─────────────────────────── */

export const settings = {
  get: asyncHandler(async (req, res) => {
    res.json({ settings: await userRepository.getSettings(req.user.id) });
  }),

  update: asyncHandler(async (req, res) => {
    res.json({ settings: await userRepository.updateSettings(req.user.id, req.body) });
  }),

  /**
   * پیکربندی کلاینت — چیزهایی که اپ باید بداند ولی نباید داخل بیلدش ثابت شوند.
   * با این، تغییر بازه‌ی ارسال موقعیت یا آستانه‌ها نیاز به انتشار نسخه‌ی
   * جدید در فروشگاه ندارد.
   */
  clientConfig: asyncHandler(async (req, res) => {
    const settingsRow = await userRepository.getSettings(req.user.id);
    res.json(buildClientConfig(settingsRow));
  }),
};

/* ─────────────────────────── دستگاه‌ها ─────────────────────────── */

export const device = {
  register: asyncHandler(async (req, res) => {
    const registered = await deviceRepository.register({ userId: req.user.id, ...req.body });
    res.status(201).json({ device: registered });
  }),

  list: asyncHandler(async (req, res) => {
    res.json({ devices: await deviceRepository.listByUser(req.user.id) });
  }),

  remove: asyncHandler(async (req, res) => {
    const ok = await deviceRepository.remove(req.params.id, req.user.id);
    res.json({ ok });
  }),
};

/* ─────────────────────── شبیه‌ساز (حالت نمایش) ─────────────────────── */

export const simulator = {
  routes: asyncHandler(async (_req, res) => {
    res.json({ routes: simulatorService.listRoutes(), demoMode: true });
  }),

  start: asyncHandler(async (req, res) => {
    const result = await simulatorService.start(req.user.id, req.body);
    res.json(result);
  }),

  stop: asyncHandler(async (req, res) => {
    res.json(simulatorService.stop(req.user.id));
  }),

  status: asyncHandler(async (req, res) => {
    res.json(simulatorService.status(req.user.id));
  }),

  fall: asyncHandler(async (req, res) => {
    if (!env.demo.enabled) throw forbidden('شبیه‌ساز فقط در حالت نمایش فعال است.');
    const features = cannedPositiveFeatures();
    const result = await fallService.detect(req.user, {
      features,
      detectedAt: new Date(),
      lat: req.body.lat,
      lng: req.body.lng,
      clientEventId: req.body.clientEventId ?? randomUUID(),
    }, { source: 'simulator' });
    res.status(201).json(result);
  }),
};

export const falls = {
  detect: asyncHandler(async (req, res) => {
    const result = await fallService.detect(req.user, req.body);
    res.status(201).json(result);
  }),
  feedback: asyncHandler(async (req, res) => {
    res.json(await fallService.submitFeedback(req.user, req.params.id, req.body));
  }),
  reportMissed: asyncHandler(async (req, res) => {
    res.status(201).json(await fallService.reportMissed(req.user, req.body));
  }),
  list: asyncHandler(async (req, res) => {
    res.json(await fallService.listFalls(req.user, req.query));
  }),
};
