/**
 * تست بار واقعی روی PostgreSQL شبکه‌ای — فصل ارزیابی پروپوزال.
 *
 * تفاوت با scripts/loadtest.js: آن اسکریپت PGlite را به عنوان پیش‌فرض می‌پذیرد
 * و در صورت وجود DATABASE_URL از همان استفاده می‌کند. ولی PGlite تک‌اتصاله
 * و درون‌پردازه‌ای است و نتیجه‌اش نماینده‌ی یک سرور تولیدی نیست. این اسکریپت
 * PostgreSQL واقعی را الزام می‌کند و اگر DATABASE_URL به Postgres اشاره نکند
 * صریحاً رد می‌شود.
 *
 * اجرا:
 *   DATABASE_URL=postgres://safestep:***@localhost:5432/safestep \
 *   LOADTEST_DURATION=15 node scripts/loadtest-postgres.js
 *
 * رد کردن در صورتی که Postgres نباشد:
 *   EXIT_CODE=4 و پیام روشن.
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import autocannon from 'autocannon';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPORT_DIR = path.resolve(ROOT, 'docs/evaluation');
const PASSWORD = 'Load@1234';

// این مقادیر باید قبل از import کردن config تنظobuf شوند تا env.db.driver
// درست محاسبه شود. به همین دلیل همه‌ی importهای پروژه بعد از این خط می‌آیند.
process.env.LOADTEST = '1';
process.env.NODE_ENV = process.env.NODE_ENV || 'development';
process.env.DEMO_MODE = 'true';

const DATABASE_URL = process.env.DATABASE_URL || '';
const DB_DRIVER = (process.env.DB_DRIVER || '').toLowerCase();

/**
 * پذیرفتن فقط PostgreSQL شبکه‌ای.
 * هیچ‌گاه PGlite را به عنوان جایگزین نمی‌پذیریم: هدف این سنجه، اندازه‌گیری
 * رفتار سیستم روی یک دیتابیس واقعی با connection pool است، نه یک
 * درون‌پردازه‌ی تک‌اتصاله.
 */
function assertPostgres() {
  if (!DATABASE_URL) {
    return {
      ok: false,
      code: 'NO_DATABASE_URL',
      message:
        'DATABASE_URL تنظیم نشده. این اسکریپت فقط روی PostgreSQL واقعی اجرا می‌شود. ' +
        'PGlite نتیجه را جایگزین نمی‌کند — تک‌اتصاله و درون‌پردازه‌ای است و ' +
        'نماینده‌ی یک سرور تولیدی نیست.',
    };
  }

  const url = DATABASE_URL.trim();
  const looksPostgres = /^postgres(ql)?:\/\//i.test(url);
  if (!looksPostgres) {
    return {
      ok: false,
      code: 'DATABASE_URL_NOT_POSTGRES',
      message: `DATABASE_URL به PostgreSQL اشاره نمی‌کند (ارزش: «${url.slice(0, 24)}…»).`,
    };
  }

  // یک DB_DRIVER صریح که pg نباشد را رد می‌کنیم تا نتایج سوء‌بردار نشود
  if (DB_DRIVER && !['pg', 'postgres', 'postgresql'].includes(DB_DRIVER)) {
    return {
      ok: false,
      code: 'DB_DRIVER_NOT_PG',
      message: `DB_DRIVER=${DB_DRIVER} است. این اسکریپت فقط pg را می‌پذیرد.`,
    };
  }

  return { ok: true };
}

/**
 * اطمینان از اینکه دیتابیس واقعاً از بیرون پردازه در دسترس است.
 * اگر سبیل سیم‌کشی دیتابیس قطع باشد، خود بخواهیم به جای نتیجهٔ فیک، خطا بدهیم.
 */
