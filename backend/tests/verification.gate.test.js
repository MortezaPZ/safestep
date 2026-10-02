/**
 * تست رگرسیون قفل مدارک — تأیید می‌کند که قفل هنوز فعال است.
 *
 * دو چیز اثبات می‌شود:
 *   ۱. خودِ middleware واقعاً ۴۰۳ می‌دهد (آزمون واحد مستقیم).
 *   ۲. مسیرهای مورد نظر واقعاً به این middleware سیم‌کشی شده‌اند (بررسی
 *      استاتیک تعریف مسیرها).
 *
 * اگر کسی middleware را بردارد یا requireVerified را از روی مسیری حذف
 * کند، این تست‌ها قرمز می‌شوند.
 *
 * نکتهٔ فنی: env در زمان بارگذاری ماژول خوانده می‌شود، پس تغییر
 * NODE_ENV در حین اجرای تست بی‌فایده است. به همین دلیل middleware مستقیماً
 * با یک req جعلی فراخوانی می‌شود — این دقیقاً همان کدی است که Express
 * در هر درخواست اجرا می‌کند.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'production';
process.env.JWT_ACCESS_SECRET = 'test-secret-not-default-0123456789abcdef0123456789abcdef';
process.env.JWT_REFRESH_SECRET = 'test-refresh-not-default-0123456789abcdef0123456789';
process.env.INVITE_CODE_PEPPER = 'test-pepper-not-default-0123456789abcdef0123456789';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { requireVerified, requireAuth } = await import('../src/middleware/auth.js');

const PASSWORD = 'Test@1234';

const GATED_PATHS = [
  '/api/v1/locations/ping',
  '/api/v1/locations/batch',
  '/api/v1/safe-zones',
  '/api/v1/sos',
  '/api/v1/simulator/start',
  '/api/v1/falls/detect',
];

/** ساختن req/res جعلی — شبیه‌سازی کاری که Express انجام می‌دهد. */
function fakeReq(user) {
  const calls = { status: null, body: null, next: null };
  const req = { user };
  const res = {
    status(code) {
      calls.status = code;
      return this;
    },
    json(body) {
      calls.body = body;
      return this;
    },
  };
  const next = (error) => {
    calls.next = error;
  };
  return { req, res, next, calls };
}

let app;
let unverifiedToken;
let verifiedToken;
let adminToken;

describe('قفل مدارک', () => {
  beforeAll(async () => {
    app = await createApp();
    await runMigrations();
    const { seed } = await import('../src/db/seed.js');
    await seed();
  }, 90_000);

  afterAll(async () => {
    await db.close?.();
  });

  it('middleware: کاربر unverified → ۴۰۳', () => {
    const res = fakeReq({ id: 'u1', role: 'guardian', verificationStatus: 'unverified' });
    requireVerified(res.req, res.res, res.next);
    expect(res.calls.next).toBeInstanceOf(Error);
    expect(res.calls.next.status).toBe(403);
    expect(res.calls.next.message).toMatch(/تأیید مدارک/);
  });

  it('middleware: کاربر verified → عبور', () => {
    const res = fakeReq({ id: 'u2', role: 'guardian', verificationStatus: 'verified' });
    requireVerified(res.req, res.res, res.next);
    expect(res.calls.next).toBeUndefined();
    expect(res.calls.status).toBeNull();
  });

  it('middleware: کاربر pending → ۴۰۳', () => {
    const res = fakeReq({ id: 'u3', role: 'guardian', verificationStatus: 'pending' });
    requireVerified(res.req, res.res, res.next);
    expect(res.calls.next).toBeInstanceOf(Error);
    expect(res.calls.next?.status).toBe(403);
  });

  it('middleware: کاربر rejected → ۴۰۳', () => {
    const res = fakeReq({ id: 'u4', role: 'guardian', verificationStatus: 'rejected' });
    requireVerified(res.req, res.res, res.next);
    expect(res.calls.next).toBeInstanceOf(Error);
    expect(res.calls.next?.status).toBe(403);
  });

  it('middleware: مدیر سامانه حتی اگر unverified باشد معاف است', () => {
    const res = fakeReq({ id: 'u5', role: 'admin', verificationStatus: 'unverified' });
    requireVerified(res.req, res.res, res.next);
    expect(res.calls.next).toBeUndefined();
    expect(res.calls.status).toBeNull();
  });

  it('هر شش مسیر به requireVerified سیم‌کشی شده‌اند (بررسی استاتیک)', () => {
    const source = fs.readFileSync(
      path.resolve(import.meta.dirname, '../src/routes/index.js'),
      'utf8',
    );
    for (const p of GATED_PATHS) {
      // مسیر تعریف شده، و در همان بلوک requireVerified آمده
      const routeIdx = source.indexOf(`'${p.replace('/api/v1', '')}'`);
      expect(routeIdx, `مسیر ${p} پیدا نشد`).toBeGreaterThan(-1);
      const block = source.slice(routeIdx, routeIdx + 400);
      expect(block, `مسیر ${p} به requireVerified سیم‌کشی نشده`).toContain(
        'requireVerified',
      );
    }
  });

  it('middleware روی همهٔ مسیرهای قفل‌شده استفاده شده — شمارش', () => {
    const source = fs.readFileSync(
      path.resolve(import.meta.dirname, '../src/routes/index.js'),
      'utf8',
    );
    const count = (source.match(/requireVerified,/g) || []).length;
    expect(count).toBeGreaterThanOrEqual(6);
  });

  it('migration ۰۰۸ (ستون verification_status) اعمال شده', async () => {
    const { rows } = await db.query(
      `SELECT EXISTS (
         SELECT FROM information_schema.columns
         WHERE table_name = 'users' AND column_name = 'verification_status'
       ) AS exists`,
    );
    expect(rows[0].exists).toBe(true);
  });

  it('seed: حساب ناظر تأییدنشده unverified و بقیه verified', async () => {
    const { rows } = await db.query(
      `SELECT phone, verification_status FROM users ORDER BY phone`,
    );
    const byPhone = Object.fromEntries(rows.map((r) => [r.phone, r.verification_status]));
    expect(byPhone['09121110008']).toBe('unverified');
    expect(byPhone['09121110001']).toBe('verified');
    expect(byPhone['09121110002']).toBe('verified');
    expect(byPhone['09121110003']).toBe('verified');
    expect(byPhone['09121110009']).toBe('verified');
  });
});
