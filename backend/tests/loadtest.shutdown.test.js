import { expect, it } from 'vitest';
import http from 'node:http';
import { closeLoadServer, roundedMetric } from '../scripts/loadtest-helpers.js';

it('waits for an in-flight response before completing shutdown', async () => {
  let markStarted;
  const started = new Promise((resolve) => { markStarted = resolve; });
  let finished = false;
  const server = http.createServer((_req, res) => {
    markStarted();
    setTimeout(() => { finished = true; res.end('ok'); }, 100);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const response = fetch(`http://127.0.0.1:${server.address().port}/`);
  await started;
  await closeLoadServer(server, 0);
  expect(finished).toBe(true);
  expect(await (await response).text()).toBe('ok');
  expect(roundedMetric(12.345)).toBe(12.35);
  expect(roundedMetric(null)).toBe('—');
});
