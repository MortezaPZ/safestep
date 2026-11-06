import { setTimeout as delay } from 'node:timers/promises';

/** Stop accepting new work, wait for open connections, then allow tail work to settle. */
export async function closeLoadServer(server, settleMs = 1000) {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  await delay(settleMs);
}

export function roundedMetric(value) {
  return Number.isFinite(value) ? Number(value.toFixed(2)) : '—';
}
