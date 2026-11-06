import { afterEach, expect, it, vi } from 'vitest';
import { getSosLocation } from '../../web/js/utils/sos-location.js';

afterEach(() => vi.useRealTimers());

it('returns no coordinates when accuracy is out of the accepted server range', async () => {
  const geo = { getCurrentPosition: (success) => success({ coords: { latitude: 35, longitude: 51, accuracy: 12000 } }) };
  expect(await getSosLocation(geo)).toBeNull();
  geo.getCurrentPosition = (success) => success({ coords: { latitude: 35, longitude: 51, accuracy: 8 } });
  expect(await getSosLocation(geo)).toEqual({ lat: 35, lng: 51, accuracyM: 8 });
});

it('finishes even when the browser permission prompt never resolves', async () => {
  vi.useFakeTimers();
  let lateSuccess;
  const result = getSosLocation({ getCurrentPosition: (success) => { lateSuccess = success; } }, 4000);
  await vi.advanceTimersByTimeAsync(4000);
  expect(await result).toBeNull();
  lateSuccess({ coords: { latitude: 35, longitude: 51, accuracy: 5 } });
  expect(await result).toBeNull();
});