async function probePostgres() {
  const { default: pg } = await import('pg');
  const pool = new pg.Pool({ connectionString: DATABASE_URL, max: 2, connectionTimeoutMillis: 5_000 });
  try {
    const res = await pool.query('SELECT version() AS v, current_setting(\'max_connections\')::int AS mc');
    return {
      ok: true,
      version: res.rows[0]?.v?.split(' ')?.[1] ?? null,
      maxConnections: res.rows[0]?.mc ?? null,
    };
  } finally {
    await pool.end();
  }
}

const { createApp } = await import('../src/app.js');
const db = (await import('../src/db/index.js')).default;
const { runMigrations } = await import('../src/db/migrate.js');
const { hashPassword } = await import('../src/utils/crypto.js');
const telemetryService = (await import('../src/services/telemetryService.js')).default;

const DURATION = Number(process.env.LOADTEST_DURATION || 15);

async function listen(app) {
  const server = http.createServer(app);
  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', (err) => (err ? reject(err) : resolve()));
  });
  const { port } = server.address();
  return { server, port };
}

async function seedLoad(nPrimary) {
  const hash = await hashPassword(PASSWORD);
  const primaries = [];
  for (let i = 0; i < nPrimary; i += 1) {
    const phone = `0914${String(1000000 + i).slice(-7)}`;
    const { rows } = await db.query(
      `INSERT INTO users (phone, password_hash, full_name, role, verification_status)
       VALUES ($1,$2,$3,'primary','verified') RETURNING id`,
      [phone, hash, `بار ${i}`],
    );
    await db.query('INSERT INTO user_settings (user_id) VALUES ($1)', [rows[0].id]);
    primaries.push({ id: rows[0].id, phone });
  }
  return primaries;
}

async function login(port, phone) {
  const res = await fetch(`http://127.0.0.1:${port}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, password: PASSWORD }),
  });
  const data = await res.json();
  if (!data.accessToken) throw new Error(`ورود ناموفق برای ${phone}: ${JSON.stringify(data)}`);
  return data.accessToken;
}

function summarize(result) {
  const lat = result.latency;
  return {
    requests: result.requests.total,
    throughput: result.throughput.mean,
    errors: result.errors + result.non2xx,
    p50: lat.p50,
    p95: lat.p95 ?? lat.p97_5 ?? lat.p90,
    p99: lat.p99,
    mean: lat.mean,
  };
}

async function runCannon(url, { method, headers, body, connections, duration, title }) {
  const result = await autocannon({
    url, method, headers, body, connections, duration, pipelining: 1, title,
  });
  return summarize(result);
}

/**
 * سنجه‌های اضافهٔ مخصوص Postgres — پارامترهای استخر که فقط در این درایور
 * قابل مشاهده‌اند. بدون این بخش، تفاوت PGlite و Postgres از گزارش معلوم
 * نمی‌شود.
 */
async function poolStats() {
  try {
    const { rows } = await db.query(
      `SELECT count(*)::int AS total,
              count(*) FILTER (WHERE state = 'active')::int AS active,
              count(*) FILTER (WHERE state = 'idle')::int AS idle
         FROM pg_stat_activity
        WHERE datname = current_database()`,
    );
    return rows[0] ?? null;
  } catch {
    return null;
  }
}

function toMd(rows, { probe, poolBefore, poolAfter, duration }) {
  const date = new Date().toISOString().slice(0, 10);
  const lines = [
    `# تست بار روی PostgreSQL واقعی — ${date}`,
    '',
    'این گزارش فقط با `DATABASE_URL` به PostgreSQL واقعی تولید می‌شود. PGlite',
    'تک‌اتصاله و درون‌پردازه‌ای است و نتیجه‌اش نماینده‌ی تولید نیست، پس جایگزین',
    'این سنجه نمی‌شود.',
    '',
    `سرور پایگاه داده: PostgreSQL ${probe.version ?? 'نامعلوم'} ` +
      `(حداکثر اتصال پیکربندی‌شده: ${probe.maxConnections ?? 'نامعلوم'})`,
    `مدت هر سناریو: ${duration} ثانیه. درایور: pg.`,
    '',
    '| سناریو | درخواست | میانگین ms | p50 | p95 | p99 | خطا |',
    '| --- | --- | --- | --- | --- | --- | --- |',
  ];
  for (const r of rows) {
    lines.push(`| ${r.title} | ${r.requests} | ${r.mean} | ${r.p50} | ${r.p95} | ${r.p99} | ${r.errors} |`);
  }
  if (poolBefore || poolAfter) {
    lines.push('');
    lines.push('## اتصال‌های دیتابیس در حین بار');
    lines.push('');
    lines.push('| زمان | کل | فعال | بیکار |');
    lines.push('| --- | --- | --- | --- |');
    if (poolBefore) lines.push(`| پیش از بار | ${poolBefore.total} | ${poolBefore.active} | ${poolBefore.idle} |`);
    if (poolAfter) lines.push(`| در اوج بار | ${poolAfter.total} | ${poolAfter.active} | ${poolAfter.idle} |`);
  }
  return `${lines.join('\n')}\n`;
}

