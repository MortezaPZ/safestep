import db from '../db/index.js';

const n = (v) => (v === null || v === undefined ? null : Number(v));
const d = (v) => (v ? new Date(v).toISOString() : null);

export function mapFallEvent(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    alertId: row.alert_id,
    detectedAt: d(row.detected_at),
    modelName: row.model_name,
    modelVersion: row.model_version,
    confidence: n(row.confidence),
    features: row.features,
    lat: n(row.lat),
    lng: n(row.lng),
    userFeedback: row.user_feedback,
    detectionSource: row.detection_source,
    svmMargin: n(row.svm_margin),
    knnAgree: n(row.knn_agree),
    feedbackAt: d(row.feedback_at),
    respondedWithinSec: row.responded_within_sec,
    classifiedAsFall: Boolean(row.classified_as_fall),
    clientEventId: row.client_event_id,
    createdAt: d(row.created_at),
  };
}

export async function insert(event) {
  const { rows } = await db.query(
    `INSERT INTO fall_events (
       user_id, alert_id, detected_at, model_name, model_version, confidence,
       features, lat, lng, user_feedback, detection_source, svm_margin, knn_agree,
       classified_as_fall, client_event_id, feedback_at, responded_within_sec
     ) VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
     RETURNING *`,
    [
      event.userId,
      event.alertId ?? null,
      event.detectedAt,
      event.modelName ?? null,
      event.modelVersion ?? null,
      event.confidence ?? null,
      JSON.stringify(event.features ?? []),
      event.lat ?? null,
      event.lng ?? null,
      event.userFeedback ?? null,
      event.detectionSource ?? 'device',
      event.svmMargin ?? null,
      event.knnAgree ?? null,
      event.classifiedAsFall === true,
      event.clientEventId ?? null,
      event.feedbackAt ?? null,
      event.respondedWithinSec ?? null,
    ],
  );
  return mapFallEvent(rows[0]);
}

export async function findByClientEvent(userId, clientEventId) {
  const { rows } = await db.query(
    'SELECT * FROM fall_events WHERE user_id = $1 AND client_event_id = $2',
    [userId, clientEventId],
  );
  return mapFallEvent(rows[0]);
}

export async function findById(id) {
  const { rows } = await db.query('SELECT * FROM fall_events WHERE id = $1', [id]);
  return mapFallEvent(rows[0]);
}

export async function listForUsers(userIds, { limit = 50, before } = {}) {
  const { rows } = await db.query(
    `SELECT * FROM fall_events
     WHERE user_id = ANY($1::uuid[])
       AND ($2::timestamptz IS NULL OR detected_at < $2)
     ORDER BY detected_at DESC
     LIMIT $3`,
    [userIds, before ?? null, limit],
  );
  return rows.map(mapFallEvent);
}

export async function listRecentForAdmin(limit = 50) {
  const { rows } = await db.query(
    `SELECT f.id, f.detected_at, f.confidence, f.classified_as_fall, f.detection_source,
            f.user_feedback, u.full_name
       FROM fall_events f JOIN users u ON u.id = f.user_id
      ORDER BY f.detected_at DESC
      LIMIT $1`,
    [limit],
  );
  return rows.map((row) => ({
    id: row.id,
    detectedAt: row.detected_at,
    confidence: row.confidence,
    classifiedAsFall: row.classified_as_fall,
    source: row.detection_source,
    feedback: row.user_feedback,
    subjectName: row.full_name,
    title: row.classified_as_fall ? 'فراخوان اضطراری' : 'گزارش سقوط',
  }));
}

export async function applyFeedback(id, { feedback, respondedWithinSec }) {
  const { rows } = await db.query(
    `UPDATE fall_events SET
       user_feedback = $2,
       responded_within_sec = COALESCE($3, responded_within_sec),
       feedback_at = now()
     WHERE id = $1 AND user_feedback IS NULL
     RETURNING *`,
    [id, feedback, respondedWithinSec ?? null],
  );
  return mapFallEvent(rows[0]);
}

export async function linkAlert(id, alertId) {
  const { rows } = await db.query(
    'UPDATE fall_events SET alert_id = $2 WHERE id = $1 RETURNING *',
    [id, alertId],
  );
  return mapFallEvent(rows[0]);
}

export async function listExpiredPositives(nowIso) {
  const { rows } = await db.query(
    `SELECT f.*, s.fall_countdown_sec
     FROM fall_events f
     JOIN user_settings s ON s.user_id = f.user_id
     WHERE f.classified_as_fall = TRUE
       AND f.user_feedback IS NULL
       AND f.alert_id IS NULL
       AND f.detected_at + ((s.fall_countdown_sec + 60) * INTERVAL '1 second') < $1::timestamptz`,
    [nowIso],
  );
  return rows.map(mapFallEvent);
}

export async function metrics() {
  const { rows } = await db.query(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE classified_as_fall)::int AS positives,
      COUNT(*) FILTER (WHERE user_feedback = 'confirmed')::int AS confirmed,
      COUNT(*) FILTER (WHERE user_feedback = 'false_alarm')::int AS false_alarm,
      COUNT(*) FILTER (WHERE user_feedback = 'no_response')::int AS no_response,
      COUNT(*) FILTER (WHERE user_feedback IS NULL)::int AS pending,
      COUNT(*) FILTER (WHERE classified_as_fall AND user_feedback IN ('confirmed','no_response'))::int AS tp,
      COUNT(*) FILTER (WHERE classified_as_fall AND user_feedback = 'false_alarm')::int AS fp,
      COUNT(*) FILTER (WHERE NOT classified_as_fall AND detection_source = 'manual' AND user_feedback = 'confirmed')::int AS fn,
      COUNT(*) FILTER (WHERE NOT classified_as_fall AND detection_source <> 'manual' AND (user_feedback IS NULL OR user_feedback <> 'confirmed'))::int AS tn
    FROM fall_events
  `);
  const med = await db.query(
    'SELECT responded_within_sec AS v FROM fall_events WHERE responded_within_sec IS NOT NULL ORDER BY v',
  );
  const vals = med.rows.map((x) => Number(x.v)).sort((a, b) => a - b);
  let medianResponseSec = null;
  if (vals.length) {
    const mid = Math.floor(vals.length / 2);
    medianResponseSec = vals.length % 2 ? vals[mid] : (vals[mid - 1] + vals[mid]) / 2;
  }
  const r = rows[0] ?? {};
  const tp = Number(r.tp ?? 0);
  const fp = Number(r.fp ?? 0);
  const fn = Number(r.fn ?? 0);
  const tn = Number(r.tn ?? 0);
  const precision = tp + fp === 0 ? 0 : tp / (tp + fp);
  const recall = tp + fn === 0 ? 0 : tp / (tp + fn);
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall);
  const falseAlarmRate = tp + fp === 0 ? 0 : fp / (tp + fp);
  return {
    total: Number(r.total ?? 0),
    positives: Number(r.positives ?? 0),
    feedback: {
      confirmed: Number(r.confirmed ?? 0),
      false_alarm: Number(r.false_alarm ?? 0),
      no_response: Number(r.no_response ?? 0),
      pending: Number(r.pending ?? 0),
    },
    confusion: { tp, fp, tn, fn },
    precision,
    recall,
    f1,
    falseAlarmRate,
    medianResponseSec,
  };
}
