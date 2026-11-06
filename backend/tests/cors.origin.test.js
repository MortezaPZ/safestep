import { expect, it } from 'vitest';
import request from 'supertest';

process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'pglite';
process.env.PGLITE_DATA_DIR = 'memory';
process.env.CORS_ORIGINS = 'https://allowed.example';
const { createApp } = await import('../src/app.js');
const app = createApp();

async function preflight(origin, host = '10.0.0.5:4090', protocol) {
  let req = request(app).options('/api/v1/auth/login')
    .set('Host', host).set('Origin', origin).set('Access-Control-Request-Method', 'POST');
  if (protocol) req = req.set('X-Forwarded-Proto', protocol);
  return req;
}

it('permits same origin and configured origins but rejects other origins with 403', async () => {
  const same = await preflight('http://10.0.0.5:4090');
  expect(same.status).toBe(204);
  expect(same.headers['access-control-allow-origin']).toBe('http://10.0.0.5:4090');
  expect((await preflight('https://app.example', 'app.example', 'https')).status).toBe(204);
  expect((await preflight('https://allowed.example')).status).toBe(204);
  expect((await preflight('https://10.0.0.5:4090')).status).toBe(403);
  expect((await preflight('http://10.0.0.6:4090')).status).toBe(403);
  expect((await preflight('null')).status).toBe(403);
});
