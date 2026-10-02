/**
 * سرویس محدوده‌های امن.
 *
 * تغییر هندسه وضعیت هیسترزیس را باطل می‌کند تا شعاع جدید هشدار جعلی نسازد.
 */
import * as safeZoneRepository from '../repositories/safeZoneRepository.js';
import * as locationRepository from '../repositories/locationRepository.js';
import db from '../db/index.js';
import {
  haversineDistance,
  polygonCentroid,
  polygonAreaM2,
  polygonPerimeterM,
  inscribedRadiusEstimateM,
  signedDistanceToZoneM,
} from '../utils/geo.js';
import { thresholdsFor, effectiveHysteresisForZone, isScheduleActive } from './geofenceEngine.js';
import env from '../config/env.js';
import { badRequest, notFound, forbidden } from '../utils/errors.js';
import * as guardianshipRepository from '../repositories/guardianshipRepository.js';
import logger from '../utils/logger.js';

const log = logger.child({ module: 'safe-zone' });
const MAX_ZONES_PER_USER = 20;

const geofenceConfig = {
  hysteresisM: env.geofence.hysteresisM,
  debounceCount: env.geofence.debounceCount,
  cooldownSec: env.geofence.cooldownSec,
};

function parsePolygon(raw) {
  if (!Array.isArray(raw) || raw.length < 3 || raw.length > 60) {
    throw badRequest('چندضلعی باید بین ۳ تا ۶۰ رأس داشته باشد.');
  }
  const pts = raw.map((p) => {
    if (Array.isArray(p) && p.length >= 2) return { lat: Number(p[0]), lng: Number(p[1]) };
    return { lat: Number(p.lat), lng: Number(p.lng) };
  });
  for (let i = 0; i < pts.length; i += 1) {
    const p = pts[i];
    if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng) || p.lat < -90 || p.lat > 90 || p.lng < -180 || p.lng > 180) {
      throw badRequest('رأس چندضلعی نامعتبر است.');
    }
    const prev = pts[i === 0 ? pts.length - 1 : i - 1];
    if (i > 0 && p.lat === prev.lat && p.lng === prev.lng) {
      throw badRequest('رأس تکراری متوالی در چندضلعی مجاز نیست.');
    }
  }
  return pts.map((p) => [p.lat, p.lng]);
}

function parseSchedule(raw) {
  if (raw == null) return null;
  const windows = raw.windows;
  if (!Array.isArray(windows) || windows.length === 0) return null;
  const hhmm = /^([01]\d|2[0-3]):[0-5]\d$/;
  const normalized = windows.map((w) => {
    if (!hhmm.test(w.from) || !hhmm.test(w.to)) {
      throw badRequest('ساعت پنجره باید به صورت HH:MM باشد.');
    }
    const days = (w.days ?? []).map(Number);
    if (days.some((d) => d < 0 || d > 6)) {
      throw badRequest('روز هفته باید بین ۰ و ۶ باشد.');
    }
    return { days, from: w.from, to: w.to };
  });
  return { timezone: raw.timezone || 'Asia/Tehran', windows: normalized };
}

function geometryFromInput(data) {
  const shape = data.shape === 'polygon' ? 'polygon' : 'circle';
  if (shape === 'polygon') {
    const polygon = parsePolygon(data.polygon);
    const c = polygonCentroid(polygon);
    let maxR = 50;
    for (const [lat, lng] of polygon) {
      maxR = Math.max(maxR, haversineDistance(c.lat, c.lng, lat, lng));
    }
    return {
      shape,
      polygon,
      centerLat: c.lat,
      centerLng: c.lng,
      radiusM: Math.min(5000, Math.max(50, Math.round(maxR))),
    };
  }
  if (data.centerLat == null || data.centerLng == null || data.radiusM == null) {
    throw badRequest('برای محدوده‌ی دایره‌ای مرکز و شعاع لازم است.');
  }
  return {
    shape: 'circle',
    polygon: null,
    centerLat: data.centerLat,
    centerLng: data.centerLng,
    radiusM: data.radiusM,
  };
}

function decorate(zone, currentLocation) {
  const hyst = effectiveHysteresisForZone(zone, geofenceConfig);
  const thresholds = zone.shape === 'polygon'
    ? {
      exitThresholdM: Math.round(hyst),
      enterThresholdM: Math.round(-hyst),
      hysteresisM: Math.round(hyst),
    }
    : {
      exitThresholdM: Math.round(thresholdsFor(zone.radiusM, geofenceConfig).exitThresholdM),
      enterThresholdM: Math.round(thresholdsFor(zone.radiusM, geofenceConfig).enterThresholdM),
      hysteresisM: Math.round(thresholdsFor(zone.radiusM, geofenceConfig).effectiveHysteresisM),
    };

  let distanceM = null;
  if (currentLocation) {
    distanceM = Math.round(Math.abs(signedDistanceToZoneM(
      { lat: currentLocation.lat, lng: currentLocation.lng },
      zone,
    )));
  }

  return {
    ...zone,
    thresholds,
    scheduleActive: isScheduleActive(zone.schedule),
    ...(distanceM !== null ? { currentDistanceM: distanceM } : {}),
  };
}

