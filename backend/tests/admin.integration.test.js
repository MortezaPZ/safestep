/**
 * تست یکپارچه‌ی نقش ادمین، پنل مدیریت و لایه‌ی سنجش.
 *
 * چهار چیز اینجا اثبات می‌شود — و هر چهار، ادعاهای امنیتیِ فاز اول‌اند:
 *
 *   ۱) کاربر عادی به هیچ مسیر ادمینی دسترسی ندارد
 *   ۲) هیچ‌کس نمی‌تواند خودش را با ثبت‌نام، ادمین کند
 *   ۳) تعلیق حساب **فوری** اثر می‌کند، نه پس از انقضای توکن
 *   ۴) ادمین هیچ مسیری برای دیدن موقعیت کاربران ندارد
 *
 * علاوه بر این، درستی سنجه‌ها و بی‌اثرسازی تکرارِ صف آفلاین آزموده می‌شود.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { createAdmin } = await import('../src/db/createAdmin.js');
const { default: telemetryService } = await import('../src/services/telemetryService.js');

const PASSWORD = 'Test@1234';
const HOME = { lat: 35.7219, lng: 51.3347 };

let app;

const auth = (token) => ({ Authorization: `Bearer ${token}` });

async function signUp(phone, fullName, role = 'primary') {
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({ phone, password: PASSWORD, fullName, role });
  expect(res.status).toBe(201);
  return { token: res.body.accessToken, id: res.body.user.id, user: res.body.user };
}

async function login(phone, password = PASSWORD) {
  return request(app).post('/api/v1/auth/login').send({ phone, password });
}

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
  // در تست‌ها به‌طور پیش‌فرض خاموش است؛ اینجا صریحاً روشنش می‌کنیم
  // چون هدف همین تست، آزمودن خودِ لایه‌ی سنجش است.
  telemetryService.setEnabled(true);
});

afterAll(async () => {
  telemetryService.setEnabled(false);
  await db.close();
});

/* ═══════════════════════════════════════════════════════════════════ */

