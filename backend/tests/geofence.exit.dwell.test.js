/**
 * آزمون حصار جغرافیایی — پوشش شکاف موجود.
 *
 * تست‌های geofence*.js موجود، موتور را روی فاصله‌های انتزاعی یا چندضلعی‌ها
 * آزمایش می‌کنند. این فایل دو مسیر کامل API را پوشش می‌دهد که در هیچ‌کدام
 * از آن‌ها نیست:
 *
 *   ۱) خروج واقعی از یک محدوده‌ی دایره‌ای هشدار zone_exit می‌سازد
 *      (و خروج از محدوده‌ی دیگر مزاحمت نمی‌کند).
 *   ۲) ماندن بیرون از محدوده (dwell) پس از گذشت dwellAlertMinutes
 *      هشدار ماندگاری می‌سازد — با زمان ثبت واقعی پینگ‌ها، نه با
 *      دستکاری مستقیم ردیف دیتابیس.
 *
 * تفاوت با تست موجود: در safezone‌ها.تست موجود dwell را با عقب کشیدن
 * last_transition_at در دیتابیس شبیه‌سازی می‌کند. اینجا گذار زمان واقعی
 * در ستون recorded_at پینگ‌هاست؛ یعنی همان چیزی که در تولید رخ می‌دهد.
 */
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
const { invalidateAccountState } = await import('../src/middleware/auth.js');

const PASSWORD = 'Test@1234';
const HOME = { lat: 35.7219, lng: 51.3347 };
let app;
const auth = (t) => ({ Authorization: 'Bearer ' + t });

/**
 * ثبت پینگ با زمان ثبت مشخص.
 * کلاینت واقعی recorded_at را می‌فرستد؛ این توانایی برای شبیه‌سازی زمان
 * واقعی لازم است.
 */
async function pingAt(token, point, recordedAt) {
  return request(app)
    .post('/api/v1/locations/ping')
    .set(auth(token))
    .send({ ...point, recordedAt: recordedAt.toISOString(), accuracyM: 6 });
}

async function signUp(phone, name) {
  const res = await request(app).post('/api/v1/auth/register').send({
    phone, password: PASSWORD, fullName: name, role: 'primary',
  });
  expect(res.status).toBe(201);
  const id = res.body.user.id;
  await db.query("UPDATE users SET verification_status = 'verified' WHERE id = $1", [id]);
  invalidateAccountState(id);
  return { token: res.body.accessToken, id };
}

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  await db.close();
});

describe('خروج واقعی از محدوده‌ی امن هشدار می‌سازد', () => {
  let user;
  const RADIUS = 120;
  // مقصدِ واقعاً بیرون: فراتر از شعاع + هیسترزیس
  const OUT = destinationPoint(HOME.lat, HOME.lng, RADIUS + 400, 75);

  it('کاربر ثبت‌نام می‌کند', async () => {
    user = await signUp('09152220001', 'حصار خروج', 'primary');
  });

  it('محدوده‌ی دایره‌ای با ماندگاری ۳ دقیقه‌ای ساخته می‌شود', async () => {
    const res = await request(app)
      .post('/api/v1/safe-zones')
      .set(auth(user.token))
      .send({
        name: 'خانه',
        centerLat: HOME.lat,
        centerLng: HOME.lng,
        radiusM: RADIUS,
        alertOnExit: true,
        alertOnEnter: true,
        dwellAlertMinutes: 3,
      });
    expect(res.status).toBe(201);
    expect(res.body.dwellAlertMinutes).toBe(3);
  });

  it('اولین پینگ داخل محدوده، هشدار نمی‌دهد', async () => {
    const at = new Date(Date.now() - 10 * 60_000);
    const res = await pingAt(user.token, HOME, at);
    expect(res.status).toBe(201);
    expect(res.body.alerts).toHaveLength(0);
  });

  it('یک پینگ بیرون هنوز هشدار نمی‌دهد (debounce)', async () => {
    const at = new Date(Date.now() - 9 * 60_000);
    const res = await pingAt(user.token, OUT, at);
    expect(res.status).toBe(201);
    expect(res.body.alerts.filter((a) => a.type === 'zone_exit')).toHaveLength(0);
  });

  it('پینگ بیرونِ بعدی، دقیقاً یک هشدار خروج می‌سازد', async () => {
    const at = new Date(Date.now() - 8 * 60_000);
    const res = await pingAt(user.token, OUT, at);
    expect(res.status).toBe(201);
    const exits = res.body.alerts.filter((a) => a.type === 'zone_exit');
    expect(exits).toHaveLength(1);
    expect(exits[0].zoneName ?? exits[0].metadata?.zoneName).toBeTruthy();
    // متن هشدار خروج ساده است، نه متن ماندگاری
    expect(exits[0].body).not.toMatch(/ماندگاری|دقیقه/);
  });
});

