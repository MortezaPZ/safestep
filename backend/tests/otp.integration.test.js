import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.SMS_DRIVER = 'console';
process.env.PHONE_VERIFICATION_REQUIRED = 'false';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { consumeLastDispatch } = await import('../src/services/smsAdapter.js');
const env = (await import('../src/config/env.js')).default;

const PASSWORD = 'Test@1234';
let app;

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();
});

afterAll(async () => {
  await db.close();
});

describe('OTP پیامک', () => {
  it('پیکربندی عمومی درایور را نشان می‌دهد', async () => {
    const res = await request(app).get('/api/v1/config/public');
    expect(res.status).toBe(200);
    expect(res.body.smsDriver).toBe('console');
    expect(res.body.phoneVerificationRequired).toBe(false);
  });

  it('سلامت سرویس وضعیت پیامک دارد', async () => {
    const res = await request(app).get('/health');
    expect(res.body.sms.driver).toBe('console');
  });

  it('درخواست کد را می‌فرستد', async () => {
    const res = await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770001', purpose: 'register' });
    expect(res.status).toBe(200);
    expect(res.body.hint).toContain('لاگ');
    const sent = consumeLastDispatch();
    expect(sent.code).toMatch(/^\d{6}$/);
  });

  it('کد درست توکن تأیید می‌دهد', async () => {
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770002', purpose: 'register' });
    const sent = consumeLastDispatch();
    const res = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770002', code: sent.code, purpose: 'register' });
    expect(res.status).toBe(200);
    expect(res.body.verificationToken).toBeTruthy();
  });

  it('کد غلط رد می‌شود', async () => {
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770003', purpose: 'register' });
    consumeLastDispatch();
    const res = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770003', code: '000000', purpose: 'register' });
    expect(res.status).toBe(401);
  });

  it('کد منقضی رد می‌شود', async () => {
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770004', purpose: 'register' });
    const sent = consumeLastDispatch();
    await db.query(
      `UPDATE phone_otps SET expires_at = now() - interval '1 minute' WHERE phone = $1`,
      ['09127770004'],
    );
    const res = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770004', code: sent.code, purpose: 'register' });
    expect(res.status).toBe(401);
  });

  it('پس از پنج تلاش قفل می‌شود', async () => {
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770005', purpose: 'register' });
    consumeLastDispatch();
    for (let i = 0; i < 5; i += 1) {
      await request(app)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: '09127770005', code: '111111', purpose: 'register' });
    }
    const res = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770005', code: '111111', purpose: 'register' });
    expect(res.status).toBe(429);
  });

  it('نرخ درخواست بیش از سه تا در ده دقیقه محدود است', async () => {
    const phone = '09127770006';
    for (let i = 0; i < 3; i += 1) {
      const r = await request(app).post('/api/v1/auth/otp/request').send({ phone, purpose: 'login' });
      expect(r.status).toBe(200);
      consumeLastDispatch();
    }
    const res = await request(app).post('/api/v1/auth/otp/request').send({ phone, purpose: 'login' });
    expect(res.status).toBe(429);
  });

  it('بدون الزام، ثبت‌نام بدون توکن ممکن است', async () => {
    const res = await request(app).post('/api/v1/auth/register').send({
      phone: '09127770007',
      password: PASSWORD,
      fullName: 'بدون تأیید',
      role: 'primary',
    });
    expect(res.status).toBe(201);
    expect(res.body.user.phoneVerifiedAt).toBeNull();
  });

  it('با پرچم الزام، ثبت‌نام بدون توکن رد می‌شود', async () => {
    env.auth.phoneVerificationRequired = true;
    const res = await request(app).post('/api/v1/auth/register').send({
      phone: '09127770008',
      password: PASSWORD,
      fullName: 'باید تأیید شود',
      role: 'primary',
    });
    expect(res.status).toBe(401);
    env.auth.phoneVerificationRequired = false;
  });

  it('با پرچم الزام و توکن معتبر، شماره تأیید می‌شود', async () => {
    env.auth.phoneVerificationRequired = true;
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770009', purpose: 'register' });
    const sent = consumeLastDispatch();
    const verify = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770009', code: sent.code, purpose: 'register' });
    const res = await request(app).post('/api/v1/auth/register').send({
      phone: '09127770009',
      password: PASSWORD,
      fullName: 'تأییدشده',
      role: 'primary',
      verificationToken: verify.body.verificationToken,
    });
    expect(res.status).toBe(201);
    expect(res.body.user.phoneVerifiedAt).toBeTruthy();
    env.auth.phoneVerificationRequired = false;
  });

  it('توکن با purpose دیگر برای ثبت‌نام قبول نمی‌شود', async () => {
    env.auth.phoneVerificationRequired = true;
    await request(app)
      .post('/api/v1/auth/otp/request')
      .send({ phone: '09127770010', purpose: 'login' });
    const sent = consumeLastDispatch();
    const verify = await request(app)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: '09127770010', code: sent.code, purpose: 'login' });
    const res = await request(app).post('/api/v1/auth/register').send({
      phone: '09127770010',
      password: PASSWORD,
      fullName: 'غلط',
      role: 'primary',
      verificationToken: verify.body.verificationToken,
    });
    expect(res.status).toBe(401);
    env.auth.phoneVerificationRequired = false;
  });
});