describe('نقش ادمین و پنل مدیریت', () => {
  let admin;
  let sara; // کاربر اصلی
  let reza; // مراقب

  it('ادمین از راه API قابل ساخت نیست', async () => {
    const res = await request(app).post('/api/v1/auth/register').send({
      phone: '09131110001',
      password: PASSWORD,
      fullName: 'مهاجم',
      role: 'admin',
    });

    // نقش admin در فهرست مجاز ثبت‌نام نیست، پس اعتبارسنجی ردش می‌کند
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('اولین ادمین با اسکریپت سرور ساخته می‌شود', async () => {
    const result = await createAdmin({
      phone: '09131119999',
      fullName: 'مدیر سامانه',
      password: 'Admin@12345',
    });

    expect(result.created).toBe(true);
    expect(result.user.role).toBe('admin');

    const res = await login('09131119999', 'Admin@12345');
    expect(res.status).toBe(200);
    expect(res.body.user.role).toBe('admin');
    admin = { token: res.body.accessToken, id: res.body.user.id };
  });

  it('کاربران عادی ثبت‌نام می‌کنند', async () => {
    sara = await signUp('09131110010', 'سارا محمدی', 'primary');
    reza = await signUp('09131110011', 'رضا محمدی', 'guardian');
    expect(sara.user.role).toBe('primary');
  });

  it('کاربر عادی به هیچ مسیر ادمینی دسترسی ندارد', async () => {
    const paths = [
      '/api/v1/admin/overview',
      '/api/v1/admin/users',
      '/api/v1/admin/devices',
      '/api/v1/admin/metrics',
      '/api/v1/admin/logs/requests',
      '/api/v1/admin/logs/audit',
    ];

    for (const path of paths) {
      // eslint-disable-next-line no-await-in-loop
      const res = await request(app).get(path).set(auth(sara.token));
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
    }
  });

  it('درخواست بدون توکن هم رد می‌شود', async () => {
    const res = await request(app).get('/api/v1/admin/users');
    expect(res.status).toBe(401);
  });

  it('ادمین فهرست کاربران را با شمارنده‌ها می‌بیند', async () => {
    const res = await request(app).get('/api/v1/admin/users').set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.total).toBeGreaterThanOrEqual(3);

    const row = res.body.users.find((u) => u.id === sara.id);
    expect(row).toBeDefined();
    expect(row.status).toBe('active');
    expect(row).toHaveProperty('deviceCount');
    expect(row).toHaveProperty('guardianCount');
    // هش پسورد هرگز نباید به کلاینت برسد
    expect(row.passwordHash).toBeUndefined();
  });

  it('جست‌وجوی کاربر با نام کار می‌کند', async () => {
    const res = await request(app)
      .get('/api/v1/admin/users?search=سارا')
      .set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.users.every((u) => u.fullName.includes('سارا'))).toBe(true);
  });

  it('کاراکتر ویژه‌ی LIKE در جست‌وجو بی‌اثر می‌شود', async () => {
    // بدون escape، «‎%‎» کل جدول را برمی‌گرداند
    const res = await request(app).get('/api/v1/admin/users?search=%').set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
  });

  it('ادمین حساب کاربر را معلق می‌کند و تعلیق فوری اثر می‌کند', async () => {
    const suspend = await request(app)
      .post(`/api/v1/admin/users/${reza.id}/suspend`)
      .set(auth(admin.token))
      .send({ reason: 'گزارش تخلف' });

    expect(suspend.status).toBe(200);
    expect(suspend.body.user.status).toBe('suspended');

    // ── نکته‌ی اصلی: توکنِ قبلیِ رضا هنوز از نظر امضا معتبر است، اما باید
    // بی‌اثر شده باشد. اگر فقط به توکن تکیه می‌کردیم، تا ۱۵ دقیقه کار می‌کرد.
    const blocked = await request(app).get('/api/v1/auth/me').set(auth(reza.token));
    expect(blocked.status).toBe(403);
    expect(blocked.body.error.message).toContain('معلق');

    // ورود دوباره هم پیام روشن می‌دهد، نه «شماره یا رمز نادرست»
    const relogin = await login('09131110011');
    expect(relogin.status).toBe(403);
  });

  it('ادمین حساب را دوباره فعال می‌کند', async () => {
    const res = await request(app)
      .post(`/api/v1/admin/users/${reza.id}/activate`)
      .set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.user.status).toBe('active');

    const ok = await request(app).get('/api/v1/auth/me').set(auth(reza.token));
    expect(ok.status).toBe(200);
  });

  it('ادمین نمی‌تواند حساب خودش را معلق کند', async () => {
    const res = await request(app)
      .post(`/api/v1/admin/users/${admin.id}/suspend`)
      .set(auth(admin.token))
      .send({});

    expect(res.status).toBe(400);
  });

  it('نقش آخرین ادمین قابل برداشتن نیست', async () => {
    const res = await request(app)
      .patch(`/api/v1/admin/users/${admin.id}/role`)
      .set(auth(admin.token))
      .send({ role: 'primary' });

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('CONFLICT');
  });

  it('ادمین می‌تواند نقش کاربر دیگری را تغییر دهد و تغییر فوری اثر می‌کند', async () => {
    const promote = await request(app)
      .patch(`/api/v1/admin/users/${sara.id}/role`)
      .set(auth(admin.token))
      .send({ role: 'admin' });

    expect(promote.status).toBe(200);
    expect(promote.body.user.role).toBe('admin');

    // سارا با همان توکن قبلی، حالا باید به پنل دسترسی داشته باشد:
    // نقش از دیتابیس خوانده می‌شود، نه از ادعای داخل توکن
    const access = await request(app).get('/api/v1/admin/overview').set(auth(sara.token));
    expect(access.status).toBe(200);

    // برگرداندن به حالت اول تا بقیه‌ی تست‌ها دست‌نخورده بمانند
    const demote = await request(app)
      .patch(`/api/v1/admin/users/${sara.id}/role`)
      .set(auth(admin.token))
      .send({ role: 'primary' });
    expect(demote.status).toBe(200);

    const denied = await request(app).get('/api/v1/admin/overview').set(auth(sara.token));
    expect(denied.status).toBe(403);
  });

  it('ادمین هیچ مسیری برای دیدن موقعیت کاربران ندارد', async () => {
    // اگر روزی چنین مسیری اضافه شود، این تست می‌شکند — و باید بشکند.
    const res = await request(app)
      .get(`/api/v1/locations/current?userId=${sara.id}`)
      .set(auth(admin.token));

    expect(res.status).toBe(403);
  });

  it('نمای کلی، آمار سامانه را برمی‌گرداند', async () => {
    const res = await request(app).get('/api/v1/admin/overview').set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.stats.users.total).toBeGreaterThanOrEqual(3);
    expect(res.body.stats.users.byRole.admin).toBeGreaterThanOrEqual(1);
    expect(Array.isArray(res.body.recentAlerts)).toBe(true);
  });

  /* ─────────────────────────── دستگاه‌ها ─────────────────────────── */

  it('ثبت دوباره‌ی دستگاه با همان installId، ردیف تکراری نمی‌سازد', async () => {
    const installId = '11111111-2222-3333-4444-555555555555';

    const first = await request(app)
      .post('/api/v1/devices')
      .set(auth(sara.token))
      .send({
        platform: 'android',
        installId,
        pushToken: 'token-old',
        appVersion: '1.0.0',
        osVersion: 'Android 14',
        model: 'Pixel 8',
      });
    expect(first.status).toBe(201);

    // توکن FCM عوض شده، ولی همان نصب است
    const second = await request(app)
      .post('/api/v1/devices')
      .set(auth(sara.token))
      .send({ platform: 'android', installId, pushToken: 'token-new', appVersion: '1.1.0' });
    expect(second.status).toBe(201);
    expect(second.body.device.id).toBe(first.body.device.id);
    expect(second.body.device.appVersion).toBe('1.1.0');

    const list = await request(app).get('/api/v1/devices').set(auth(sara.token));
    expect(list.body.devices.filter((d) => d.installId === installId)).toHaveLength(1);
  });

  it('ادمین دستگاه را ابطال می‌کند و ابطال، دوباره‌کاری نمی‌پذیرد', async () => {
    const list = await request(app)
      .get(`/api/v1/admin/devices?userId=${sara.id}`)
      .set(auth(admin.token));

    expect(list.status).toBe(200);
    expect(list.body.devices.length).toBeGreaterThan(0);

    const deviceId = list.body.devices[0].id;

    const revoke = await request(app)
      .post(`/api/v1/admin/devices/${deviceId}/revoke`)
      .set(auth(admin.token));
    expect(revoke.status).toBe(200);
    expect(revoke.body.device.revokedAt).not.toBeNull();
    // توکن Push باید پاک شده باشد تا هیچ نوتیفیکیشنی به دستگاه ابطال‌شده نرود
    expect(revoke.body.device.hasPushToken).toBe(false);

    const again = await request(app)
      .post(`/api/v1/admin/devices/${deviceId}/revoke`)
      .set(auth(admin.token));
    expect(again.status).toBe(404);
  });

  /* ─────────────────────────── لاگ حسابرسی ─────────────────────────── */

  it('کنش‌های ادمین در لاگ حسابرسی ثبت شده‌اند', async () => {
    const res = await request(app)
      .get('/api/v1/admin/logs/audit?limit=100')
      .set(auth(admin.token));

    expect(res.status).toBe(200);

    const actions = res.body.logs.map((l) => l.action);
    expect(actions).toContain('admin.user.suspend');
    expect(actions).toContain('admin.user.activate');
    expect(actions).toContain('admin.user.role_change');
    expect(actions).toContain('admin.device.revoke');

    const suspendLog = res.body.logs.find((l) => l.action === 'admin.user.suspend');
    expect(suspendLog.actorUserId).toBe(admin.id);
    expect(suspendLog.entityId).toBe(reza.id);
    expect(suspendLog.metadata.reason).toBe('گزارش تخلف');
  });

  it('فیلتر لاگ حسابرسی بر اساس نوع کنش کار می‌کند', async () => {
    const res = await request(app)
      .get('/api/v1/admin/logs/audit?action=admin.user.suspend')
      .set(auth(admin.token));

    expect(res.status).toBe(200);
    expect(res.body.logs.every((l) => l.action === 'admin.user.suspend')).toBe(true);
  });

  it('نوع کنش نامعتبر در فیلتر، رد می‌شود', async () => {
    const res = await request(app)
      .get('/api/v1/admin/logs/audit?action=not.a.real.action')
      .set(auth(admin.token));

    expect(res.status).toBe(400);
  });
});

