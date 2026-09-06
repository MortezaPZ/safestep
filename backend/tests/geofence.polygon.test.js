import { describe, it, expect } from 'vitest';
import {
  pointInPolygon,
  distanceToPolygonEdgeM,
  signedDistanceToZoneM,
} from '../src/utils/geo.js';
import {
  evaluateZoneGeneric,
  DEFAULT_CONFIG,
} from '../src/services/geofenceEngine.js';
import { ZONE_STATE } from '../src/config/constants.js';

/** مربع تقریبی دور ونک/تهران */
const TEHRAN = [
  [35.757, 51.389],
  [35.757, 51.419],
  [35.737, 51.419],
  [35.737, 51.389],
];

const zone = {
  id: 'z1',
  name: 'ونک',
  shape: 'polygon',
  polygon: TEHRAN,
  centerLat: 35.747,
  centerLng: 51.404,
  radiusM: 1500,
};

describe('pointInPolygon', () => {
  it('نقطه داخل چندضلعی محدب', () => {
    expect(pointInPolygon({ lat: 35.747, lng: 51.404 }, TEHRAN)).toBe(true);
  });

  it('نقطه بیرون', () => {
    expect(pointInPolygon({ lat: 35.8, lng: 51.5 }, TEHRAN)).toBe(false);
  });

  it('چندضلعی مقعر (L شکل) نقطه در گوشه‌ی خالی بیرون است', () => {
    const l = [
      [0, 0], [4, 0], [4, 2], [2, 2], [2, 4], [0, 4],
    ];
    expect(pointInPolygon({ lat: 3, lng: 3 }, l)).toBe(false);
    expect(pointInPolygon({ lat: 1, lng: 1 }, l)).toBe(true);
  });
});

describe('distanceToPolygonEdgeM', () => {
  it('فاصله داخل و خارج هم‌مرتبه است', () => {
    const inside = { lat: 35.747, lng: 51.404 };
    const outside = { lat: 35.747, lng: 51.43 };
    const dIn = distanceToPolygonEdgeM(inside, TEHRAN);
    const dOut = distanceToPolygonEdgeM(outside, TEHRAN);
    expect(dIn).toBeGreaterThan(50);
    expect(dOut).toBeGreaterThan(50);
  });
});

describe('هیسترزیس چندضلعی', () => {
  it('لرزش روی مرز هشدار خروج نمی‌دهد', () => {
    let prev = { state: ZONE_STATE.INSIDE, consecutiveCount: 0, pendingState: null };
    const events = [];
    const config = { ...DEFAULT_CONFIG, hysteresisM: 25, debounceCount: 2 };
    for (let i = 0; i < 20; i += 1) {
      const jitter = (i % 2 === 0 ? 0.00005 : -0.00005);
      const point = { lat: 35.757 + jitter, lng: 51.404 };
      const result = evaluateZoneGeneric(point, zone, prev, config);
      if (result.event) events.push(result.event);
      prev = {
        state: result.state,
        consecutiveCount: result.consecutiveCount,
        pendingState: result.pendingState,
      };
    }
    expect(events.filter((e) => e === 'exit')).toHaveLength(0);
  });

  it('خروج واقعی پس از debounce یک رویداد می‌دهد', () => {
    let prev = { state: ZONE_STATE.INSIDE, consecutiveCount: 0, pendingState: null };
    const config = { ...DEFAULT_CONFIG, hysteresisM: 25, debounceCount: 2 };
    const far = { lat: 35.70, lng: 51.50 };
    let events = [];
    for (let i = 0; i < 3; i += 1) {
      const result = evaluateZoneGeneric(far, zone, prev, config);
      if (result.event) events.push(result.event);
      prev = {
        state: result.state,
        consecutiveCount: result.consecutiveCount,
        pendingState: result.pendingState,
      };
    }
    expect(events.filter((e) => e === 'exit')).toHaveLength(1);
    expect(signedDistanceToZoneM(far, zone)).toBeGreaterThan(100);
  });
});
