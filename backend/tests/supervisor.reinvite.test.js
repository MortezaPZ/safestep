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

it('revoking and reinviting the former main supervisor keeps only the new main', async () => {
  async function register(phone, role) {
    const res = await request(app).post('/api/v1/auth/register').send({
      phone, password: 'Test@1234', fullName: 'آزمون', role,
    });
    expect(res.status).toBe(201);
    return { id: res.body.user.id, token: res.body.accessToken };
  }
  const primary = await register('09151119881', 'primary');
  const first = await register('09151119882', 'guardian');
  const second = await register('09151119883', 'guardian');
  const auth = (u) => ({ Authorization: `Bearer ${u.token}` });
  async function invite(guardian) {
    const invitation = await request(app).post('/api/v1/guardianships/invites').set(auth(primary))
      .send({ permissions: ['view_location', 'receive_alerts'] });
    expect(invitation.status).toBe(201);
    const redeemed = await request(app).post('/api/v1/guardianships/redeem').set(auth(guardian))
      .send({ code: invitation.body.code });
    expect(redeemed.status).toBe(201);
    return redeemed.body.guardianship.id;
  }
  const firstId = await invite(first);
  const secondId = await invite(second);
  expect((await request(app).patch(`/api/v1/guardianships/${firstId}/main-supervisor`).set(auth(primary)).send({})).status).toBe(200);
  expect((await request(app).delete(`/api/v1/guardianships/${firstId}`).set(auth(primary))).status).toBe(200);
  expect((await request(app).patch(`/api/v1/guardianships/${secondId}/main-supervisor`).set(auth(primary)).send({})).status).toBe(200);
  expect(await invite(first)).toBe(firstId);
  const { rows } = await db.query(`SELECT guardian_user_id, is_main_supervisor FROM guardianships
    WHERE primary_user_id = $1 AND status = 'active' ORDER BY guardian_user_id`, [primary.id]);
  expect(rows).toHaveLength(2);
  expect(rows.filter((row) => row.is_main_supervisor).map((row) => row.guardian_user_id)).toEqual([second.id]);
});
