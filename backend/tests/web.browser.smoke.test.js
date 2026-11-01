import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.DEMO_MODE = 'false';

const { createApp } = await import('../src/app.js');
const { default: env } = await import('../src/config/env.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { invalidateAccountState } = await import('../src/middleware/auth.js');

const chromeCandidates = [
  process.env.CHROME_BIN,
  process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  '/usr/bin/chromium',
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].filter(Boolean);
const browserExecutable = chromeCandidates.find((candidate) => existsSync(candidate));
const canRunBrowserSmoke = Boolean(browserExecutable && globalThis.WebSocket);

let app;
let server;
let origin;

async function cdpClient(url) {
  const socket = new WebSocket(url);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let nextId = 1;
  const pending = new Map();
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(String(data));
    if (!message.id) return;
    const callbacks = pending.get(message.id);
    if (!callbacks) return;
    pending.delete(message.id);
    if (message.error) callbacks.reject(new Error(message.error.message));
    else callbacks.resolve(message.result ?? {});
  });

  return {
    send(method, params = {}, sessionId) {
      const id = nextId++;
      const result = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
      socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
      return result;
    },
    close() {
      socket.close();
    },
  };
}

async function evaluate(cdp, sessionId, expression) {
  const response = await cdp.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  }, sessionId);
  if (response.exceptionDetails) {
    throw new Error(response.exceptionDetails.text ?? 'Browser evaluation failed');
  }
  return response.result?.value;
}

describe('وب‌اپ در مرورگر واقعی', () => {
  beforeAll(async () => {
    await db.connect();
    await runMigrations();
    app = createApp();
    server = http.createServer(app);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    origin = `http://127.0.0.1:${server.address().port}`;
    // The browser uses a random local port; allow this test server's own origin.
    env.corsOrigins.push(origin);
  });

  afterAll(async () => {
    if (server?.listening) await new Promise((resolve) => server.close(resolve));
    await db.close();
  });

  it.skipIf(!canRunBrowserSmoke)(
    'ورود معتبر به داشبورد اصلی را در Chromium رندر می‌کند',
    async () => {
      const phone = `0912${String(Date.now()).slice(-7)}`;
      const password = 'Browser@1234';
      const registered = await request(app)
        .post('/api/v1/auth/register')
        .send({ phone, password, fullName: 'کاربر آزمون مرورگر', role: 'primary' });
      expect(registered.status).toBe(201);
      await db.query("UPDATE users SET verification_status = 'verified' WHERE id = $1", [
        registered.body.user.id,
      ]);
      invalidateAccountState(registered.body.user.id);

      const profile = await mkdtemp(path.join(os.tmpdir(), 'safestep-chrome-'));
      const browser = spawn(browserExecutable, [
        '--headless=new',
        '--disable-gpu',
        '--no-first-run',
        '--no-default-browser-check',
        '--remote-debugging-port=0',
        `--user-data-dir=${profile}`,
        'about:blank',
      ], { stdio: 'ignore' });
      let cdp;

      try {
        let debugPort;
        for (let attempt = 0; attempt < 100; attempt += 1) {
          const activePort = await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')
            .catch(() => null);
          if (activePort) {
            debugPort = activePort.split(/\r?\n/)[0];
            break;
          }
          if (browser.exitCode !== null) throw new Error('Chromium exited before starting.');
          await delay(100);
        }
        if (!debugPort) throw new Error('Chromium did not expose its local DevTools port.');

        const version = await fetch(`http://127.0.0.1:${debugPort}/json/version`).then((r) => r.json());
        cdp = await cdpClient(version.webSocketDebuggerUrl);
        const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
        const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
        await cdp.send('Page.enable', {}, sessionId);
        await cdp.send('Page.navigate', { url: origin }, sessionId);

        let authReady = false;
        for (let attempt = 0; attempt < 100; attempt += 1) {
          authReady = await evaluate(
            cdp,
            sessionId,
            "Boolean(document.querySelector('#auth-phone') && document.querySelector('#auth-password'))",
          ).catch(() => false);
          if (authReady) break;
          await delay(100);
        }
        expect(authReady).toBe(true);
        await evaluate(cdp, sessionId, `(() => {
          document.querySelector('#auth-phone').value = ${JSON.stringify(phone)};
          document.querySelector('#auth-password').value = ${JSON.stringify(password)};
          document.querySelector('form').requestSubmit();
          return true;
        })()`);

        let pageState = null;
        for (let attempt = 0; attempt < 150; attempt += 1) {
          const encoded = await evaluate(cdp, sessionId, `JSON.stringify({
            main: Boolean(document.querySelector('main#main.app-main')),
            viewText: document.querySelector('#view')?.innerText ?? '',
            pageText: document.body?.innerText ?? ''
          })`).catch(() => null);
          if (encoded) {
            pageState = JSON.parse(encoded);
            if (pageState.main && pageState.viewText.trim()) break;
          }
          await delay(100);
        }

        expect(pageState?.main, pageState?.pageText).toBe(true);
        expect(pageState?.viewText.trim().length, pageState?.pageText).toBeGreaterThan(0);
      } finally {
        cdp?.close();
        if (browser.exitCode === null) {
          browser.kill();
          await Promise.race([
            new Promise((resolve) => browser.once('exit', resolve)),
            delay(2000),
          ]);
        }
        await rm(profile, { recursive: true, force: true });
      }
    },
    35000,
  );
});
