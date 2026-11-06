/**
 * اجراکننده‌ی مهاجرت‌ها (migrations).
 *
 * فایل‌های ‎migrations/*.sql به ترتیب نام اجرا می‌شوند و نام هر فایلِ اجراشده
 * در جدول ‎schema_migrations ثبت می‌گردد تا دوباره اجرا نشود.
 * هر مهاجرت درون یک تراکنش اجرا می‌شود: یا کامل اعمال می‌شود یا هیچ.
 *
 * اجرا:  npm run migrate
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import db from './index.js';
import env from '../config/env.js';
import logger from '../utils/logger.js';
import sensitiveDataRepository from '../repositories/sensitiveDataRepository.js';
import { assertProductionSecrets } from '../config/env.js';

const log = logger.child({ module: 'migrate' });
const MIGRATIONS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'migrations');
const MIGRATION_LOCK_ID = '741234567890123456';
let migrationQueue = Promise.resolve();

/** فقط نام‌هایی با این الگو پذیرفته می‌شوند — هم نظم می‌آورد و هم جلوی تزریق در INSERT را می‌گیرد. */
const VALID_NAME = /^\d{3}_[a-z0-9_]+\.sql$/;

async function ensureMigrationsTable() {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
}

async function appliedVersions() {
  const { rows } = await db.query('SELECT version FROM schema_migrations');
  return new Set(rows.map((r) => r.version));
}

async function migrationFiles() {
  const entries = await fs.readdir(MIGRATIONS_DIR);
  const files = entries.filter((f) => f.endsWith('.sql')).sort();

  const invalid = files.filter((f) => !VALID_NAME.test(f));
  if (invalid.length > 0) {
    throw new Error(
      `نام فایل مهاجرت نامعتبر است: ${invalid.join(', ')} — الگوی درست: 001_snake_case.sql`,
    );
  }
  return files;
}

/**
 * اجرای تمام مهاجرت‌های اعمال‌نشده.
 * @returns {Promise<string[]>} فهرست مهاجرت‌هایی که در این اجرا اعمال شدند
 */
export async function runMigrations() {
  const run = migrationQueue.then(runMigrationsQueued, runMigrationsQueued);
  // A failed run must not poison later PGlite or same-process callers.
  migrationQueue = run.catch(() => {});
  return run;
}

async function runMigrationsQueued() {
  assertProductionSecrets();
  await db.connect();

  const runLocked = async () => {
    // Check existing ciphertext before any schema changes or legacy encryption.
    await sensitiveDataRepository.assertSensitiveKeyReadable();
    return applyPendingMigrations();
  };

  // PGlite has one connection and no cross-process advisory-lock facility.
  // The module queue above serializes its callers; PostgreSQL additionally
  // uses a dedicated session lock shared by every server process.
  if (env.db.driver === 'pg') {
    return withPostgresAdvisoryLock(runLocked);
  }
  return runLocked();
}

async function applyPendingMigrations() {
  await ensureMigrationsTable();

  const applied = await appliedVersions();
  const files = await migrationFiles();
  const pending = files.filter((f) => !applied.has(f));

  if (pending.length === 0) {
    await sensitiveDataRepository.assertSensitiveKeyReadable();
    await sensitiveDataRepository.encryptLegacySensitiveData();
    log.info('دیتابیس به‌روز است؛ مهاجرت جدیدی وجود ندارد', { total: files.length });
    return [];
  }

  log.info('اجرای مهاجرت‌های جدید', { pending: pending.length });

  for (const file of pending) {
    const sql = await fs.readFile(path.join(MIGRATIONS_DIR, file), 'utf8');
    const started = Date.now();

    // نام فایل با VALID_NAME اعتبارسنجی شده، پس درج مستقیم آن امن است
    await db.exec(`BEGIN;\n${sql}\n;INSERT INTO schema_migrations (version) VALUES ('${file}');\nCOMMIT;`);

    log.info('مهاجرت اعمال شد', { file, ms: Date.now() - started });
  }

  await sensitiveDataRepository.assertSensitiveKeyReadable();
  await sensitiveDataRepository.encryptLegacySensitiveData();

  return pending;
}

/**
 * Serialize schema upgrades across independent PostgreSQL processes.
 * The lock client is dedicated because advisory locks are session-scoped;
 * using a pooled query could release it as soon as the pool chooses another
 * connection. Closing the dedicated client also releases the lock on errors.
 */
export async function withPostgresAdvisoryLock(work, createClient) {
  let client;
  let locked = false;
  try {
    if (createClient) {
      client = await createClient();
    } else {
      const { Client } = await import('pg');
      client = new Client({ connectionString: env.db.url });
    }
    await client.connect();
    await client.query('SELECT pg_advisory_lock($1::bigint)', [MIGRATION_LOCK_ID]);
    locked = true;
    return await work();
  } finally {
    if (client) {
      if (locked) {
        try {
          await client.query('SELECT pg_advisory_unlock($1::bigint)', [MIGRATION_LOCK_ID]);
        } catch (error) {
          // Closing the session below is the final release path if UNLOCK fails.
          log.error('آزاد کردن قفل مهاجرت ناموفق بود؛ اتصال اختصاصی بسته می‌شود', {
            error: error.message,
          });
        }
      }
      try {
        await client.end();
      } catch (error) {
        log.error('بستن اتصال اختصاصی قفل مهاجرت ناموفق بود', {
          error: error.message,
        });
      }
    }
  }
}

// اگر مستقیم اجرا شود (نه import)، مهاجرت‌ها را اجرا کن و خارج شو
const isDirectRun = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (isDirectRun) {
  try {
    const applied = await runMigrations();
    console.log(
      applied.length > 0
        ? `\n✅ ${applied.length} مهاجرت با موفقیت اعمال شد.\n`
        : '\n✅ دیتابیس از قبل به‌روز بود.\n',
    );
    await db.close();
    process.exit(0);
  } catch (error) {
    log.error('اجرای مهاجرت‌ها شکست خورد', { error: error.message });
    console.error(`\n❌ خطا: ${error.message}\n`);
    await db.close().catch(() => {});
    process.exit(1);
  }
}