/* ═══════════════════════════════════════════════════════════════════ */

describe('لایه‌ی سنجش: لاگ درخواست و تله‌متری موقعیت', () => {
  let user;

  beforeAll(async () => {
    user = await signUp('09141110001', 'کاربر سنجش', 'primary');
  });

  it('لاگ درخواست، الگوی مسیر را ذخیره می‌کند نه شناسه‌ها را', async () => {
    // یک درخواست با شناسه در مسیر
    await request(app)
      .post(`/api/v1/alerts/${'00000000-0000-4000-8000-000000000000'}/read`)
      .set(auth(user.token));

    await telemetryService.flushAll();

    const adminLogin = await login('09131119999', 'Admin@12345');
    const res = await request(app)
      .get('/api/v1/admin/logs/requests?limit=200')
      .set(auth(adminLogin.body.accessToken));

    expect(res.status).toBe(200);

    const routes = res.body.logs.map((l) => l.route);
    expect(routes).toContain('/api/v1/alerts/:id/read');
    // هیچ UUIDی نباید در ستون مسیر نشسته باشد
    expect(routes.some((r) => /[0-9a-f]{8}-[0-9a-f]{4}/.test(r))).toBe(false);
  });

  it('پینگ موقعیت، تله‌متری تولید می‌کند', async () => {
    const res = await request(app)
      .post('/api/v1/locations/ping')
      .set(auth(user.token))
      .send({
        lat: HOME.lat,
        lng: HOME.lng,
        accuracyM: 12.5,
        provider: 'gps',
        batteryLevel: 80,
        recordedAt: new Date().toISOString(),
      });

    expect(res.status).toBe(201);
    expect(res.body.ping.provider).toBe('gps');
    expect(res.body.ping.source).toBe('device');

    await telemetryService.flushAll();

    const adminLogin = await login('09131119999', 'Admin@12345');
    const metrics = await request(app)
      .get('/api/v1/admin/metrics')
      .set(auth(adminLogin.body.accessToken));

    expect(metrics.status).toBe(200);
    expect(metrics.body.location.total).toBeGreaterThan(0);
    expect(metrics.body.location.accuracy.avgM).toBeGreaterThan(0);
    expect(metrics.body.requests.total).toBeGreaterThan(0);
    // صدک‌ها باید محاسبه شده باشند، نه فقط میانگین
    expect(metrics.body.requests.p95Ms).not.toBeNull();
  });

  it('پینگ تکراری با همان clientUuid دوباره ذخیره نمی‌شود', async () => {
    const clientUuid = '99999999-8888-4777-8666-555555555555';
    const body = {
      lat: HOME.lat,
      lng: HOME.lng,
      accuracyM: 10,
      clientUuid,
      recordedAt: new Date().toISOString(),
    };

    const first = await request(app)
      .post('/api/v1/locations/ping')
      .set(auth(user.token))
      .send(body);
    const second = await request(app)
      .post('/api/v1/locations/ping')
      .set(auth(user.token))
      .send(body);

    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    // پاسخ موفق است تا کلاینت صفش را خالی کند، ولی همان ردیف قبلی برمی‌گردد
    expect(second.body.ping.id).toBe(first.body.ping.id);
  });

  it('ارسال دسته‌ای صف آفلاین، همه را ذخیره و تکراری‌ها را رد می‌کند', async () => {
    const base = Date.now() - 10 * 60 * 1000;
    const pings = Array.from({ length: 5 }, (_, i) => ({
      lat: HOME.lat + i * 0.0002,
      lng: HOME.lng + i * 0.0002,
      accuracyM: 15,
      provider: 'fused',
      clientUuid: `aaaaaaaa-bbbb-4ccc-8ddd-00000000000${i}`,
      recordedAt: new Date(base + i * 30_000).toISOString(),
    }));

    const first = await request(app)
      .post('/api/v1/locations/batch')
      .set(auth(user.token))
      .send({ pings });

    expect(first.status).toBe(201);
    expect(first.body.accepted).toBe(5);
    expect(first.body.duplicates).toBe(0);

    // ارسال دوباره‌ی همان دسته (سناریوی قطع اتصال پس از دریافت سرور)
    const retry = await request(app)
      .post('/api/v1/locations/batch')
      .set(auth(user.token))
      .send({ pings });

    expect(retry.status).toBe(201);
    expect(retry.body.accepted).toBe(0);
    expect(retry.body.duplicates).toBe(5);
  });

  it('دسته‌ی بزرگ‌تر از سقف رد می‌شود', async () => {
    const pings = Array.from({ length: 201 }, (_, i) => ({
      lat: HOME.lat,
      lng: HOME.lng,
      recordedAt: new Date(Date.now() - i * 1000).toISOString(),
    }));

    const res = await request(app)
      .post('/api/v1/locations/batch')
      .set(auth(user.token))
      .send({ pings });

    expect(res.status).toBe(400);
  });

  it('پیکربندی کلاینت، بازه‌ی پینگ و پرچم فازهای بعد را برمی‌گرداند', async () => {
    const res = await request(app).get('/api/v1/config/client').set(auth(user.token));

    expect(res.status).toBe(200);
    expect(res.body.tracking.pingIntervalSec).toBe(30);
    expect(res.body.tracking.maxBatchSize).toBe(200);
    // فاز سوم هنوز فعال نیست و اپ باید بتواند این را بفهمد
    expect(res.body.features.fallDetection).toBe(true);
    // نام رویدادهای WebSocket از سرور می‌آید تا اپ و بک‌اند هرگز از هم جدا نیفتند
    expect(res.body.realtime.events.LOCATION_UPDATE).toBe('location:update');
  });

  it('تنظیمات دسترس‌پذیری روی سرور ذخیره می‌شود', async () => {
    const res = await request(app)
      .patch('/api/v1/settings')
      .set(auth(user.token))
      .send({ textScale: 1.6, highContrastEnabled: true, pingIntervalSec: 60 });

    expect(res.status).toBe(200);
    expect(res.body.settings.textScale).toBeCloseTo(1.6, 5);
    expect(res.body.settings.highContrastEnabled).toBe(true);
    expect(res.body.settings.pingIntervalSec).toBe(60);

    // و اپ آن را از پیکربندی کلاینت می‌خواند
    const config = await request(app).get('/api/v1/config/client').set(auth(user.token));
    expect(config.body.tracking.pingIntervalSec).toBe(60);
    expect(config.body.accessibility.textScale).toBeCloseTo(1.6, 5);
  });

  it('مقدار خارج از بازه‌ی مجاز برای بزرگ‌نمایی متن رد می‌شود', async () => {
    const res = await request(app)
      .patch('/api/v1/settings')
      .set(auth(user.token))
      .send({ textScale: 5 });

    expect(res.status).toBe(400);
  });
});
