import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { checkGpsLostAlerts } = await import('../src/services/locationService.js');
let app;

beforeAll(async () => { await db.connect(); await runMigrations(); app = createApp(); });
afterAll(async () => { await db.close(); });

describe('manual tracking intent', () => {
  it('suppresses GPS-lost on stop, then resumes with a fresh grace period', async () => {
    const registration = await request(app).post('/api/v1/auth/register').send({
      phone: '09151119991', password: 'Test@1234', fullName: 'آزمون ردیابی', role: 'primary',
    });
    expect(registration.status).toBe(201);
    const { id } = registration.body.user;
    const auth = { Authorization: `Bearer ${registration.body.accessToken}` };
    expect((await request(app).put('/api/v1/locations/tracking').send({ active: false })).status).toBe(401);
    expect((await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: 'false' })).status).toBe(400);
    const guardian = await request(app).post('/api/v1/auth/register').send({
      phone: '09151119992', password: 'Test@1234', fullName: 'مراقب', role: 'guardian',
    });
    expect(guardian.status).toBe(201);
    expect((await request(app).put('/api/v1/locations/tracking')
      .set('Authorization', `Bearer ${guardian.body.accessToken}`).send({ active: false })).status).toBe(403);
    await db.query(
      `INSERT INTO location_pings (user_id, lat, lng, source, recorded_at)
       VALUES ($1, 35, 51, 'device', now() - interval '10 minutes')`, [id],
    );
    const stop = await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: false });
    expect(stop.status).toBe(200);
    expect(stop.body.trackingActive).toBe(false);
    expect(await checkGpsLostAlerts()).toBe(0);
    const settings = await db.query('SELECT location_sharing_enabled FROM user_settings WHERE user_id = $1', [id]);
    expect(settings.rows[0].location_sharing_enabled).toBe(true);

    const start = await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: true });
    expect(start.body.trackingActive).toBe(true);
    expect(await checkGpsLostAlerts()).toBe(0);
    const firstStart = await db.query('SELECT tracking_started_at FROM user_settings WHERE user_id = $1', [id]);
    await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: true });
    const secondStart = await db.query('SELECT tracking_started_at FROM user_settings WHERE user_id = $1', [id]);
    expect(new Date(secondStart.rows[0].tracking_started_at).getTime())
      .toBe(new Date(firstStart.rows[0].tracking_started_at).getTime());
    expect(await checkGpsLostAlerts(Date.now() + 361_000)).toBe(1);
  });

  it('uses three times the configured moving or stationary interval', async () => {
    for (const [phone, adaptive, interval, stationary, threshold] of [
      ['09151119993', false, 900, 120, 2700],
      ['09151119994', true, 900, 1800, 5400],
    ]) {
      const registration = await request(app).post('/api/v1/auth/register').send({
        phone, password: 'Test@1234', fullName: 'آزمون بازه', role: 'primary',
      });
      const id = registration.body.user.id;
      await db.query(`UPDATE user_settings SET adaptive_ping_enabled = $2, ping_interval_sec = $3,
                      ping_interval_stationary_sec = $4 WHERE user_id = $1`,
        [id, adaptive, interval, stationary]);
      await db.query(`INSERT INTO location_pings (user_id, lat, lng, source, recorded_at)
                      VALUES ($1, 35, 51, 'device', now())`, [id]);
      const now = Date.now();
      await checkGpsLostAlerts(now + (threshold - 10) * 1000);
      let alerts = await db.query("SELECT count(*)::int AS n FROM alerts WHERE user_id = $1 AND type = 'gps_lost'", [id]);
      expect(alerts.rows[0].n).toBe(0);
      await checkGpsLostAlerts(now + (threshold + 10) * 1000);
      alerts = await db.query("SELECT count(*)::int AS n FROM alerts WHERE user_id = $1 AND type = 'gps_lost'", [id]);
      expect(alerts.rows[0].n).toBe(1);
    }
  });

  it('detects a missing first ping after tracking is explicitly started', async () => {
    const registration = await request(app).post('/api/v1/auth/register').send({
      phone: '09151119995', password: 'Test@1234', fullName: 'آزمون بدون پینگ', role: 'primary',
    });
    expect(registration.status).toBe(201);
    const id = registration.body.user.id;
    const auth = { Authorization: `Bearer ${registration.body.accessToken}` };
    const start = await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: true });
    expect(start.status).toBe(200);
    const first = await db.query('SELECT tracking_started_at FROM user_settings WHERE user_id = $1', [id]);
    expect(first.rows[0].tracking_started_at).not.toBeNull();
    await request(app).put('/api/v1/locations/tracking').set(auth).send({ active: true });
    const second = await db.query('SELECT tracking_started_at FROM user_settings WHERE user_id = $1', [id]);
    expect(new Date(second.rows[0].tracking_started_at).getTime())
      .toBe(new Date(first.rows[0].tracking_started_at).getTime());
    await checkGpsLostAlerts(Date.now() + 361_000);
    const alerts = await db.query("SELECT count(*)::int AS n FROM alerts WHERE user_id = $1 AND type = 'gps_lost'", [id]);
    expect(alerts.rows[0].n).toBe(1);
  });
});
