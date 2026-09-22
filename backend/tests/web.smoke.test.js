import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');

let app;

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  await db.close();
});

describe('وب‌اپ ایستا', () => {
  it('صفحه اصلی HTML برمی‌گرداند', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/html/);
    expect(String(res.headers['content-security-policy'] ?? '')).not.toMatch(
      /upgrade-insecure-requests/i,
    );
  });

  it('ماژول اپ را به‌صورت جاوااسکریپت سرو می‌کند نه HTML', async () => {
    const res = await request(app).get('/js/app.js');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/javascript|ecmascript|text/);
    expect(res.text.trimStart().startsWith('<')).toBe(false);
    expect(res.text).toContain('import api');
  });

  it('مختصات نامعتبر کاشی نقشه رد می‌شود', async () => {
    const res = await request(app).get('/tiles/foo/1/1.png');
    expect(res.status).toBe(400);
  });

  it('اسکریپت ناوبری ناظر گزینه پشتیبانی ندارد', async () => {
    const appJs = await request(app).get('/js/app.js');
    expect(appJs.status).toBe(200);
    expect(appJs.text).not.toMatch(/labelKey:\s*'navSupport'/);
    expect(appJs.text).not.toMatch(/پشتیبانی/);
    expect(appJs.text).toContain('forPrimary: true');
  });

  it('اسکریپت پنل ادمین را سرو می‌کند', async () => {
    const res = await request(app).get('/js/views/admin.js');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/javascript|ecmascript|text/);
    expect(res.text).toContain('mountAdmin');
    expect(res.text).toContain('نمای کلی');
  });
});
