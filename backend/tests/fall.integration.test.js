import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.DEMO_MODE = 'true';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { generateDataset } = await import('../scripts/falls/generate_synthetic.js');
const { cannedPositiveFeatures } = await import('../src/services/fallDetection/classifier.js');
const fallWatchdog = await import('../src/services/fallWatchdog.js');
const { invalidateAccountState } = await import('../src/middleware/auth.js');

const PASSWORD = 'Test@1234';
let app;

async function signUp(phone, fullName, role) {
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({ phone, password: PASSWORD, fullName, role });
  expect(res.status).toBe(201);
  const id = res.body.user.id;
  await db.query("UPDATE users SET verification_status = 'verified' WHERE id = $1", [id]);
  invalidateAccountState(id);
  return { token: res.body.accessToken, id, user: res.body.user };
}

const auth = (token) => ({ Authorization: `Bearer ${token}` });

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  await db.close();
});

describe('API تشخیص سقوط', () => {
  let primary;
  let guardianEm;
  let guardianNo;
  let adminToken;
  let fallId;
  let negativeId;

  it('کاربران را می‌سازد', async () => {
    primary = await signUp('09130000001', 'کاربر سقوط', 'primary');
    guardianEm = await signUp('09130000002', 'مراقب اضطراری', 'guardian');
    guardianNo = await signUp('09130000003', 'مراقب عادی', 'guardian');
    expect(primary.user.role).toBe('primary');
  });

  it('دعوت با دسترسی اضطراری را مصرف می‌کند', async () => {
    const inv = await request(app)
      .post('/api/v1/guardianships/invites')
      .set(auth(primary.token))
      .send({ permissions: ['view_location', 'receive_alerts', 'emergency'] });
    expect(inv.status).toBe(201);
    const redeem = await request(app)
      .post('/api/v1/guardianships/redeem')
      .set(auth(guardianEm.token))
      .send({ code: inv.body.code });
    expect(redeem.status).toBe(201);
  });

  it('دعوت بدون اضطراری را مصرف می‌کند', async () => {
    const inv = await request(app)
      .post('/api/v1/guardianships/invites')
      .set(auth(primary.token))
      .send({ permissions: ['view_location', 'receive_alerts'] });
    const redeem = await request(app)
      .post('/api/v1/guardianships/redeem')
      .set(auth(guardianNo.token))
      .send({ code: inv.body.code });
    expect(redeem.status).toBe(201);
  });

  it('تشخیص مثبت شمارش معکوس برمی‌گرداند و هشدار نمی‌سازد', async () => {
    const res = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({
        features: cannedPositiveFeatures(),
        detectedAt: new Date().toISOString(),
        lat: 35.7,
        lng: 51.4,
        clientEventId: randomUUID(),
      });
    expect(res.status).toBe(201);
    expect(res.body.isFall).toBe(true);
    expect(res.body.fallEventId).toBeTruthy();
    expect(res.body.countdownSec).toBeGreaterThanOrEqual(10);
    fallId = res.body.fallEventId;
    const alerts = await request(app).get('/api/v1/alerts').set(auth(primary.token));
    expect(alerts.body.alerts.filter((a) => a.type === 'fall_detected')).toHaveLength(0);
  });

  it('تکرار clientEventId بی‌اثر است', async () => {
    const id = randomUUID();
    const body = {
      features: cannedPositiveFeatures(),
      clientEventId: id,
    };
    const a = await request(app).post('/api/v1/falls/detect').set(auth(primary.token)).send(body);
    const b = await request(app).post('/api/v1/falls/detect').set(auth(primary.token)).send(body);
    expect(a.status).toBe(201);
    expect(b.body.duplicate).toBe(true);
    expect(b.body.fallEventId).toBe(a.body.fallEventId);
  });

  it('نمونهٔ منفی هم ردیف می‌سازد', async () => {
    const adl = generateDataset({ perClass: 4, seed: 3 }).find((r) => r.label === 0);
    const res = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: adl.features, clientEventId: randomUUID() });
    expect(res.status).toBe(201);
    expect(res.body.isFall).toBe(false);
    negativeId = res.body.fallEventId;
  });

  it('مراقب نمی‌تواند detect بزند', async () => {
    const res = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(guardianEm.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    expect(res.status).toBe(403);
  });

  it('بازخورد false_alarm هشدار نمی‌سازد', async () => {
    const created = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    const fb = await request(app)
      .post(`/api/v1/falls/${created.body.fallEventId}/feedback`)
      .set(auth(primary.token))
      .send({ feedback: 'false_alarm', respondedWithinSec: 4 });
    expect(fb.status).toBe(200);
    const alerts = await request(app).get('/api/v1/alerts').set(auth(guardianEm.token));
    const related = (alerts.body.alerts ?? []).filter((a) => a.metadata?.fallEventId === created.body.fallEventId);
    expect(related).toHaveLength(0);
  });

  it('بازخورد confirmed هشدار fall_detected می‌سازد', async () => {
    const created = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    const fb = await request(app)
      .post(`/api/v1/falls/${created.body.fallEventId}/feedback`)
      .set(auth(primary.token))
      .send({ feedback: 'confirmed', respondedWithinSec: 8 });
    expect(fb.status).toBe(200);
    const alerts = await request(app).get('/api/v1/alerts').set(auth(guardianEm.token));
    const hit = (alerts.body.alerts ?? []).find((a) => a.type === 'fall_detected' && a.metadata?.fallEventId === created.body.fallEventId);
    expect(hit).toBeTruthy();
    expect(hit.title).toContain('سقوط');
  });

  it('بازخورد تکراری بی‌اثر است', async () => {
    const created = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    await request(app)
      .post(`/api/v1/falls/${created.body.fallEventId}/feedback`)
      .set(auth(primary.token))
      .send({ feedback: 'false_alarm' });
    const again = await request(app)
      .post(`/api/v1/falls/${created.body.fallEventId}/feedback`)
      .set(auth(primary.token))
      .send({ feedback: 'confirmed' });
    expect(again.body.duplicate).toBe(true);
  });

  it('no_response هشدار می‌سازد', async () => {
    const created = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    const fb = await request(app)
      .post(`/api/v1/falls/${created.body.fallEventId}/feedback`)
      .set(auth(primary.token))
      .send({ feedback: 'no_response' });
    expect(fb.status).toBe(200);
  });

  it('گزارش ازدست‌رفته FN می‌سازد', async () => {
    const res = await request(app)
      .post('/api/v1/falls/report-missed')
      .set(auth(primary.token))
      .send({ lat: 35.7, lng: 51.4 });
    expect(res.status).toBe(201);
    expect(res.body.fallEvent.detectionSource).toBe('manual');
  });

  it('مراقب اضطراری فهرست را می‌بیند', async () => {
    const res = await request(app)
      .get('/api/v1/falls')
      .query({ userId: primary.id })
      .set(auth(guardianEm.token));
    expect(res.status).toBe(200);
    expect(res.body.falls.length).toBeGreaterThan(0);
  });

  it('مراقب بدون اضطراری فهرست را نمی‌بیند', async () => {
    const res = await request(app)
      .get('/api/v1/falls')
      .query({ userId: primary.id })
      .set(auth(guardianNo.token));
    expect(res.status).toBe(403);
  });

  it('ادمین فهرست سقوط دیگران را نمی‌بیند', async () => {
    await db.query("UPDATE users SET role = 'admin' WHERE id = $1", [guardianNo.id]);
    invalidateAccountState(guardianNo.id);
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ phone: '09130000003', password: PASSWORD });
    adminToken = login.body.accessToken;
    const res = await request(app)
      .get('/api/v1/falls')
      .query({ userId: primary.id })
      .set(auth(adminToken));
    expect(res.status).toBe(403);
  });

  it('watchdog پس از مهلت no_response می‌زند', async () => {
    const created = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: cannedPositiveFeatures(), clientEventId: randomUUID() });
    await db.query(
      `UPDATE fall_events SET detected_at = now() - interval '10 minutes' WHERE id = $1`,
      [created.body.fallEventId],
    );
    const out = await fallWatchdog.processOnce();
    expect(out.raised).toBeGreaterThanOrEqual(1);
  });

  it('سنجه‌ها ماتریس درهم‌ریختگی دارند', async () => {
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ phone: '09130000003', password: PASSWORD });
    const res = await request(app).get('/api/v1/admin/metrics').set(auth(login.body.accessToken));
    expect(res.status).toBe(200);
    expect(res.body.fallDetection.confusion).toHaveProperty('tp');
    expect(res.body.fallDetection.confusion).toHaveProperty('fn');
    expect(res.body.fallDetection.total).toBeGreaterThan(0);
  });

  it('پیکربندی کلاینت تشخیص سقوط را روشن نشان می‌دهد', async () => {
    const res = await request(app).get('/api/v1/config/client').set(auth(primary.token));
    expect(res.body.features.fallDetection).toBe(true);
  });

  it('تنظیم شمارش معکوس ذخیره می‌شود', async () => {
    const res = await request(app)
      .patch('/api/v1/settings')
      .set(auth(primary.token))
      .send({ fallCountdownSec: 45, fallDetectionEnabled: true });
    expect(res.status).toBe(200);
    expect(res.body.settings.fallCountdownSec).toBe(45);
  });

  it('شبیه‌ساز سقوط در حالت نمایش کار می‌کند', async () => {
    const res = await request(app).post('/api/v1/simulator/fall').set(auth(primary.token)).send({});
    expect(res.status).toBe(201);
    expect(res.body.isFall).toBe(true);
  });

  it('بردار ناقص رد می‌شود', async () => {
    const res = await request(app)
      .post('/api/v1/falls/detect')
      .set(auth(primary.token))
      .send({ features: [1, 2, 3], clientEventId: randomUUID() });
    expect(res.status).toBe(400);
  });

  it('متن هشدار سقوط فارسی است', async () => {
    const { composeAlertMessage } = await import('../src/services/alertService.js');
    const msg = composeAlertMessage('fall_detected', { userName: 'مریم', confidence: 0.81 });
    expect(msg.title).toBe('احتمال سقوط');
    expect(msg.body).toContain('81');
  });
});
