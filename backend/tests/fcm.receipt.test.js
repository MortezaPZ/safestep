import { beforeAll, afterAll, expect, it } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
let app;

beforeAll(async () => { await db.connect(); await runMigrations(); app = createApp(); });
afterAll(async () => { await db.close(); });

it('only a queued FCM recipient can record an idempotent server receipt', async () => {
  async function register(phone, role) {
    const res = await request(app).post('/api/v1/auth/register').send({
      phone, password: 'Test@1234', fullName: 'آزمون', role,
    });
    expect(res.status).toBe(201);
    return { id: res.body.user.id, token: res.body.accessToken };
  }
  const subject = await register('09151119981', 'primary');
  const recipient = await register('09151119982', 'guardian');
  const outsider = await register('09151119983', 'guardian');
  const { rows } = await db.query(
    `INSERT INTO alerts (user_id, type, title, body) VALUES ($1, 'sos', 'SOS', 'test') RETURNING id`,
    [subject.id],
  );
  const id = rows[0].id;
  await db.query(`INSERT INTO notification_outbox (user_id, alert_id, channel) VALUES ($1, $2, 'fcm')`, [recipient.id, id]);
  const url = `/api/v1/alerts/${id}/delivery-receipt`;
  expect((await request(app).post(url)).status).toBe(401);
  expect((await request(app).post(url).set('Authorization', `Bearer ${outsider.token}`)).status).toBe(404);
  const first = await request(app).post(url).set('Authorization', `Bearer ${recipient.token}`);
  const repeat = await request(app).post(url).set('Authorization', `Bearer ${recipient.token}`);
  expect(first.status).toBe(200);
  expect(repeat.body.receivedAt).toBe(first.body.receivedAt);
  const saved = await db.query('SELECT count(*)::int AS count FROM fcm_device_receipts');
  expect(saved.rows[0].count).toBe(1);
});
