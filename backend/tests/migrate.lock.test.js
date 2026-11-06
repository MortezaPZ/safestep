import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, expect, it } from 'vitest';

process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'pglite';
process.env.PGLITE_DATA_DIR = 'memory';

const { runMigrations, withPostgresAdvisoryLock } = await import('../src/db/migrate.js');
const { default: db } = await import('../src/db/index.js');

afterAll(async () => {
  await db.close();
});

it('serializes concurrent PGlite migration calls in-process', async () => {
  const results = await Promise.all([runMigrations(), runMigrations()]);

  expect(results).toHaveLength(2);
  expect(results[0].length + results[1].length).toBeGreaterThan(0);
  expect(results[0].length === 0 || results[1].length === 0).toBe(true);
});

it('unlocks and closes the dedicated PostgreSQL session after migration failure', async () => {
  const calls = [];
  const client = {
    async connect() {
      calls.push('connect');
    },
    async query(sql) {
      calls.push(sql.includes('pg_advisory_unlock') ? 'unlock' : 'lock');
      return { rows: [] };
    },
    async end() {
      calls.push('end');
    },
  };
  const failure = new Error('simulated migration failure');

  await expect(
    withPostgresAdvisoryLock(async () => {
      calls.push('work');
      throw failure;
    }, async () => client),
  ).rejects.toBe(failure);

  expect(calls).toEqual(['connect', 'lock', 'work', 'unlock', 'end']);
});

const postgresUrl = process.env.TEST_POSTGRES_URL;
const postgresIntegration = postgresUrl ? it : it.skip;

postgresIntegration(
  'serializes two independent processes running migrations on isolated PostgreSQL',
  async () => {
    const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
    const script = `
      const [{ runMigrations }, { default: db }] = await Promise.all([
        import('./src/db/migrate.js'), import('./src/db/index.js')
      ]);
      process.stdout.write('READY\\n');
      await new Promise((resolve) => process.stdin.once('data', resolve));
      try {
        const applied = await runMigrations();
        process.stdout.write('DONE:' + applied.length + '\\n');
      } catch (error) {
        process.stderr.write(error.stack || error.message);
        process.exitCode = 1;
      } finally {
        await db.close().catch(() => {});
      }
    `;

    function startProcess() {
      const child = spawn(process.execPath, ['--input-type=module', '-e', script], {
        cwd: backendRoot,
        env: {
          ...process.env,
          NODE_ENV: 'test',
          DB_DRIVER: 'pg',
          DATABASE_URL: postgresUrl,
          PGLITE_DATA_DIR: 'memory',
        },
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      let stdout = '';
      let stderr = '';
      let ready = false;
      let resolveReady;
      let rejectReady;
      const readyPromise = new Promise((resolve, reject) => {
        resolveReady = resolve;
        rejectReady = reject;
      });
      const closed = new Promise((resolve) => {
        child.once('close', (code) => resolve({ code, stdout, stderr }));
      });

      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', (chunk) => {
        stdout += chunk;
        if (!ready && stdout.includes('READY')) {
          ready = true;
          resolveReady();
        }
      });
      child.stderr.on('data', (chunk) => {
        stderr += chunk;
      });
      child.once('error', (error) => rejectReady(error));
      child.once('close', (code) => {
        if (!ready) rejectReady(new Error(`migration process exited early: ${code}; ${stderr}`));
      });

      return { child, readyPromise, closed };
    }

    const children = [startProcess(), startProcess()];
    await Promise.all(children.map((entry) => entry.readyPromise));
    for (const entry of children) entry.child.stdin.end('go\n');
    const results = await Promise.all(children.map((entry) => entry.closed));

    expect(
      results.map((result) => result.code),
      results.map((result) => result.stderr).join('\n'),
    ).toEqual([0, 0]);
    expect(results.every((result) => result.stdout.includes('DONE:'))).toBe(true);
  },
  60_000,
);
