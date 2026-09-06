import { describe, it, expect } from 'vitest';
import { isScheduleActive } from '../src/services/geofenceEngine.js';

describe('isScheduleActive', () => {
  it('بدون زمان‌بندی همیشه فعال است', () => {
    expect(isScheduleActive(null)).toBe(true);
    expect(isScheduleActive({ windows: [] })).toBe(true);
  });

  it('پنجره‌ی عبور از نیمه‌شب', () => {
    const schedule = {
      timezone: 'UTC',
      windows: [{ days: [0, 1, 2, 3, 4, 5, 6], from: '22:00', to: '06:00' }],
    };
    expect(isScheduleActive(schedule, new Date('2026-03-02T23:00:00Z'))).toBe(true);
    expect(isScheduleActive(schedule, new Date('2026-03-02T03:00:00Z'))).toBe(true);
    expect(isScheduleActive(schedule, new Date('2026-03-02T12:00:00Z'))).toBe(false);
  });

  it('فقط جمعه در تهران', () => {
    const schedule = {
      timezone: 'Asia/Tehran',
      windows: [{ days: [5], from: '08:00', to: '18:00' }],
    };
    // جمعه ۶ مارس ۲۰۲۶
    expect(isScheduleActive(schedule, new Date('2026-03-06T08:30:00+03:30'))).toBe(true);
    // شنبه
    expect(isScheduleActive(schedule, new Date('2026-03-07T08:30:00+03:30'))).toBe(false);
  });

  it('UTC در برابر تهران برای همان لحظه', () => {
    const tehran = {
      timezone: 'Asia/Tehran',
      windows: [{ days: [0, 1, 2, 3, 4, 5, 6], from: '00:30', to: '01:00' }],
    };
    const utc = {
      timezone: 'UTC',
      windows: [{ days: [0, 1, 2, 3, 4, 5, 6], from: '00:30', to: '01:00' }],
    };
    const instant = new Date('2026-03-02T00:45:00Z');
    expect(isScheduleActive(utc, instant)).toBe(true);
    expect(isScheduleActive(tehran, instant)).toBe(false);
  });
});
