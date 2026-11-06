import { expect, it } from 'vitest';
import { spawnSync } from 'node:child_process';

it('requires an explicit flag before seeding an isolated production-mode database', () => {
  const env = { ...process.env, NODE_ENV: 'production', DB_DRIVER: 'pglite', PGLITE_DATA_DIR: 'memory', DATABASE_URL: '',
    DEMO_MODE: 'false', JWT_ACCESS_SECRET: 'isolated-test-access-secret',
    JWT_REFRESH_SECRET: 'isolated-test-refresh-secret', INVITE_CODE_PEPPER: 'isolated-test-pepper',
    IDENTITY_DATA_ENCRYPTION_KEY: 'isolated-test-identity-key-0123456789' };
  const denied = spawnSync(process.execPath, ['src/db/seed.js'], { env, encoding: 'utf8', timeout: 30000 });
  expect(denied.status).toBe(1);
  expect(denied.stderr).toContain('--allow-production-seed');
  expect(denied.stdout).not.toContain('ساخته شد');
  const allowed = spawnSync(process.execPath, ['src/db/seed.js', '--allow-production-seed'], {
    env, encoding: 'utf8', timeout: 30000,
  });
  expect(allowed.status).toBe(0);
}, 70000);