describe('ماندن بیرون از محدوده (dwell) هشدار می‌سازد', () => {
  let user;
  const RADIUS = 100;
  const OUT = destinationPoint(HOME.lat, HOME.lng, RADIUS + 500, 190);
  const DWELL_MIN = 3;

  it('کاربر و محدوده را می‌سازد', async () => {
    user = await signUp('09152220002', 'حصار ماندگاری', 'primary');
    const res = await request(app)
      .post('/api/v1/safe-zones')
      .set(auth(user.token))
      .send({
        name: 'خانه',
        centerLat: HOME.lat,
        centerLng: HOME.lng,
        radiusM: RADIUS,
        dwellAlertMinutes: DWELL_MIN,
      });
    expect(res.status).toBe(201);
  });

  /**
   * گذر زمان واقعی: پینگ‌ها با recorded_at در گذشته می‌آیند تا
   * موتور dwell بر اساس همان منطقی که در تولید اجرا می‌شود،
   * last_transition_at را در لحظه‌ی گذار واقعی ثبت کند.
   */
  it('خروج تأیید می‌شود', async () => {
    const t0 = Date.now() - 20 * 60_000;
    await pingAt(user.token, HOME, new Date(t0));
    await pingAt(user.token, OUT, new Date(t0 + 60_000));
    const res = await pingAt(user.token, OUT, new Date(t0 + 2 * 60_000));
    expect(res.body.alerts.filter((a) => a.type === 'zone_exit')).toHaveLength(1);
  });

  it('کوتاه‌تر از مدت ماندگاری، هشدار ماندگاری نمی‌دهد', async () => {
    const t0 = Date.now() - 20 * 60_000;
    // گذار در t0+2 دقیقه رخ داده؛ اکنون فقط ۱ دقیقه بعد‌تریم
    const res = await pingAt(user.token, OUT, new Date(t0 + 3 * 60_000));
    expect(res.status).toBe(201);
    expect(res.body.alerts.filter((a) => a.metadata?.dwellMinutes)).toHaveLength(0);
  });

  it('پس از گذشت مدت ماندگاری، هشدار ماندگاری می‌سازد', async () => {
    const res = await pingAt(user.token, OUT, new Date(Date.now() - 30_000));
    expect(res.status).toBe(201);
    const dwell = res.body.alerts.filter((a) => a.metadata?.dwellMinutes === DWELL_MIN);
    expect(dwell).toHaveLength(1);
    expect(dwell[0].body).toMatch(new RegExp(String(DWELL_MIN)));
  });

  it('هر پینگ بعدی، هشدار ماندگاری تکراری نمی‌سازد', async () => {
    const res = await pingAt(user.token, OUT, new Date(Date.now() - 20_000));
    expect(res.status).toBe(201);
    expect(res.body.alerts.filter((a) => a.metadata?.dwellMinutes)).toHaveLength(0);
  });

  it('بازگشت به داخل، زنجیره را پاک می‌کند و خروج دوباره کار می‌کند', async () => {
    // بازگشت
    await pingAt(user.token, HOME, new Date(Date.now() - 15_000));
    await pingAt(user.token, HOME, new Date(Date.now() - 10_000));

    // خروج دوباره
    const t1 = Date.now() - 5_000;
    await pingAt(user.token, OUT, new Date(t1));
    const res = await pingAt(user.token, OUT, new Date(t1 + 1_000));
    expect(res.body.alerts.filter((a) => a.type === 'zone_exit')).toHaveLength(1);
    // چون تازه بیرون رفته، ماندگاری نباید فوراً بشود
    expect(res.body.alerts.filter((a) => a.metadata?.dwellMinutes)).toHaveLength(0);
  });
});

describe('محدوده با ماندگاری خاموش، هشدار ماندگاری نمی‌دهد', () => {
  const user = { token: null, id: null };
  const RADIUS = 90;
  const OUT = destinationPoint(HOME.lat, HOME.lng, RADIUS + 300, 10);

  it('کاربر و محدوده بدون dwell', async () => {
    const signed = await signUp('09152220003', 'بدون ماندگاری');
    user.token = signed.token;
    user.id = signed.id;
    const res = await request(app)
      .post('/api/v1/safe-zones')
      .set(auth(user.token))
      .send({
        name: 'خانه',
        centerLat: HOME.lat,
        centerLng: HOME.lng,
        radiusM: RADIUS,
      });
    expect(res.status).toBe(201);
    expect(res.body.dwellAlertMinutes).toBeNull();
  });

  it('خروج هشدار می‌دهد ولی ماندگاری نمی‌دهد', async () => {
    const t0 = Date.now() - 40 * 60_000;
    await pingAt(user.token, HOME, new Date(t0));
    await pingAt(user.token, OUT, new Date(t0 + 60_000));
    const res2 = await pingAt(user.token, OUT, new Date(t0 + 2 * 60_000));
    // مدت‌هاست که بیرون است، ولی چون dwellAlertMinutes خالی است نباید هشدار ماندگاری باشد
    const res = await pingAt(user.token, OUT, new Date(Date.now() - 30_000));
    expect(res2.body.alerts.filter((a) => a.type === 'zone_exit')).toHaveLength(1);
    expect(res.body.alerts).toHaveLength(0);
    expect(res.body.status.status).toBe('outside');
  });
});
