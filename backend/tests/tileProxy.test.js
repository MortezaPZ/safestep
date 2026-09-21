import { describe, expect, it } from 'vitest';
import { isValidTileCoord } from '../src/services/tileProxy.js';

describe('مختصات کاشی نقشه', () => {
  it('مقادیر صحیح را می‌پذیرد', () => {
    expect(isValidTileCoord('0', '0', '0')).toBe(true);
    expect(isValidTileCoord('2', '3', '1')).toBe(true);
  });

  it('مقادیر نامعتبر را رد می‌کند', () => {
    expect(isValidTileCoord('foo', '0', '0')).toBe(false);
    expect(isValidTileCoord('3', '8', '0')).toBe(false);
    expect(isValidTileCoord('20', '0', '0')).toBe(false);
  });
});
