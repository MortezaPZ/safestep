import db from '../db/index.js';

// Fixed projections intentionally omit names, coordinates and sensor features.
const queries = {
  location_reference_samples: `SELECT id, user_id, environment, reference_label, error_m, accuracy_m, valid, sampled_at
    FROM location_reference_samples ORDER BY sampled_at, id`,
  sus_responses: `SELECT id, user_id, role,
      answers->>0 AS q1, answers->>1 AS q2, answers->>2 AS q3, answers->>3 AS q4, answers->>4 AS q5,
      answers->>5 AS q6, answers->>6 AS q7, answers->>7 AS q8, answers->>8 AS q9, answers->>9 AS q10,
      score, created_at FROM (
        SELECT DISTINCT ON (user_id) * FROM sus_responses ORDER BY user_id, created_at DESC, id DESC
      ) latest ORDER BY user_id`,
  alert_deliveries: `SELECT d.id, d.alert_id, d.recipient_user_id, a.type AS alert_type,
      d.channel, d.status, d.latency_ms, d.created_at,
      r.received_at AS device_receipt_recorded_at,
      CASE WHEN r.received_at IS NOT NULL THEN
        ROUND(EXTRACT(EPOCH FROM (r.received_at - a.created_at)) * 1000)::bigint
      END AS alert_to_server_receipt_ms
    FROM alert_deliveries d JOIN alerts a ON a.id = d.alert_id
    LEFT JOIN fcm_device_receipts r ON r.alert_id = d.alert_id
      AND r.recipient_user_id = d.recipient_user_id AND d.channel = 'fcm'
    ORDER BY d.created_at, d.id`,
  fall_events: `SELECT id, user_id, classified_as_fall, user_feedback, detection_source,
      detected_at, feedback_at, created_at FROM fall_events ORDER BY detected_at, id`,
  location_telemetry: `SELECT id, user_id, e2e_latency_ms, process_ms, accuracy_m, source,
      is_queued_replay, recorded_at, received_at FROM location_telemetry
      WHERE source = 'device' ORDER BY recorded_at, id`,
};

export const evaluationExportNames = Object.keys(queries);
export const evaluationExportColumns = {
  location_reference_samples: ['id', 'user_id', 'environment', 'reference_label', 'error_m', 'accuracy_m', 'valid', 'sampled_at'],
  sus_responses: ['id', 'user_id', 'role', 'q1', 'q2', 'q3', 'q4', 'q5', 'q6', 'q7', 'q8', 'q9', 'q10', 'score', 'created_at'],
  alert_deliveries: ['id', 'alert_id', 'recipient_user_id', 'alert_type', 'channel', 'status', 'latency_ms', 'created_at', 'device_receipt_recorded_at', 'alert_to_server_receipt_ms'],
  fall_events: ['id', 'user_id', 'classified_as_fall', 'user_feedback', 'detection_source', 'detected_at', 'feedback_at', 'created_at'],
  location_telemetry: ['id', 'user_id', 'e2e_latency_ms', 'process_ms', 'accuracy_m', 'source', 'is_queued_replay', 'recorded_at', 'received_at'],
};
export async function evaluationExportRows(name) {
  if (!Object.hasOwn(queries, name)) throw new Error('Invalid evaluation export');
  const { rows } = await db.query(queries[name]);
  return rows;
}
