import env from '../config/env.js';
import logger from '../utils/logger.js';
import { expireUnanswered } from './fallService.js';
import locationService from './locationService.js';

const log = logger.child({ module: 'fall-watchdog' });

let timer = null;
let nowFn = () => new Date();

export function setClock(fn) {
  nowFn = fn;
}

export async function processOnce() {
  const falls = await expireUnanswered(nowFn());
  const gpsAlerts = await locationService.checkGpsLostAlerts(nowFn().getTime());
  return { falls, gpsAlerts };
}

export function start() {
  if (env.isTest || timer) return;
  timer = setInterval(() => {
    processOnce().catch((error) => {
      log.error('watchdog سقوط شکست خورد', { error: error.message });
    });
  }, 15_000);
  timer.unref?.();
}

export function stop() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

export default { start, stop, processOnce, setClock };
