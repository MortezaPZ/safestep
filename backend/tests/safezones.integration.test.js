import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { destinationPoint } from '../src/utils/geo.js';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.GEOFENCE_DEBOUNCE_COUNT = '2';
process.env.GEOFENCE_COOLDOWN_SEC = '0';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');

const PASSWORD = 'Test@1234';
const HOME = { lat: 35.7219, lng: 51.3347 };
let app;
const auth = (t) => ({ Authorization: `Bearer ${t}` });

async function signUp(phone, name, role) {
  const res = await request(app).post('/api/v1/auth/register').send({
    phone, password: PASSWORD, fullName: name, role,
  });
  expect(res.status).toBe(201);
  return { token: res.body.accessToken, id: res.body.user.id };
}

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  await db.close();
});

describe('محدوده‌ی چندضلعی و زمان‌بندی', () => {
  let user;
  let zoneId;

  it('کاربر ثبت‌نام می‌کند', async () => {
    user = await signUp('09151110001', 'چندضلعی', 'primary');
  });

  it('ساخت چندضلعی از API', async () => {
    const poly = [
      [HOME.lat + 0.002, HOME.lng - 0.002],
      [HOME.lat + 0.002, HOME.lng + 0.002],
      [HOME.lat - 0.002, HOME.lng + 0.002],
      [HOME.lat - 0.002, HOME.lng - 0.002],
    ];
    const res = await request(app)
      .post('/api/v1/safe-zones')
      .set(auth(user.token))
      .send({ name: 'محله', shape: 'polygon', polygon: poly, dwellAlertMinutes: 1 });
    expect(res.status).toBe(201);
    expect(res.body.shape).toBe('polygon');
    zoneId = res.body.id;
  });

  it('پیش‌نمایش مساحت برمی‌گرداند', async () => {
    const res = await request(app)
      .post('/api/v1/safe-zones/preview')
      .set(auth(user.token))
      .send({
        shape: 'polygon',
        polygon: [
          [HOME.lat + 0.001, HOME.lng - 0.001],
          [HOME.lat + 0.001, HOME.lng + 0.001],
          [HOME.lat - 0.001, HOME.lng + 0.001],
          [HOME.lat - 0.001, HOME.lng - 0.001],
        ],
      });
    expect(res.status).toBe(200);
    expect(res.body.areaM2).toBeGreaterThan(0);
  });

  it('پینگ داخل سپس دو پینگ بیرون → خروج', async () => {
    await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send({
      lat: HOME.lat, lng: HOME.lng,
    });
    const far = destinationPoint(HOME.lat, HOME.lng, 2000, 90);
    await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send({
      lat: far.lat, lng: far.lng,
    });
    const res = await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send({
      lat: far.lat, lng: far.lng,
    });
    expect(res.status).toBe(201);
    expect(res.body.alerts.some((a) => a.type === 'zone_exit')).toBe(true);
  });

  it('محدوده‌ی زمان‌بندی‌شده بیرون پنجره هشدار نمی‌دهد', async () => {
    const poly = [
      [35.8, 51.4], [35.8, 51.41], [35.79, 51.41], [35.79, 51.4],
    ];
    const created = await request(app)
      .post('/api/v1/safe-zones')
      .set(auth(user.token))
      .send({
        name: 'فقط جمعه',
        shape: 'polygon',
        polygon: poly,
        schedule: { timezone: 'UTC', windows: [{ days: [5], from: '00:00', to: '00:01' }] },
      });
    expect(created.status).toBe(201);
    const inside = { lat: 35.795, lng: 51.405 };
    const outside = { lat: 35.70, lng: 51.50 };
    await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send(inside);
    await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send(outside);
    const res = await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send(outside);
    const forThis = (res.body.alerts ?? []).filter((a) => a.zoneId === created.body.id);
    expect(forThis).toHaveLength(0);
  });

  it('هشدار ماندگاری پس از عقب‌بردن last_transition_at', async () => {
    await db.query(
      `UPDATE zone_states SET last_transition_at = now() - interval '2 minutes',
              last_dwell_alert_at = NULL, state = 'outside'
        WHERE zone_id = $1`,
      [zoneId],
    );
    const far = destinationPoint(HOME.lat, HOME.lng, 2500, 45);
    const res = await request(app).post('/api/v1/locations/ping').set(auth(user.token)).send({
      lat: far.lat, lng: far.lng,
    });
    expect(res.body.alerts.some((a) => a.metadata?.dwellMinutes === 1 || a.body?.includes('دقیقه'))).toBe(true);
  });

  it('پیکربندی کلاینت پینگ تطبیقی دارد', async () => {
    const res = await request(app).get('/api/v1/config/client').set(auth(user.token));
    expect(res.status).toBe(200);
    expect(res.body.adaptivePing.stationarySpeedMps).toBe(0.5);
  });
});
