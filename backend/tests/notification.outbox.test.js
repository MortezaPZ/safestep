/**
 * صف FCM HTTP v1: enqueue به‌ازای گیرنده، ارسال، ابطال توکن، backoff.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.NOTIFICATION_DRIVER = 'auto';
process.env.RATE_LIMIT_SOS_MAX = '100';

vi.mock('google-auth-library', () => ({
  GoogleAuth: class GoogleAuth {
    async getClient() {
      return { getAccessToken: async () => ({ token: 'ya29.test-token' }) };
    }
  },
}));

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { createAdmin } = await import('../src/db/createAdmin.js');
const env = (await import('../src/config/env.js')).default;
const notificationAdapter = await import('../src/services/notificationAdapter.js');
const notificationOutbox = await import('../src/services/notificationOutbox.js');
const { invalidateAccountState } = await import('../src/middleware/auth.js');

const PASSWORD = 'Test@1234';
const FAKE_SA = JSON.stringify({
  client_email: 'fcm@safestep-test.iam.gserviceaccount.com',
  private_key: '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
  project_id: 'safestep-test',
});

let app;
const auth = (token) => ({ Authorization: `Bearer ${token}` });

async function signUp(phone, fullName, role) {
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({ phone, password: PASSWORD, fullName, role });
  expect(res.status).toBe(201);
  const id = res.body.user.id;
  await db.query("UPDATE users SET verification_status = 'verified' WHERE id = $1", [id]);
  invalidateAccountState(id);
  return { token: res.body.accessToken, id };
}

function enableFcm() {
  env.notification.driver = 'fcm';
  env.notification.fcmServiceAccountJson = FAKE_SA;
  env.notification.fcmProjectId = 'safestep-test';
}

function disableFcm() {
  env.notification.driver = 'local';
  env.notification.fcmServiceAccountJson = '';
  env.notification.fcmServiceAccountPath = '';
  env.notification.fcmProjectId = '';
}

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  disableFcm();
  await db.close();
});

beforeEach(() => {
  disableFcm();
  vi.unstubAllGlobals();
});

describe('سلامت و درایور محلی', () => {
  it('بدون حساب سرویس fcmConfigured برابر false است', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.notifications.fcmConfigured).toBe(false);
  });

  it('درایور local هیچ ردیفی در صف نمی‌سازد', async () => {
    env.notification.driver = 'local';
    const primary = await signUp('09141110001', 'محلی اصلی', 'primary');
    const guardian = await signUp('09141110002', 'محلی مراقب', 'guardian');
    const invite = await request(app)
      .post('/api/v1/guardianships/invites')
      .set(auth(primary.token))
      .send({ permissions: ['view_location', 'receive_alerts', 'emergency'] });
    await request(app)
      .post('/api/v1/guardianships/redeem')
      .set(auth(guardian.token))
      .send({ code: invite.body.code });

    const sos = await request(app).post('/api/v1/sos').set(auth(primary.token)).send({
      lat: 35.72,
      lng: 51.33,
    });
    expect(sos.status).toBe(201);
    const { rows } = await db.query('SELECT count(*)::int AS n FROM notification_outbox');
    expect(rows[0].n).toBe(0);
  });
});

describe('صف FCM', () => {
  let primary;
  let guardian;
  let admin;

  beforeAll(async () => {
    const created = await createAdmin({
      phone: '09141119999',
      fullName: 'مدیر نوتیف',
      password: 'Admin@12345',
    });
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ phone: '09141119999', password: 'Admin@12345' });
    admin = { token: login.body.accessToken, id: created.user?.id ?? login.body.user.id };

    primary = await signUp('09141110010', 'اصلی FCM', 'primary');
    guardian = await signUp('09141110011', 'مراقب FCM', 'guardian');
    const invite = await request(app)
      .post('/api/v1/guardianships/invites')
      .set(auth(primary.token))
      .send({ permissions: ['view_location', 'receive_alerts', 'emergency'] });
    await request(app)
      .post('/api/v1/guardianships/redeem')
      .set(auth(guardian.token))
      .send({ code: invite.body.code });
  });

  it('SOS برای گیرنده با مجوز اضطراری یک ردیف صف می‌سازد', async () => {
    enableFcm();
    const sos = await request(app).post('/api/v1/sos').set(auth(primary.token)).send({
      lat: 35.72,
      lng: 51.33,
    });
    expect(sos.status).toBe(201);
    const after = await db.query(
      `SELECT * FROM notification_outbox WHERE user_id = $1 ORDER BY id DESC LIMIT 5`,
      [guardian.id],
    );
    expect(after.rows.length).toBeGreaterThan(0);
    expect(after.rows[0].status).toBe('pending');
    expect(after.rows[0].channel).toBe('fcm');
  });

  it('processOnce پیام را می‌فرستد و ردیف را sent می‌کند', async () => {
    enableFcm();
    const registered = await request(app)
      .post('/api/v1/devices')
      .set(auth(guardian.token))
      .send({ platform: 'android', installId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', pushToken: 'live-token' });
    expect(registered.status).toBe(201);

    const sos = await request(app).post('/api/v1/sos').set(auth(primary.token)).send({
      lat: 35.72,
      lng: 51.33,
    });
    expect(sos.status).toBe(201);

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        json: async () => ({ name: 'projects/safestep-test/messages/1' }),
      })),
    );

    const result = await notificationOutbox.processOnce();
    expect(result.sent).toBeGreaterThan(0);
    const { rows } = await db.query(
      `SELECT status FROM notification_outbox WHERE alert_id = $1`,
      [sos.body.alert.id],
    );
    expect(rows.every((r) => r.status === 'sent')).toBe(true);
    expect(globalThis.fetch).toHaveBeenCalled();
    const body = JSON.parse(vi.mocked(globalThis.fetch).mock.calls[0][1].body);
    expect(body.message.token).toBe('live-token');
    expect(body.message.android.notification.channel_id).toBe('safestep_sos');
  });

  it('پاسخ ۴۰۴ UNREGISTERED توکن را پاک می‌کند', async () => {
    enableFcm();
    await request(app)
      .post('/api/v1/devices')
      .set(auth(guardian.token))
      .send({ platform: 'android', installId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', pushToken: 'dead-token' });

    const sos = await request(app).post('/api/v1/sos').set(auth(primary.token)).send({
      lat: 35.72,
      lng: 51.34,
    });
    expect(sos.status).toBe(201);

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 404,
        json: async () => ({ error: { status: 'NOT_FOUND', message: 'Requested entity was not found.', details: [{ errorCode: 'UNREGISTERED' }] } }),
      })),
    );

    await notificationOutbox.processOnce();
    const { rows } = await db.query(
      `SELECT push_token FROM devices WHERE user_id = $1 AND install_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'`,
      [guardian.id],
    );
    expect(rows[0].push_token).toBeNull();
  });

  it('شکست ارسال backoff می‌دهد و پس از ۵ تلاش abandoned می‌شود', async () => {
    enableFcm();
    await request(app)
      .post('/api/v1/devices')
      .set(auth(guardian.token))
      .send({ platform: 'android', installId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', pushToken: 'fail-token' });

    const sos = await request(app).post('/api/v1/sos').set(auth(primary.token)).send({
      lat: 35.71,
      lng: 51.33,
    });
    expect(sos.status).toBe(201);
    expect(sos.body.alert?.id).toBeTruthy();
    const alertId = sos.body.alert.id;

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 500,
        json: async () => ({ error: { message: 'unavailable' } }),
      })),
    );

    for (let i = 0; i < 5; i += 1) {
      await db.query(
        `UPDATE notification_outbox SET next_attempt_at = now() WHERE alert_id = $1`,
        [alertId],
      );
      await notificationOutbox.processOnce();
    }

    const { rows } = await db.query(
      `SELECT status, attempts FROM notification_outbox WHERE alert_id = $1`,
      [alertId],
    );
    expect(rows[0].status).toBe('abandoned');
    expect(Number(rows[0].attempts)).toBeGreaterThanOrEqual(5);
  });

  it('توکن یکسان از دستگاه قبلی برداشته می‌شود', async () => {
    const other = await signUp('09141110012', 'دستگاه دوم', 'guardian');
    await request(app)
      .post('/api/v1/devices')
      .set(auth(guardian.token))
      .send({ platform: 'android', installId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', pushToken: 'shared-token' });
    await request(app)
      .post('/api/v1/devices')
      .set(auth(other.token))
      .send({ platform: 'android', installId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', pushToken: 'shared-token' });

    const first = await db.query(
      `SELECT push_token FROM devices WHERE install_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'`,
    );
    const second = await db.query(
      `SELECT push_token FROM devices WHERE install_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5'`,
    );
    expect(first.rows[0].push_token).toBeNull();
    expect(second.rows[0].push_token).toBe('shared-token');
  });

  it('ادمین فهرست صف را می‌بیند', async () => {
    enableFcm();
    const res = await request(app)
      .get('/api/v1/admin/notifications/outbox')
      .set(auth(admin.token));
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.items)).toBe(true);
    expect(typeof res.body.total).toBe('number');
  });

  it('ادمین ردیف abandoned را دوباره در صف می‌گذارد', async () => {
    const { rows } = await db.query(
      `SELECT id FROM notification_outbox WHERE status = 'abandoned' LIMIT 1`,
    );
    expect(rows.length).toBe(1);
    const res = await request(app)
      .post(`/api/v1/admin/notifications/outbox/${rows[0].id}/retry`)
      .set(auth(admin.token));
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('pending');
  });

  it('کاربر عادی به صف دسترسی ندارد', async () => {
    const res = await request(app)
      .get('/api/v1/admin/notifications/outbox')
      .set(auth(primary.token));
    expect(res.status).toBe(403);
  });

  it('isFcmConfigured پس از JSON حساب سرویس true است', () => {
    enableFcm();
    expect(notificationAdapter.isFcmConfigured()).toBe(true);
    expect(notificationAdapter.activeDriver()).toBe('fcm');
  });

  it('ارسال مستقیم به توکن از HTTP v1 استفاده می‌کند', async () => {
    enableFcm();
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url) => {
        expect(String(url)).toContain('/v1/projects/safestep-test/messages:send');
        return {
          ok: true,
          status: 200,
          json: async () => ({ name: 'ok' }),
        };
      }),
    );
    const result = await notificationAdapter.sendFcmToToken('tok', {
      title: 't',
      body: 'b',
      data: { alertId: '1' },
      severity: 'warning',
    });
    expect(result.ok).toBe(true);
  });
});
