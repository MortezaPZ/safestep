/**
 * تست بار برای فصل ارزیابی.
 * PGLITE_DATA_DIR=memory روی پورت تصادفی؛ اگر DATABASE_URL باشد همان سناریو روی pg هم اجرا می‌شود.
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import autocannon from 'autocannon';

process.env.LOADTEST = '1';
process.env.NODE_ENV = process.env.NODE_ENV === 'test' ? 'development' : (process.env.NODE_ENV || 'development');
process.env.PGLITE_DATA_DIR = process.env.PGLITE_DATA_DIR || 'memory';
process.env.DB_DRIVER = process.env.DB_DRIVER || 'pglite';
process.env.DEMO_MODE = 'true';

const { createApp } = await import('../src/app.js');
const db = (await import('../src/db/index.js')).default;
const { runMigrations } = await import('../src/db/migrate.js');
const { hashPassword } = await import('../src/utils/crypto.js');
const telemetryService = (await import('../src/services/telemetryService.js')).default;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const PASSWORD = 'Load@1234';
const DURATION = Number(process.env.LOADTEST_DURATION || 15);

async function listen(app) {
  const server = http.createServer(app);
  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', (err) => (err ? reject(err) : resolve()));
  });
  const { port } = server.address();
  return { server, port };
}

async function seedLoad(nPrimary, nGuardian) {
  const hash = await hashPassword(PASSWORD);
  const primaries = [];
  for (let i = 0; i < nPrimary; i += 1) {
    const phone = `0914${String(1000000 + i).slice(-7)}`;
    const { rows } = await db.query(
      `INSERT INTO users (phone, password_hash, full_name, role)
       VALUES ($1,$2,$3,'primary') RETURNING id`,
      [phone, hash, `بار ${i}`],
    );
    await db.query('INSERT INTO user_settings (user_id) VALUES ($1)', [rows[0].id]);
    primaries.push({ id: rows[0].id, phone });
  }
  for (let i = 0; i < nGuardian; i += 1) {
    const phone = `0915${String(1000000 + i).slice(-7)}`;
    await db.query(
      `INSERT INTO users (phone, password_hash, full_name, role)
       VALUES ($1,$2,$3,'guardian')`,
      [phone, hash, `مراقب بار ${i}`],
    );
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
  if (!data.accessToken) {
    throw new Error(`ورود ناموفق برای ${phone}: ${JSON.stringify(data)}`);
  }
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
    url,
    method,
    headers,
    body,
    connections,
    duration,
    pipelining: 1,
    title,
  });
  return summarize(result);
}

function toMd(rows) {
  const date = new Date().toISOString().slice(0, 10);
  const lines = [
    `# تست بار ${date}`,
    '',
    `مدت هر سناریو: ${DURATION} ثانیه. درایور: ${process.env.DB_DRIVER}.`,
    '',
    '| سناریو | درخواست | میانگین ms | p50 | p95 | p99 | خطا |',
    '| --- | --- | --- | --- | --- | --- | --- |',
  ];
  for (const r of rows) {
    lines.push(`| ${r.title} | ${r.requests} | ${r.mean} | ${r.p50} | ${r.p95} | ${r.p99} | ${r.errors} |`);
  }
  return `${lines.join('\n')}\n`;
}

async function main() {
  await db.connect();
  await runMigrations();
  telemetryService.setEnabled(true);
  const primaries = await seedLoad(50, 100);
  const app = createApp();
  const { server, port } = await listen(app);
  const token = await login(port, primaries[0].phone);
  const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const pingBody = JSON.stringify({
    lat: 35.72,
    lng: 51.33,
    accuracyM: 8,
    batteryLevel: 80,
  });

  const rows = [];
  for (const rate of [50, 100, 200]) {
    const connections = Math.min(50, Math.max(10, Math.round(rate / 4)));
    const s = await runCannon(`http://127.0.0.1:${port}/api/v1/locations/ping`, {
      method: 'POST',
      headers: auth,
      body: pingBody,
      connections,
      duration: DURATION,
      title: `ping ~${rate} conn=${connections}`,
    });
    rows.push({ title: s.title ?? `ping ${rate}`, ...s, title: `POST /locations/ping (هدف ${rate}/s، ${connections} اتصال)` });
  }

  rows.push({
    title: 'GET /locations/watching',
    ...(await runCannon(`http://127.0.0.1:${port}/api/v1/locations/watching`, {
      method: 'GET',
      headers: auth,
      connections: 20,
      duration: DURATION,
      title: 'watching',
    })),
  });

  rows.push({
    title: 'POST /sos burst',
    ...(await runCannon(`http://127.0.0.1:${port}/api/v1/sos`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({ lat: 35.72, lng: 51.33, note: 'load' }),
      connections: 4,
      duration: Math.min(8, DURATION),
      title: 'sos',
    })),
  });

  const adminPhone = '09149990000';
  const hash = await hashPassword(PASSWORD);
  const adminIns = await db.query(
    `INSERT INTO users (phone, password_hash, full_name, role)
     VALUES ($1,$2,'ادمین بار','admin') RETURNING id`,
    [adminPhone, hash],
  );
  await db.query('INSERT INTO user_settings (user_id) VALUES ($1)', [adminIns.rows[0].id]);
  const adminToken = await login(port, adminPhone);
  await telemetryService.flush();
  const metricsRes = await fetch(`http://127.0.0.1:${port}/api/v1/admin/metrics`, {
    headers: { Authorization: `Bearer ${adminToken}` },
  });
  const metrics = await metricsRes.json();

  const md = `${toMd(rows)}
## مقایسه با سنجه‌ی سرور

تأخیر میانگین درخواست‌ها در \`GET /admin/metrics\`: ${metrics.requests?.avgMs ?? '—'} ms
p95 سرور: ${metrics.requests?.p95Ms ?? '—'} ms

این مقایسه نشان می‌دهد لایه‌ی اندازه‌گیری داخلی با ناظر خارجی (\`autocannon\`) هم‌خوان است.
`;
  const outDir = path.join(ROOT, 'docs/evaluation');
  fs.mkdirSync(outDir, { recursive: true });
  const file = path.join(outDir, `load-test-${new Date().toISOString().slice(0, 10)}.md`);
  fs.writeFileSync(file, md, 'utf8');
  process.stdout.write(md);
  process.stdout.write(`wrote ${file}\n`);
  server.close();
  await db.close();
}

await main();
