/**
 * آداپتور نوتیفیکیشن: WebSocket برای اپ باز، FCM HTTP v1 برای اپ بسته.
 *
 * API قدیمی `fcm/send` با Server Key در ۲۰۲۴ از طرف گوگل بسته شد.
 * مسیر واقعی حالا `projects/{id}/messages:send` است و برای هر توکن یک
 * درخواست جدا می‌زند. اگر حساب سرویس نباشد، مسیر محلی (WebSocket + لاگ)
 * بدون شکست خوردن فعال می‌ماند.
 */
import fs from 'node:fs';
import { GoogleAuth } from 'google-auth-library';
import env from '../config/env.js';
import logger from '../utils/logger.js';
import hub from '../realtime/hub.js';
import * as deviceRepository from '../repositories/deviceRepository.js';

const log = logger.child({ module: 'notification' });

export const NOTIFICATION_EVENT = 'notification:push';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

function parseServiceAccount() {
  const raw = env.notification.fcmServiceAccountJson;
  const filePath = env.notification.fcmServiceAccountPath;
  let parsed = null;

  if (raw) {
    try {
      parsed = JSON.parse(raw);
    } catch {
      try {
        parsed = JSON.parse(Buffer.from(raw, 'base64').toString('utf8'));
      } catch {
        return null;
      }
    }
  } else if (filePath) {
    try {
      parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch {
      return null;
    }
  }

  if (!parsed?.client_email || !parsed?.private_key) return null;
  const projectId = env.notification.fcmProjectId || parsed.project_id;
  if (!projectId) return null;
  return { credentials: parsed, projectId };
}

/** آیا پیکربندی FCM کامل و قابل‌خواندن است؟ */
export function isFcmConfigured() {
  return Boolean(parseServiceAccount());
}

/**
 * مسیر تحویل فعال.
 * @returns {'fcm'|'local'}
 */
export function activeDriver() {
  const configured = env.notification.driver;
  if (configured === 'fcm') return 'fcm';
  if (configured === 'local') return 'local';
  return isFcmConfigured() ? 'fcm' : 'local';
}

function stringifyData(data, severity) {
  const out = {};
  for (const [key, value] of Object.entries({ ...(data ?? {}), severity })) {
    if (value === undefined || value === null) continue;
    out[key] = String(value);
  }
  return out;
}

function fcmMessageBody(token, { title, body, data, severity }) {
  const critical = severity === 'critical';
  return {
    message: {
      token,
      notification: { title, body },
      data: stringifyData(data, severity),
      android: {
        priority: critical ? 'HIGH' : 'NORMAL',
        notification: {
          channel_id: critical ? 'safestep_sos' : 'safestep_alerts',
          sound: critical ? 'sos_alert' : 'default',
        },
      },
      apns: {
        headers: { 'apns-priority': critical ? '10' : '5' },
        payload: {
          aps: {
            sound: critical ? 'sos_alert.caf' : 'default',
            'interruption-level': critical ? 'critical' : 'active',
          },
        },
      },
    },
  };
}

function isUnregisteredError(status, json) {
  const details = json?.error?.details ?? [];
  const statusName = json?.error?.status;
  if (status === 404 && (statusName === 'NOT_FOUND' || /UNREGISTERED/i.test(JSON.stringify(json ?? {})))) {
    return true;
  }
  if (status === 400 && statusName === 'INVALID_ARGUMENT') {
    return /registration.?token|not a valid fcm/i.test(JSON.stringify(json ?? {}));
  }
  return details.some((d) => d.errorCode === 'UNREGISTERED');
}

async function accessToken(credentials) {
  const auth = new GoogleAuth({
    credentials,
    scopes: [FCM_SCOPE],
  });
  const client = await auth.getClient();
  const result = await client.getAccessToken();
  const token = typeof result === 'string' ? result : result?.token;
  if (!token) throw new Error('توکن دسترسی FCM خالی بود');
  return token;
}

/**
 * ارسال یک پیام به یک توکن (قرارداد HTTP v1؛ بدون multicast).
 * @returns {Promise<{ok: boolean, invalidToken: boolean, status: number, error?: string}>}
 */
export async function sendFcmToToken(token, message) {
  const cfg = parseServiceAccount();
  if (!cfg) {
    return { ok: false, invalidToken: false, status: 0, error: 'FCM پیکربندی نشده' };
  }

  const bearer = await accessToken(cfg.credentials);
  const url = `https://fcm.googleapis.com/v1/projects/${cfg.projectId}/messages:send`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${bearer}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(fcmMessageBody(token, message)),
    signal: AbortSignal.timeout(10_000),
  });

  if (response.ok) {
    return { ok: true, invalidToken: false, status: response.status };
  }

  let json = null;
  try {
    json = await response.json();
  } catch {
    json = null;
  }

  const invalidToken = isUnregisteredError(response.status, json);
  return {
    ok: false,
    invalidToken,
    status: response.status,
    error: json?.error?.message ?? `FCM پاسخ ${response.status} داد`,
  };
}

