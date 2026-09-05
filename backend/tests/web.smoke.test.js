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
  });

  it('اسکریپت پنل ادمین را سرو می‌کند', async () => {
    const res = await request(app).get('/js/views/admin.js');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/javascript|ecmascript|text/);
    expect(res.text).toContain('mountAdmin');
    expect(res.text).toContain('نمای کلی');
  });
});
