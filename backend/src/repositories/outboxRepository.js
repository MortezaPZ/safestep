/**
 * صف ماندگار نوتیفیکیشن — انتخاب ردیف‌های قابل ارسال و به‌روزرسانی وضعیت.
 */
import env from '../config/env.js';
import db from '../db/index.js';

function mapRow(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    userId: row.user_id,
    alertId: row.alert_id,
    channel: row.channel,
    payload: row.payload ?? {},
    status: row.status,
    attempts: Number(row.attempts ?? 0),
    lastError: row.last_error,
    nextAttemptAt: row.next_attempt_at ? new Date(row.next_attempt_at).toISOString() : null,
    sentAt: row.sent_at ? new Date(row.sent_at).toISOString() : null,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
  };
}

export async function insert({ userId, alertId, channel = 'fcm', payload }) {
  const { rows } = await db.query(
    `INSERT INTO notification_outbox (user_id, alert_id, channel, payload, status, next_attempt_at)
     VALUES ($1, $2, $3, $4::jsonb, 'pending', now())
     RETURNING *`,
    [userId, alertId ?? null, channel, JSON.stringify(payload ?? {})],
  );
  return mapRow(rows[0]);
}

export async function claimPending(limit = 50) {
  const capped = Math.min(Math.max(Number(limit) || 50, 1), 200);
  const locking = env.db.driver === 'pg' ? 'FOR UPDATE SKIP LOCKED' : '';
  const { rows } = await db.query(
    `SELECT * FROM notification_outbox
      WHERE status = 'pending' AND next_attempt_at <= now()
      ORDER BY next_attempt_at ASC
      LIMIT $1
      ${locking}`,
    [capped],
  );
  return rows.map(mapRow);
}

export async function markSent(id) {
  await db.query(
    `UPDATE notification_outbox
        SET status = 'sent', sent_at = now(), last_error = NULL
      WHERE id = $1`,
    [id],
  );
}

export async function markFailure(id, { attempts, lastError, abandon }) {
  const delaySec = 30 * 2 ** Math.max(attempts - 1, 0);
  const nextAt = new Date(Date.now() + delaySec * 1000).toISOString();
  await db.query(
    `UPDATE notification_outbox
        SET status = $2,
            attempts = $3,
            last_error = $4,
            next_attempt_at = $5::timestamptz
      WHERE id = $1`,
    [id, abandon ? 'abandoned' : 'pending', attempts, lastError ?? null, nextAt],
  );
}

export async function retry(id) {
  const { rows } = await db.query(
    `UPDATE notification_outbox
        SET status = 'pending', next_attempt_at = now(), last_error = NULL
      WHERE id = $1
      RETURNING *`,
    [id],
  );
  return mapRow(rows[0]);
}

export async function list({ status = null, limit = 50, offset = 0 } = {}) {
  const capped = Math.min(Math.max(Number(limit) || 50, 1), 200);
  const off = Math.max(Number(offset) || 0, 0);
  const { rows } = await db.query(
    `SELECT * FROM notification_outbox
      WHERE ($1::text IS NULL OR status = $1)
      ORDER BY created_at DESC
      LIMIT $2 OFFSET $3`,
    [status || null, capped, off],
  );
  const { rows: countRows } = await db.query(
    `SELECT count(*)::int AS n FROM notification_outbox
      WHERE ($1::text IS NULL OR status = $1)`,
    [status || null],
  );
  return { items: rows.map(mapRow), total: countRows[0]?.n ?? 0 };
}

export async function getById(id) {
  const { rows } = await db.query('SELECT * FROM notification_outbox WHERE id = $1', [id]);
  return mapRow(rows[0]);
}

export default { insert, claimPending, markSent, markFailure, retry, list, getById };
