import { beforeAll, afterAll, expect, it } from 'vitest';
import request from 'supertest';
import { evaluationCsv } from '../src/utils/evaluationCsv.js';

process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'pglite';
process.env.PGLITE_DATA_DIR = 'memory';
const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { createAdmin } = await import('../src/db/createAdmin.js');
const { susMetrics } = await import('../src/repositories/logRepository.js');
let app;
beforeAll(async () => { await db.connect(); await runMigrations(); app = createApp(); });
afterAll(async () => { await db.close(); });

it('exports only allowlisted research fields to admins and counts the latest SUS per user', async () => {
  const primary = await request(app).post('/api/v1/auth/register').send({
    phone: '09151119581', password: 'Test@1234', fullName: 'PrivateNameMarker', role: 'primary',
  });
  const id = primary.body.user.id;
  await createAdmin({ phone: '09151119589', password: 'Admin@12345', fullName: 'Admin' });
  const login = await request(app).post('/api/v1/auth/login').send({ phone: '09151119589', password: 'Admin@12345' });
  const adminAuth = { Authorization: `Bearer ${login.body.accessToken}` };
  const userAuth = { Authorization: `Bearer ${primary.body.accessToken}` };
  await db.query(`INSERT INTO location_reference_samples (user_id, error_m, accuracy_m, valid, environment, reference_label)
    VALUES ($1, 25, 60, false, 'urban', '=SUM(1,2)')`, [id]);
  await db.query(`INSERT INTO sus_responses (user_id, role, answers, score, created_at) VALUES
    ($1, 'primary', $2::jsonb, 10, now() - interval '1 day'), ($1, 'primary', $3::jsonb, 90, now())`,
    [id, JSON.stringify(Array(10).fill(1)), JSON.stringify(Array(10).fill(5))]);
  const alert = await db.query(`INSERT INTO alerts (user_id, type, title, body, lat, lng)
    VALUES ($1, 'sos', 'PrivateNameMarker', 'private', 37.123456, 51.123456) RETURNING id`, [id]);
  await db.query(`INSERT INTO alert_deliveries (alert_id, recipient_user_id, channel, status, latency_ms)
    VALUES ($1, $2, 'fcm', 'sent', 123)`, [alert.rows[0].id, id]);
  await db.query(`INSERT INTO fcm_device_receipts (alert_id, recipient_user_id) VALUES ($1, $2)`, [alert.rows[0].id, id]);
  await db.query(`INSERT INTO fall_events (user_id, detected_at, classified_as_fall, detection_source, lat, lng)
    VALUES ($1, now(), true, 'device', 37.123456, 51.123456)`, [id]);
  await db.query(`INSERT INTO location_telemetry (user_id, recorded_at, e2e_latency_ms, source, is_queued_replay)
    VALUES ($1, now(), 123, 'device', true), ($1, now(), 999, 'simulator', false)`, [id]);

  const base = '/api/v1/evaluation/export/';
  expect((await request(app).get(base + 'sus_responses')).status).toBe(401);
  expect((await request(app).get(base + 'sus_responses').set(userAuth)).status).toBe(403);
  expect((await request(app).get(base + 'users').set(adminAuth)).status).toBe(400);
  for (const dataset of ['location_reference_samples', 'sus_responses', 'alert_deliveries', 'fall_events', 'location_telemetry']) {
    const res = await request(app).get(base + dataset).set(adminAuth);
    expect(res.status, dataset).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.text).not.toContain('PrivateNameMarker');
    expect(res.text).not.toContain('37.123456');
    expect(res.text).not.toContain('51.123456');
    if (dataset === 'location_reference_samples') expect(res.text).toContain("\"'=SUM(1,2)\"");
    if (dataset === 'sus_responses') {
      expect(res.text.trim().split('\n')).toHaveLength(2);
      expect(res.text).toContain(',90,');
    }
    if (dataset === 'location_telemetry') {
      expect(res.text).not.toContain('simulator');
      expect(res.text).toContain('true');
    }
    if (dataset === 'alert_deliveries') {
      expect(res.text).toContain('device_receipt_recorded_at');
      expect(res.text).toContain('alert_to_server_receipt_ms');
      expect(res.text).not.toContain(',receipt_to_server_ms');
      const [header, row] = res.text.trim().split(/\r?\n/).map((line) => line.split(','));
      const elapsed = row[header.indexOf('alert_to_server_receipt_ms')];
      expect(elapsed).toMatch(/^\d+$/);
    }
  }
  expect((await susMetrics()).total).toBe(1);
  expect((await susMetrics()).avgScore).toBe(90);
});

it('quotes CSV and prevents formula execution in string cells', () => {
  expect(evaluationCsv(['text', 'number'], [{ text: '=1+1', number: -5 }])).toBe("text,number\r\n'=1+1,-5\r\n");
  expect(evaluationCsv(['text'], [{ text: 'a,"b"' }])).toContain('"a,""b"""');
});
