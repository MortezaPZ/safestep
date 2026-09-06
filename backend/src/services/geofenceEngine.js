/**
 * موتور Geofence با هیسترزیس و debounce.
 *
 * فاصلهٔ علامت‌دار تا مرز (منفی داخل، مثبت بیرون) برای دایره و چندضلعی
 * یکسان است؛ آستانه‌ها همان باند مرده‌اند.
 */
import { ZONE_STATE } from '../config/constants.js';
import {
  haversineDistance,
  signedDistanceToZoneM,
  inscribedRadiusEstimateM,
} from '../utils/geo.js';

export const DEFAULT_CONFIG = Object.freeze({
  hysteresisM: 25,
  debounceCount: 2,
  cooldownSec: 60,
});

export function thresholdsFor(radiusM, config = DEFAULT_CONFIG) {
  const effective = Math.min(config.hysteresisM, radiusM * 0.4);
  return {
    exitThresholdM: radiusM + effective,
    enterThresholdM: radiusM - effective,
    effectiveHysteresisM: effective,
  };
}

export function effectiveHysteresisForZone(zone, config = DEFAULT_CONFIG) {
  if (zone.shape === 'polygon' && zone.polygon) {
    const inscribed = inscribedRadiusEstimateM(zone.polygon);
    const scale = inscribed > 0 ? inscribed : 50;
    return Math.min(config.hysteresisM, scale * 0.4);
  }
  return Math.min(config.hysteresisM, (zone.radiusM ?? 50) * 0.4);
}

function evaluateSignedTransition(previous, signedM, effectiveHyst, config, thresholds) {
  const prevState = previous?.state ?? ZONE_STATE.UNKNOWN;
  const prevPending = previous?.pendingState ?? null;
  const prevCount = previous?.consecutiveCount ?? 0;

  let observed = null;
  if (signedM > effectiveHyst) observed = ZONE_STATE.OUTSIDE;
  else if (signedM < -effectiveHyst) observed = ZONE_STATE.INSIDE;

  const unchanged = {
    state: prevState,
    consecutiveCount: 0,
    pendingState: null,
    transitioned: false,
    event: null,
    observed,
    thresholds,
  };

  if (observed === null) return unchanged;

  if (prevState === ZONE_STATE.UNKNOWN) {
    return {
      state: observed,
      consecutiveCount: 0,
      pendingState: null,
      transitioned: true,
      event: null,
      observed,
      thresholds,
    };
  }

  if (observed === prevState) return unchanged;

  const count = prevPending === observed ? prevCount + 1 : 1;
  if (count < config.debounceCount) {
    return {
      state: prevState,
      consecutiveCount: count,
      pendingState: observed,
      transitioned: false,
      event: null,
      observed,
      thresholds,
    };
  }

  return {
    state: observed,
    consecutiveCount: 0,
    pendingState: null,
    transitioned: true,
    event: observed === ZONE_STATE.OUTSIDE ? 'exit' : 'enter',
    observed,
    thresholds,
  };
}

export function evaluateTransition(previous, distanceM, radiusM, config = DEFAULT_CONFIG) {
  const thresholds = thresholdsFor(radiusM, config);
  const signedM = distanceM - radiusM;
  return evaluateSignedTransition(
    previous,
    signedM,
    thresholds.effectiveHysteresisM,
    config,
    thresholds,
  );
}

export function evaluateZoneGeneric(point, zone, previous, config = DEFAULT_CONFIG) {
  const signedM = signedDistanceToZoneM(point, zone);
  const hyst = effectiveHysteresisForZone(zone, config);
  const radiusLike = zone.radiusM ?? Math.max(50, hyst / 0.4);
  const thresholds = {
    exitThresholdM: radiusLike + hyst,
    enterThresholdM: radiusLike - hyst,
    effectiveHysteresisM: hyst,
  };
  const result = evaluateSignedTransition(previous, signedM, hyst, config, thresholds);
  const distanceM = Math.abs(signedM) + (signedM < 0 ? 0 : 0);
  const displayDistance = zone.shape === 'polygon'
    ? Math.abs(signedM)
    : haversineDistance(point.lat, point.lng, zone.centerLat, zone.centerLng);
  return {
    ...result,
    signedM,
    distanceM: displayDistance,
    zoneId: zone.id,
    zoneName: zone.name,
  };
}

export function evaluateZone({ lat, lng }, zone, previousState, config = DEFAULT_CONFIG) {
  if (zone.shape === 'polygon' && zone.polygon) {
    return evaluateZoneGeneric({ lat, lng }, zone, previousState, config);
  }
  const distanceM = haversineDistance(lat, lng, zone.centerLat, zone.centerLng);
  const result = evaluateTransition(previousState, distanceM, zone.radiusM, config);
  return { ...result, distanceM, zoneId: zone.id, zoneName: zone.name };
}

export function evaluateAll(point, zones, stateByZoneId, config = DEFAULT_CONFIG) {
  return zones.map((zone) =>
    evaluateZone(point, zone, stateByZoneId.get(zone.id) ?? null, config),
  );
}

export function isCooldownElapsed(lastAlertAt, config = DEFAULT_CONFIG, now = Date.now()) {
  if (!lastAlertAt) return true;
  const elapsedSec = (now - new Date(lastAlertAt).getTime()) / 1000;
  return elapsedSec >= config.cooldownSec;
}

/**
 * زمان‌بندی محدوده. بدون schedule همیشه فعال است.
 * روز هفته همان getDay جاوااسکریپت است (شنبه=۶ … جمعه=۵).
 * پنجره‌ی عبور از نیمه‌شب: from > to یعنی تا فردا صبح.
 */
export function isScheduleActive(schedule, at = new Date()) {
  if (!schedule || !Array.isArray(schedule.windows) || schedule.windows.length === 0) {
    return true;
  }
  const tz = schedule.timezone || 'Asia/Tehran';
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(at);
  const weekday = parts.find((p) => p.type === 'weekday')?.value;
  const map = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const day = map[weekday] ?? at.getDay();
  const hh = Number(parts.find((p) => p.type === 'hour')?.value ?? '0');
  const mm = Number(parts.find((p) => p.type === 'minute')?.value ?? '0');
  const minutes = hh * 60 + mm;

  return schedule.windows.some((w) => {
    const days = w.days ?? [];
    if (!days.includes(day)) return false;
    const [fh, fm] = String(w.from).split(':').map(Number);
    const [th, tm] = String(w.to).split(':').map(Number);
    const fromM = fh * 60 + fm;
    const toM = th * 60 + tm;
    if (fromM <= toM) return minutes >= fromM && minutes < toM;
    return minutes >= fromM || minutes < toM;
  });
}

export function summarizeState(states) {
  if (!states || states.length === 0) {
    return { status: ZONE_STATE.UNKNOWN, insideZones: [], reason: 'no_zones' };
  }

  const inside = states.filter((s) => s.state === ZONE_STATE.INSIDE);
  if (inside.length > 0) {
    return { status: ZONE_STATE.INSIDE, insideZones: inside, reason: 'inside_zone' };
  }

  const known = states.filter((s) => s.state !== ZONE_STATE.UNKNOWN);
  if (known.length === 0) {
    return { status: ZONE_STATE.UNKNOWN, insideZones: [], reason: 'not_evaluated' };
  }

  return { status: ZONE_STATE.OUTSIDE, insideZones: [], reason: 'outside_all_zones' };
}