export async function list(userId) {
  const [zones, current] = await Promise.all([
    safeZoneRepository.listByUser(userId),
    locationRepository.findLatest(userId),
  ]);
  return zones.map((z) => decorate(z, current));
}

export async function create(userId, data) {
  const count = await safeZoneRepository.countByUser(userId);
  if (count >= MAX_ZONES_PER_USER) {
    throw badRequest(`حداکثر ${MAX_ZONES_PER_USER} محدوده‌ی امن می‌توانید داشته باشید.`);
  }
  const geom = geometryFromInput(data);
  const zone = await safeZoneRepository.create({
    userId,
    name: data.name,
    ...geom,
    color: data.color,
    icon: data.icon,
    schedule: parseSchedule(data.schedule),
    alertOnEnter: data.alertOnEnter !== false,
    alertOnExit: data.alertOnExit !== false,
    dwellAlertMinutes: data.dwellAlertMinutes ?? null,
  });
  const current = await locationRepository.findLatest(userId);
  log.info('محدوده‌ی امن ساخته شد', { zoneId: zone.id, userId, shape: zone.shape });
  return decorate(zone, current);
}

async function editableOwnerId(actorId, zone) {
  if (!zone) throw notFound('محدوده‌ی امن یافت نشد.');
  if (zone.userId === actorId) return zone.userId;
  const main = await guardianshipRepository.isMainSupervisor(actorId, zone.userId);
  if (!main) throw forbidden('فقط ناظر اصلی می‌تواند این محدوده را تغییر دهد.');
  return zone.userId;
}

export async function update(zoneId, userId, patch) {
  const existing = await safeZoneRepository.findById(zoneId);
  userId = await editableOwnerId(userId, existing);

  let geom = {};
  if (patch.shape || patch.polygon || patch.centerLat !== undefined || patch.radiusM !== undefined) {
    geom = geometryFromInput({ ...existing, ...patch });
  }

  const zone = await safeZoneRepository.update(zoneId, userId, {
    ...patch,
    ...geom,
    schedule: patch.schedule !== undefined ? parseSchedule(patch.schedule) : undefined,
  });
  if (!zone) throw notFound('محدوده‌ی امن یافت نشد.');

  const geometryChanged =
    patch.centerLat !== undefined ||
    patch.centerLng !== undefined ||
    patch.radiusM !== undefined ||
    patch.polygon !== undefined ||
    patch.shape !== undefined ||
    patch.isActive !== undefined;

  if (geometryChanged) {
    await db.query('DELETE FROM zone_states WHERE zone_id = $1 AND user_id = $2', [zoneId, userId]);
  }

  const current = await locationRepository.findLatest(userId);
  return decorate(zone, current);
}

export async function remove(zoneId, userId) {
  const existing = await safeZoneRepository.findById(zoneId);
  userId = await editableOwnerId(userId, existing);
  const removed = await safeZoneRepository.remove(zoneId, userId);
  if (!removed) throw notFound('محدوده‌ی امن یافت نشد.');
  return { ok: true };
}

export async function preview(userId, body) {
  const geom = geometryFromInput(body);
  const fakeZone = { ...geom, shape: geom.shape };
  const hyst = effectiveHysteresisForZone(fakeZone, geofenceConfig);
  const current = await locationRepository.findLatest(userId);

  const extra = geom.shape === 'polygon'
    ? {
      areaM2: Math.round(polygonAreaM2(geom.polygon)),
      perimeterM: Math.round(polygonPerimeterM(geom.polygon)),
      centroid: polygonCentroid(geom.polygon),
      inscribedRadiusM: Math.round(inscribedRadiusEstimateM(geom.polygon)),
    }
    : {};

  const thresholds = {
    exitThresholdM: geom.shape === 'polygon'
      ? Math.round(hyst)
      : Math.round(thresholdsFor(geom.radiusM, geofenceConfig).exitThresholdM),
    enterThresholdM: geom.shape === 'polygon'
      ? Math.round(-hyst)
      : Math.round(thresholdsFor(geom.radiusM, geofenceConfig).enterThresholdM),
    hysteresisM: Math.round(hyst),
  };

  if (!current) {
    return { ...extra, thresholds, currentDistanceM: null, wouldBeInside: null, note: 'هنوز موقعیتی ثبت نشده است.' };
  }

  const signed = signedDistanceToZoneM({ lat: current.lat, lng: current.lng }, fakeZone);
  return {
    ...extra,
    thresholds,
    currentDistanceM: Math.round(Math.abs(signed)),
    wouldBeInside: signed <= 0,
  };
}

export default { list, create, update, remove, preview, MAX_ZONES_PER_USER };
