/**
 * صف ارسال FCM: enqueue در مسیر هشدار، پردازش ناهمگام در worker.
 *
 * هشدار روی WebSocket همان لحظه می‌رود؛ FCM نباید همان درخواست HTTP را
 * معطل کند. اگر FCM قطع باشد، ردیف pending می‌ماند و با backoff دوباره
 * تلاش می‌شود.
 */
import env from '../config/env.js';
import logger from '../utils/logger.js';
import { notFound } from '../utils/errors.js';
import * as outboxRepository from '../repositories/outboxRepository.js';
import * as deviceRepository from '../repositories/deviceRepository.js';
import * as alertRepository from '../repositories/alertRepository.js';
import telemetryService from './telemetryService.js';
import { sendFcmToToken, activeDriver } from './notificationAdapter.js';

const log = logger.child({ module: 'outbox' });
const MAX_ATTEMPTS = 5;

let timer = null;

export async function enqueue({ userId, alertId, channel = 'fcm', payload }) {
  return outboxRepository.insert({ userId, alertId, channel, payload });
}

export async function enqueueForRecipients(recipientIds, { alertId, title, body, data, severity }) {
  if (activeDriver() === 'local') return [];
  const rows = [];
  for (const userId of recipientIds) {
    rows.push(
      await enqueue({
        userId,
        alertId,
        channel: 'fcm',
        payload: { title, body, data: data ?? {}, severity: severity ?? 'info' },
      }),
    );
  }
  return rows;
}

async function recordFcmDelivery(row, { status, errorCode }) {
  if (!row.alertId) return;
  let createdAt = row.createdAt;
  try {
      const alert = await alertRepository.findById(row.alertId);
    if (alert?.createdAt) createdAt = alert.createdAt;
  } catch {
    // سنجه‌ی تأخیر بدون created_at هشدار هم قابل‌محاسبه است
  }
  const latencyMs = Math.max(0, Math.round(Date.now() - new Date(createdAt).getTime()));
  telemetryService.recordDelivery({
    alertId: row.alertId,
    recipientUserId: row.userId,
    channel: 'fcm',
    status,
    latencyMs,
    errorCode: errorCode ?? null,
  });
}

export async function processOnce() {
  const batch = await outboxRepository.claimPending(50);
  let sent = 0;
  let failed = 0;

  for (const row of batch) {
    const devices = await deviceRepository.pushTokensFor([row.userId]);
    const tokens = devices.map((d) => d.token).filter(Boolean);
    const payload = row.payload ?? {};

    if (tokens.length === 0) {
      const attempts = row.attempts + 1;
      await outboxRepository.markFailure(row.id, {
        attempts,
        lastError: 'هیچ توکن Push ثبت نشده',
        abandon: attempts >= MAX_ATTEMPTS,
      });
      failed += 1;
      continue;
    }

    let allOk = true;
    let lastError = null;
    for (const token of tokens) {
      const result = await sendFcmToToken(token, {
        title: payload.title,
        body: payload.body,
        data: payload.data,
        severity: payload.severity,
      });
      if (result.invalidToken) {
        await deviceRepository.clearPushToken(token);
      }
      if (!result.ok) {
        allOk = false;
        lastError = result.error ?? `HTTP ${result.status}`;
      }
    }

    if (allOk) {
      await outboxRepository.markSent(row.id);
      await recordFcmDelivery(row, { status: 'sent' });
      sent += 1;
    } else {
      const attempts = row.attempts + 1;
      const abandon = attempts >= MAX_ATTEMPTS;
      await outboxRepository.markFailure(row.id, {
        attempts,
        lastError,
        abandon,
      });
      await recordFcmDelivery(row, {
        status: abandon ? 'failed' : 'failed',
        errorCode: lastError,
      });
      failed += 1;
    }
  }

  if (batch.length > 0) {
    log.info('دور صف نوتیفیکیشن', { claimed: batch.length, sent, failed });
  }
  return { claimed: batch.length, sent, failed };
}

export function start() {
  if (env.isTest || timer) return;
  timer = setInterval(() => {
    processOnce().catch((error) => {
      log.error('پردازش صف نوتیفیکیشن شکست خورد', { error: error.message });
    });
  }, 2000);
  timer.unref?.();
}

export function stop() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

export async function listOutbox(filters) {
  return outboxRepository.list(filters);
}

export async function retryOutbox(id) {
  const row = await outboxRepository.retry(id);
  if (!row) throw notFound('ردیف صف یافت نشد.');
  return row;
}

export default { enqueue, enqueueForRecipients, processOnce, start, stop, listOutbox, retryOutbox };