export function emitInApp(userIds, { title, body, data, severity }, deliveredVia) {
  hub.emitToUsers(userIds, NOTIFICATION_EVENT, {
    title,
    body,
    data,
    severity,
    deliveredVia,
    at: new Date().toISOString(),
  });
}

function sendViaLocal(userIds, payload) {
  emitInApp(userIds, payload, 'local');
  log.info('نوتیفیکیشن از مسیر محلی تحویل شد', {
    recipients: userIds.length,
    title: payload.title,
    severity: payload.severity,
  });
  return { sent: userIds.length, failed: 0, invalidTokens: [] };
}

/**
 * ارسال هم‌زمان درون‌برنامه‌ای. مسیر FCM دیگر اینجا await نمی‌شود؛
 * صف outbox آن را جداگانه می‌فرستد.
 */
export async function notify(userIds, message) {
  const targets = [...new Set((userIds ?? []).filter(Boolean))];
  if (targets.length === 0) {
    return { driver: 'none', sent: 0, failed: 0, fellBack: false };
  }

  const driver = activeDriver();
  const payload = {
    title: message.title,
    body: message.body,
    data: message.data ?? {},
    severity: message.severity ?? 'info',
  };

  emitInApp(targets, payload, driver);

  if (driver === 'local') {
    log.info('نوتیفیکیشن ثبت شد', { recipients: targets.length, title: payload.title });
    return { driver: 'local', sent: targets.length, failed: 0, fellBack: false };
  }

  try {
    const devices = await deviceRepository.pushTokensFor(targets);
    const tokens = devices.map((d) => d.token).filter(Boolean);
    if (tokens.length === 0) {
      return { driver: 'local', sent: targets.length, failed: 0, fellBack: true };
    }

    let sent = 0;
    let failed = 0;
    const invalidTokens = [];
    for (const token of tokens) {
      const result = await sendFcmToToken(token, payload);
      if (result.ok) sent += 1;
      else {
        failed += 1;
        if (result.invalidToken) invalidTokens.push(token);
      }
    }

    for (const token of invalidTokens) {
      await deviceRepository.clearPushToken(token);
    }

    return { driver: 'fcm', sent, failed, fellBack: false };
  } catch (error) {
    log.error('ارسال FCM شکست خورد؛ بازگشت به مسیر محلی', { error: error.message });
    return { ...sendViaLocal(targets, payload), driver: 'local', fellBack: true };
  }
}

export function status() {
  const configured = isFcmConfigured();
  return {
    driver: activeDriver(),
    fcmConfigured: configured,
    note: configured
      ? 'ارسال واقعی FCM HTTP v1 فعال است'
      : 'حساب سرویس FCM تنظیم نشده؛ تحویل از مسیر درون‌برنامه‌ای و WebSocket انجام می‌شود',
  };
}

export default {
  notify,
  status,
  activeDriver,
  isFcmConfigured,
  sendFcmToToken,
  emitInApp,
  NOTIFICATION_EVENT,
};
