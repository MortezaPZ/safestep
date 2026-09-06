/**
 * مخزن محدوده‌های امن و وضعیت کاربر نسبت به آن‌ها.
 */
import db from '../db/index.js';
import { mapSafeZone, mapZoneState } from './mappers.js';

/* ───────────────────────── محدوده‌های امن ───────────────────────── */

export async function listByUser(userId, { onlyActive = false } = {}) {
  const { rows } = await db.query(
    `SELECT * FROM safe_zones
     WHERE user_id = $1 AND ($2::boolean = FALSE OR is_active = TRUE)
     ORDER BY created_at ASC`,
    [userId, onlyActive],
  );
  return rows.map(mapSafeZone);
}

export async function findById(id) {
  const { rows } = await db.query('SELECT * FROM safe_zones WHERE id = $1', [id]);
  return mapSafeZone(rows[0]);
}

export async function create({
  userId, name, centerLat, centerLng, radiusM, color, icon,
  shape = 'circle', polygon = null, schedule = null,
  alertOnEnter = true, alertOnExit = true, dwellAlertMinutes = null,
}) {
  const { rows } = await db.query(
    `INSERT INTO safe_zones (
       user_id, name, center_lat, center_lng, radius_m, color, icon,
       shape, polygon, schedule, alert_on_enter, alert_on_exit, dwell_alert_minutes
     )
     VALUES ($1, $2, $3, $4, $5, COALESCE($6, '#2F6FED'), COALESCE($7, 'home'),
             $8, $9::jsonb, $10::jsonb, $11, $12, $13)
     RETURNING *`,
    [
      userId, name, centerLat, centerLng, radiusM, color ?? null, icon ?? null,
      shape, polygon ? JSON.stringify(polygon) : null,
      schedule ? JSON.stringify(schedule) : null,
      alertOnEnter !== false, alertOnExit !== false, dwellAlertMinutes ?? null,
    ],
  );
  return mapSafeZone(rows[0]);
}

/** به‌روزرسانی جزئی. شرط user_id مالکیت را در همان کوئری تضمین می‌کند. */
export async function update(id, userId, patch) {
  const { rows } = await db.query(
    `UPDATE safe_zones SET
       name       = COALESCE($3, name),
       center_lat = COALESCE($4, center_lat),
       center_lng = COALESCE($5, center_lng),
       radius_m   = COALESCE($6, radius_m),
       is_active  = COALESCE($7, is_active),
       color      = COALESCE($8, color),
       icon       = COALESCE($9, icon),
       shape      = COALESCE($10, shape),
       polygon    = COALESCE($11::jsonb, polygon),
       schedule   = COALESCE($12::jsonb, schedule),
       alert_on_enter = COALESCE($13, alert_on_enter),
       alert_on_exit  = COALESCE($14, alert_on_exit),
       dwell_alert_minutes = COALESCE($15, dwell_alert_minutes),
       updated_at = now()
     WHERE id = $1 AND user_id = $2
     RETURNING *`,
    [
      id,
      userId,
      patch.name ?? null,
      patch.centerLat ?? null,
      patch.centerLng ?? null,
      patch.radiusM ?? null,
      patch.isActive ?? null,
      patch.color ?? null,
      patch.icon ?? null,
      patch.shape ?? null,
      patch.polygon ? JSON.stringify(patch.polygon) : null,
      patch.schedule !== undefined
        ? (patch.schedule === null ? null : JSON.stringify(patch.schedule))
        : null,
      patch.alertOnEnter ?? null,
      patch.alertOnExit ?? null,
      patch.dwellAlertMinutes === undefined ? null : patch.dwellAlertMinutes,
    ],
  );
  return mapSafeZone(rows[0]);
}

export async function remove(id, userId) {
  const { rowCount } = await db.query(
    'DELETE FROM safe_zones WHERE id = $1 AND user_id = $2',
    [id, userId],
  );
  return rowCount > 0;
}

export async function countByUser(userId) {
  const { rows } = await db.query(
    'SELECT COUNT(*)::int AS count FROM safe_zones WHERE user_id = $1',
    [userId],
  );
  return rows[0]?.count ?? 0;
}

/* ─────────────────── وضعیت محدوده (ماشین حالتِ هیسترزیس) ─────────────────── */

export async function getZoneState(userId, zoneId) {
  const { rows } = await db.query(
    'SELECT * FROM zone_states WHERE user_id = $1 AND zone_id = $2',
    [userId, zoneId],
  );
  return mapZoneState(rows[0]);
}

/** وضعیت کاربر نسبت به تمام محدوده‌های فعالش — با یک کوئری، برای موتور Geofence. */
export async function listStatesForUser(userId) {
  const { rows } = await db.query(
    `SELECT z.id AS zone_id, z.user_id, z.name AS zone_name, z.radius_m, z.is_active,
            z.shape, z.polygon, z.schedule, z.alert_on_enter, z.alert_on_exit, z.dwell_alert_minutes,
            s.state, s.consecutive_count, s.pending_state, s.last_distance_m,
            s.last_transition_at, s.last_alert_at, s.last_evaluated_at, s.last_dwell_alert_at
     FROM safe_zones z
     LEFT JOIN zone_states s ON s.zone_id = z.id AND s.user_id = z.user_id
     WHERE z.user_id = $1 AND z.is_active = TRUE`,
    [userId],
  );
  return rows.map(mapZoneState);
}

/** ثبت وضعیت جدید. رکورد اگر نبود ساخته می‌شود (اولین ارزیابی هر محدوده). */
export async function upsertZoneState({
  userId,
  zoneId,
  state,
  consecutiveCount,
  pendingState,
  lastDistanceM,
  transitioned,
  alerted,
  dwellAlerted = false,
}) {
  const { rows } = await db.query(
    `INSERT INTO zone_states
       (user_id, zone_id, state, consecutive_count, pending_state, last_distance_m,
        last_transition_at, last_alert_at, last_evaluated_at, last_dwell_alert_at)
     VALUES ($1, $2, $3, $4, $5, $6,
             CASE WHEN $7::boolean THEN now() ELSE NULL END,
             CASE WHEN $8::boolean THEN now() ELSE NULL END,
             now(),
             CASE WHEN $9::boolean THEN now() ELSE NULL END)
     ON CONFLICT (user_id, zone_id) DO UPDATE SET
       state              = EXCLUDED.state,
       consecutive_count  = EXCLUDED.consecutive_count,
       pending_state      = EXCLUDED.pending_state,
       last_distance_m    = EXCLUDED.last_distance_m,
       last_transition_at = CASE WHEN $7::boolean THEN now() ELSE zone_states.last_transition_at END,
       last_alert_at      = CASE WHEN $8::boolean THEN now() ELSE zone_states.last_alert_at END,
       last_evaluated_at  = now(),
       last_dwell_alert_at = CASE WHEN $9::boolean THEN now() ELSE zone_states.last_dwell_alert_at END
     RETURNING *`,
    [
      userId,
      zoneId,
      state,
      consecutiveCount,
      pendingState ?? null,
      lastDistanceM ?? null,
      Boolean(transitioned),
      Boolean(alerted),
      Boolean(dwellAlerted),
    ],
  );
  return mapZoneState(rows[0]);
}
