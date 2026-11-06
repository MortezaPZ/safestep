import { beforeAll, afterAll, expect, it } from 'vitest';
import request from 'supertest';

process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'pglite';
process.env.PGLITE_DATA_DIR = 'memory';
const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { locationMetrics } = await import('../src/repositories/logRepository.js');
let app;
beforeAll(async () => { await db.connect(); await runMigrations(); app = createApp(); });
afterAll(async () => { await db.close(); });

it('snapshots reference label and environment and includes high-accuracy-number samples in p95', async () => {
  const user = await request(app).post('/api/v1/auth/register').send({
    phone: '09151119681', password: 'Test@1234', fullName: 'آزمون', role: 'primary',
  });
  const auth = { Authorization: `Bearer ${user.body.accessToken}` };
  const reference = (label) => request(app).post('/api/v1/evaluation/reference').set(auth)
    .send({ lat: 35, lng: 51, label });
  expect((await reference('پارک')).status).toBe(201);
  const missing = await request(app).post('/api/v1/evaluation/reference/sample').set(auth)
    .send({ lat: 35, lng: 51, accuracyM: 10 });
  expect(missing.status).toBe(400);
  const first = await request(app).post('/api/v1/evaluation/reference/sample').set(auth)
    .send({ lat: 35, lng: 51, accuracyM: 10, environment: 'open' });
  expect(first.status).toBe(201);
  expect(first.body).toMatchObject({ valid: true, environment: 'open', referenceLabel: 'پارک' });
  expect((await reference('خیابان')).status).toBe(201);
  const second = await request(app).post('/api/v1/evaluation/reference/sample').set(auth)
    .send({ lat: 35.001, lng: 51, accuracyM: 60, environment: 'urban' });
  expect(second.status).toBe(201);
  expect(second.body).toMatchObject({ valid: false, environment: 'urban', referenceLabel: 'خیابان' });
  const rows = await db.query('SELECT reference_label FROM location_reference_samples ORDER BY sampled_at');
  expect(rows.rows.map((row) => row.reference_label)).toEqual(['پارک', 'خیابان']);
  const summary = (await locationMetrics()).positionError;
  expect(summary.samples).toBe(2);
  expect(summary.accuracyOver30Count).toBe(1);
  expect(summary.p95M).toBeCloseTo(first.body.errorM + 0.95 * (second.body.errorM - first.body.errorM), 2);
});
