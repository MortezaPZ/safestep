import { beforeAll, afterAll, expect, it } from 'vitest';
import { createCipheriv, createHash, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import request from 'supertest';

process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'pglite';
process.env.PGLITE_DATA_DIR = 'memory';
process.env.IDENTITY_DATA_ENCRYPTION_KEY = 'current-isolated-test-key-0123456789';
const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { encryptSensitiveValue } = await import('../src/utils/sensitiveData.js');
let app;

beforeAll(async () => { await db.connect(); await runMigrations(); app = createApp(); });
afterAll(async () => { await db.close(); });

it('rejects an incompatible key before encrypting legacy values', async () => {
  async function user(phone) {
    const res = await request(app).post('/api/v1/auth/register').send({
      phone, password: 'Test@1234', fullName: 'آزمون', role: 'primary',
    });
    expect(res.status).toBe(201);
    return res.body.user.id;
  }
  const encryptedUser = await user('09151119781');
  const legacyUser = await user('09151119782');
  const iv = randomBytes(12);
  const key = createHash('sha256').update('a-different-encryption-key').digest();
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update('private', 'utf8'), cipher.final()]);
  const otherKeyValue = 'enc:v1:' + [iv, cipher.getAuthTag(), ciphertext].map((part) => part.toString('base64')).join(':');
  await db.query('UPDATE users SET health_condition = $2 WHERE id = $1', [encryptedUser, otherKeyValue]);
  await db.query('UPDATE users SET health_condition = $2 WHERE id = $1', [legacyUser, 'legacy value']);
  await db.query("DELETE FROM schema_migrations WHERE version = '018_supervisor_unique.sql'");
  await expect(runMigrations()).rejects.toThrow('کلید رمزنگاری');
  const pending = await db.query("SELECT count(*)::int AS n FROM schema_migrations WHERE version = '018_supervisor_unique.sql'");
  expect(pending.rows[0].n).toBe(0);
  const before = await db.query('SELECT health_condition FROM users WHERE id = $1', [legacyUser]);
  expect(before.rows[0].health_condition).toBe('legacy value');
  await db.query('UPDATE users SET health_condition = $2 WHERE id = $1', [encryptedUser, encryptSensitiveValue('private')]);
  await runMigrations();
  const after = await db.query('SELECT health_condition FROM users WHERE id = $1', [legacyUser]);
  expect(after.rows[0].health_condition.startsWith('enc:v1:')).toBe(true);
});

it('rejects sample production keys before opening a database', () => {
  const env = { ...process.env, NODE_ENV: 'production', DEMO_MODE: 'false', DB_DRIVER: 'pglite',
    PGLITE_DATA_DIR: 'memory', JWT_ACCESS_SECRET: 'isolated-access', JWT_REFRESH_SECRET: 'isolated-refresh',
    INVITE_CODE_PEPPER: 'isolated-pepper', IDENTITY_DATA_ENCRYPTION_KEY: 'dev-only-invalid' };
  const child = spawnSync(process.execPath, ['src/db/migrate.js'], { env, encoding: 'utf8', timeout: 15000 });
  expect(child.status).toBe(1);
  expect(child.stderr).toContain('IDENTITY_DATA_ENCRYPTION_KEY');
  expect(child.stdout).not.toContain('اتصال به دیتابیس برقرار شد');
});