async function main() {
  const check = assertPostgres();
  if (!check.ok) {
    process.stderr.write(`\n❌ ${check.message}\n\n`);
    process.stderr.write(`کد خطا: ${check.code}\n`);
    process.stderr.write('دستور اجرای صحیح:\n');
    process.stderr.write(
      '  DATABASE_URL=postgres://safestep:***@localhost:5432/safestep ' +
        'LOADTEST_DURATION=15 node scripts/loadtest-postgres.js\n\n',
    );
    process.exitCode = 4;
    return;
  }

  process.env.DB_DRIVER = 'pg';

  let probe;
  try {
    probe = await probePostgres();
  } catch (error) {
    process.stderr.write(`\n❌ اتصال به PostgreSQL برقرار نشد: ${error.message}\n\n`);
    process.stderr.write('سرور باید در حال اجرا و قابل دسترس باشد.\n\n');
    process.exitCode = 4;
    return;
  }

  await db.connect();
  await runMigrations();
  telemetryService.setEnabled(true);

  const primaries = await seedLoad(50);
  const app = createApp();
  const { server, port } = await listen(app);
  const token = await login(port, primaries[0].phone);
  const auth = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
  const pingBody = JSON.stringify({ lat: 35.72, lng: 51.33, accuracyM: 8, batteryLevel: 80 });

  const rows = [];
  const poolBefore = await poolStats();

  for (const rate of [50, 100, 200]) {
    const connections = Math.min(50, Math.max(10, Math.round(rate / 4)));
    const s = await runCannon(`http://127.0.0.1:${port}/api/v1/locations/ping`, {
      method: 'POST', headers: auth, body: pingBody, connections,
      duration: DURATION, title: `ping ~${rate}`,
    });
    rows.push({
      title: `POST /locations/ping (هدف ${rate}/s، ${connections} اتصال)`,
      ...s,
    });
  }

  const poolAfter = await poolStats();

  rows.push({
    title: 'GET /locations/watching',
    ...(await runCannon(`http://127.0.0.1:${port}/api/v1/locations/watching`, {
      method: 'GET', headers: auth, connections: 20, duration: DURATION, title: 'watching',
    })),
  });

  rows.push({
    title: 'GET /locations/history',
    ...(await runCannon(
      `http://127.0.0.1:${port}/api/v1/locations/history?limit=500&from=2026-01-01T00:00:00Z&to=2026-12-31T00:00:00Z`,
      { method: 'GET', headers: auth, connections: 20, duration: DURATION, title: 'history' },
    )),
  });

  const md = toMd(rows, { probe, poolBefore, poolAfter, duration: DURATION });

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const file = path.join(REPORT_DIR, `load-test-postgres-${new Date().toISOString().slice(0, 10)}.md`);
  fs.writeFileSync(file, md, 'utf8');

  process.stdout.write(md);
  process.stdout.write(`\nwrote ${file}\n`);

  server.close();
  await telemetryService.flushAll().catch(() => {});
  await db.close();
}

await main();
