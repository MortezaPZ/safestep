/**
 * درایور پیامک قابل تعویض: console | kavenegar | ghasedak
 */
import env from '../config/env.js';
import logger from '../utils/logger.js';

const log = logger.child({ module: 'sms' });

let lastDispatch = null;

function maskPhone(phone) {
  const d = String(phone).replace(/\D/g, '');
  if (d.length < 8) return '****';
  return `${d.slice(0, 4)}***${d.slice(-4)}`;
}

export function status() {
  return {
    driver: env.sms.driver,
    hasApiKey: Boolean(env.sms.apiKey),
    template: env.sms.template || null,
  };
}

export function consumeLastDispatch() {
  const value = lastDispatch;
  lastDispatch = null;
  return value;
}

async function sendKavenegar({ phone, code }) {
  const key = encodeURIComponent(env.sms.apiKey);
  const url = `https://api.kavenegar.com/v1/${key}/verify/lookup.json?receptor=${encodeURIComponent(phone)}&token=${encodeURIComponent(code)}&template=${encodeURIComponent(env.sms.template)}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`kavenegar HTTP ${res.status}`);
}

async function sendGhasedak({ phone, code }) {
  const res = await fetch('https://api.ghasedak.me/v2/verification/send/simple', {
    method: 'POST',
    headers: {
      apikey: env.sms.apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      receptor: phone,
      type: '1',
      template: env.sms.template,
      param1: code,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`ghasedak HTTP ${res.status}`);
}

export async function send({ phone, code, purpose }) {
  lastDispatch = { phone, code, purpose, at: new Date().toISOString() };
  const masked = maskPhone(phone);

  if (env.sms.driver === 'kavenegar') {
    await sendKavenegar({ phone, code });
    log.info('پیامک کاوه‌نگار ارسال شد', { phone: masked, purpose });
    return { driver: 'kavenegar' };
  }
  if (env.sms.driver === 'ghasedak') {
    await sendGhasedak({ phone, code });
    log.info('پیامک قاصدک ارسال شد', { phone: masked, purpose });
    return { driver: 'ghasedak' };
  }

  log.info('کد تأیید (حالت توسعه / console)', { phone: masked, code, purpose });
  return { driver: 'console' };
}

export default { send, status, consumeLastDispatch };
