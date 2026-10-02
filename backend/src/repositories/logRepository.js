/**
 * مخزن لاگ‌ها و سنجه‌ها.
 *
 * چهار جدول این فایل، ابزار اندازه‌گیریِ همان دو متغیری‌اند که پروپوزال
 * تعریف کرده است: «دقت موقعیت‌یابی» و «تأخیر سیستم».
 *
 *   request_logs        → سرور چقدر طول کشید
 *   location_telemetry  → از گوشی تا سرور چقدر طول کشید و دقت مکان چه بود
 *   alert_deliveries    → از تولید هشدار تا رسیدنش به مراقب چقدر طول کشید
 *   audit_logs          → چه کسی چه کاری کرد
 *
 * ── قاعده‌ی الزام‌آور حریم خصوصی ────────────────────────────────────────
 * هیچ مختصات، هیچ بدنه‌ی درخواست و هیچ رازی وارد این جدول‌ها نمی‌شود.
 * از موقعیت فقط `accuracy_m` نگه داشته می‌شود، چون دقت یک «سنجه» است
 * ولی مختصات یک «داده‌ی شخصی».
 */
import db from '../db/index.js';

/* ═══════════════════════════ نوشتن ═══════════════════════════ */

/**
 * درج دسته‌ای لاگ درخواست.
 * دسته‌ای است چون میان‌افزار لاگ روی مسیر داغِ هر درخواست قرار دارد؛ یک
 * INSERT به‌ازای هر درخواست یعنی دو برابر شدن رفت‌وبرگشت دیتابیس و آلوده
 * شدن همان عددی که قرار است اندازه بگیریم.
 *
 * @param {Array<object>} entries
 * @returns {Promise<number>} تعداد ردیف‌های درج‌شده
 */
export async function insertRequestLogs(entries) {
  if (!Array.isArray(entries) || entries.length === 0) return 0;

  const columns = 11;
  const values = [];
  const placeholders = entries.map((_, i) => {
    const base = i * columns;
    return `($${base + 1},$${base + 2},$${base + 3},$${base + 4},$${base + 5},$${base + 6},$${base + 7},$${base + 8},$${base + 9},$${base + 10},$${base + 11})`;
  });

  for (const e of entries) {
    values.push(
      e.requestId,
      e.userId ?? null,
      e.method,
      e.route,
      e.statusCode,
      e.latencyMs,
      e.requestBytes ?? null,
      e.responseBytes ?? null,
      e.errorCode ?? null,
      e.clientKind ?? null,
      e.ipHash ?? null,
    );
  }

  const { rowCount } = await db.query(
    `INSERT INTO request_logs
       (request_id, user_id, method, route, status_code, latency_ms,
        request_bytes, response_bytes, error_code, client_kind, ip_hash)
     VALUES ${placeholders.join(',')}`,
    values,
  );
  return rowCount;
}

/** درج دسته‌ای تله‌متری موقعیت. */
export async function insertLocationTelemetry(entries) {
  if (!Array.isArray(entries) || entries.length === 0) return 0;

  const columns = 14;
  const values = [];
  const placeholders = entries.map((_, i) => {
    const b = i * columns;
    return `($${b + 1},$${b + 2},$${b + 3},$${b + 4},$${b + 5},$${b + 6},$${b + 7},$${b + 8},$${b + 9},$${b + 10},$${b + 11},$${b + 12},$${b + 13},$${b + 14})`;
  });

  for (const e of entries) {
    values.push(
      e.userId,
      e.pingId ?? null,
      e.recordedAt,
      e.e2eLatencyMs,
      e.processMs ?? null,
      e.accuracyM ?? null,
      e.provider ?? null,
      e.source ?? 'device',
      e.batchSize ?? 1,
      Boolean(e.isQueuedReplay),
      e.gapSec ?? null,
      e.referenceLat ?? null,
      e.referenceLng ?? null,
      e.errorM ?? null,
    );
  }

  const { rowCount } = await db.query(
    `INSERT INTO location_telemetry
       (user_id, ping_id, recorded_at, e2e_latency_ms, process_ms, accuracy_m,
        provider, source, batch_size, is_queued_replay, gap_sec,
        reference_lat, reference_lng, error_m)
     VALUES ${placeholders.join(',')}`,
    values,
  );
  return rowCount;
}

/** ثبت یک ردیف حسابرسی. */
export async function insertAuditLog(entry) {
  const { rows } = await db.query(
    `INSERT INTO audit_logs
       (actor_user_id, actor_role, action, entity_type, entity_id, metadata, ip_hash, request_id)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8)
     RETURNING id, created_at`,
    [
      entry.actorUserId ?? null,
      entry.actorRole ?? null,
      entry.action,
      entry.entityType ?? null,
      entry.entityId ? String(entry.entityId) : null,
      JSON.stringify(entry.metadata ?? {}),
      entry.ipHash ?? null,
      entry.requestId ?? null,
    ],
  );
  return { id: rows[0]?.id, createdAt: rows[0]?.created_at };
}

/** درج دسته‌ای رکورد تحویل هشدار (یک ردیف به‌ازای هر گیرنده و هر کانال). */
export async function insertAlertDeliveries(entries) {
  if (!Array.isArray(entries) || entries.length === 0) return 0;

  const columns = 6;
  const values = [];
  const placeholders = entries.map((_, i) => {
    const b = i * columns;
    return `($${b + 1},$${b + 2},$${b + 3},$${b + 4},$${b + 5},$${b + 6})`;
  });

  for (const e of entries) {
    values.push(
      e.alertId,
      e.recipientUserId,
      e.channel,
      e.status ?? 'sent',
      e.latencyMs ?? null,
      e.errorCode ?? null,
    );
  }

  const { rowCount } = await db.query(
    `INSERT INTO alert_deliveries
       (alert_id, recipient_user_id, channel, status, latency_ms, error_code)
     VALUES ${placeholders.join(',')}`,
    values,
  );
  return rowCount;
}

/**
 * ثبت لحظه‌ای که گیرنده هشدار را واقعاً دید.
 * این عدد، تنها سنجه‌ی «تأخیر تا اطلاع انسان» است؛ بقیه‌ی زنجیره فقط
 * تأخیر ماشین را می‌سنجد.
 */
export async function acknowledgeDelivery(alertId, recipientUserId) {
  const { rowCount } = await db.query(
    `UPDATE alert_deliveries
        SET acknowledged_at = now()
      WHERE alert_id = $1 AND recipient_user_id = $2 AND acknowledged_at IS NULL`,
    [alertId, recipientUserId],
  );
  return rowCount;
}

/* ═══════════════════════════ خواندن ═══════════════════════════ */

const mapRequestLog = (row) => ({
  id: row.id,
  requestId: row.request_id,
  userId: row.user_id,
  userName: row.user_name ?? null,
  method: row.method,
  route: row.route,
  statusCode: row.status_code,
  latencyMs: row.latency_ms,
  errorCode: row.error_code,
  clientKind: row.client_kind,
  createdAt: new Date(row.created_at).toISOString(),
});

/**
 * فهرست لاگ درخواست‌ها با فیلتر.
 * فیلترها با الگوی «پارامتر یا NULL» نوشته شده‌اند تا یک کوئری ثابت داشته
 * باشیم و رشته‌ی SQL هرگز از ورودی کاربر ساخته نشود.
 */
export async function listRequestLogs({
  from = null,
  to = null,
  route = null,
  minStatus = null,
  userId = null,
  limit = 100,
  offset = 0,
} = {}) {
  const { rows } = await db.query(
    `SELECT r.*, u.full_name AS user_name
       FROM request_logs r
       LEFT JOIN users u ON u.id = r.user_id
      WHERE ($1::timestamptz IS NULL OR r.created_at >= $1)
        AND ($2::timestamptz IS NULL OR r.created_at <= $2)
        AND ($3::text        IS NULL OR r.route ILIKE '%' || $3 || '%')
        AND ($4::int         IS NULL OR r.status_code >= $4)
        AND ($5::uuid        IS NULL OR r.user_id = $5)
      ORDER BY r.created_at DESC
      LIMIT $6 OFFSET $7`,
    [from, to, route, minStatus, userId, limit, offset],
  );
  return rows.map(mapRequestLog);
}

export async function countRequestLogs({
  from = null,
  to = null,
  route = null,
  minStatus = null,
  userId = null,
} = {}) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total
       FROM request_logs r
      WHERE ($1::timestamptz IS NULL OR r.created_at >= $1)
        AND ($2::timestamptz IS NULL OR r.created_at <= $2)
        AND ($3::text        IS NULL OR r.route ILIKE '%' || $3 || '%')
        AND ($4::int         IS NULL OR r.status_code >= $4)
        AND ($5::uuid        IS NULL OR r.user_id = $5)`,
    [from, to, route, minStatus, userId],
  );
  return rows[0]?.total ?? 0;
}

const mapAuditLog = (row) => ({
  id: row.id,
  actorUserId: row.actor_user_id,
  actorName: row.actor_name ?? null,
  actorRole: row.actor_role,
  action: row.action,
  entityType: row.entity_type,
  entityId: row.entity_id,
  metadata: row.metadata ?? {},
  createdAt: new Date(row.created_at).toISOString(),
});

export async function listAuditLogs({
  from = null,
  to = null,
  action = null,
  actorUserId = null,
  limit = 100,
  offset = 0,
} = {}) {
  const { rows } = await db.query(
    `SELECT a.*, u.full_name AS actor_name
       FROM audit_logs a
       LEFT JOIN users u ON u.id = a.actor_user_id
      WHERE ($1::timestamptz IS NULL OR a.created_at >= $1)
        AND ($2::timestamptz IS NULL OR a.created_at <= $2)
        AND ($3::text        IS NULL OR a.action = $3)
        AND ($4::uuid        IS NULL OR a.actor_user_id = $4)
      ORDER BY a.created_at DESC
      LIMIT $5 OFFSET $6`,
    [from, to, action, actorUserId, limit, offset],
  );
  return rows.map(mapAuditLog);
}

export async function countAuditLogs({
  from = null,
  to = null,
  action = null,
  actorUserId = null,
} = {}) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total
       FROM audit_logs a
      WHERE ($1::timestamptz IS NULL OR a.created_at >= $1)
        AND ($2::timestamptz IS NULL OR a.created_at <= $2)
        AND ($3::text        IS NULL OR a.action = $3)
        AND ($4::uuid        IS NULL OR a.actor_user_id = $4)`,
    [from, to, action, actorUserId],
  );
  return rows[0]?.total ?? 0;
}

/* ═══════════════════════ سنجه‌های تجمیعی ═══════════════════════ */

const num = (v) => (v === null || v === undefined ? null : Number(v));

/**
 * سنجه‌های تأخیر سرور.
 * علاوه بر میانگین، صدک‌های ۵۰/۹۵/۹۹ هم برمی‌گردند: میانگین به‌تنهایی
 * وضعیت بدترین کاربران را پنهان می‌کند و برای گزارش پایان‌نامه کافی نیست.
 */
export async function requestMetrics({ from = null, to = null } = {}) {
  const { rows } = await db.query(
    `SELECT
       COUNT(*)::int                                                       AS total,
       COUNT(*) FILTER (WHERE status_code >= 500)::int                     AS server_errors,
       COUNT(*) FILTER (WHERE status_code >= 400 AND status_code < 500)::int AS client_errors,
       AVG(latency_ms)                                                     AS avg_ms,
       MAX(latency_ms)                                                     AS max_ms,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)            AS p50_ms,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)            AS p95_ms,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)            AS p99_ms
     FROM request_logs
     WHERE ($1::timestamptz IS NULL OR created_at >= $1)
       AND ($2::timestamptz IS NULL OR created_at <= $2)`,
    [from, to],
  );
  const r = rows[0] ?? {};
  return {
    total: r.total ?? 0,
    serverErrors: r.server_errors ?? 0,
    clientErrors: r.client_errors ?? 0,
    avgMs: num(r.avg_ms),
    maxMs: num(r.max_ms),
    p50Ms: num(r.p50_ms),
    p95Ms: num(r.p95_ms),
    p99Ms: num(r.p99_ms),
  };
}

/** کندترین مسیرها — برای اینکه بهینه‌سازی روی حدس انجام نشود. */
export async function slowestRoutes({ from = null, to = null, limit = 10 } = {}) {
  const { rows } = await db.query(
    `SELECT route,
            COUNT(*)::int                                            AS count,
            AVG(latency_ms)                                          AS avg_ms,
            percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms) AS p95_ms
       FROM request_logs
      WHERE ($1::timestamptz IS NULL OR created_at >= $1)
        AND ($2::timestamptz IS NULL OR created_at <= $2)
      GROUP BY route
      ORDER BY p95_ms DESC NULLS LAST
      LIMIT $3`,
    [from, to, limit],
  );
  return rows.map((r) => ({
    route: r.route,
    count: r.count,
    avgMs: num(r.avg_ms),
    p95Ms: num(r.p95_ms),
  }));
}

/**
 * سنجه‌های موقعیت — همان جدولی که در فصل ارزیابی پایان‌نامه گزارش می‌شود.
 *
 * پینگ‌هایی که از صف آفلاین با تأخیر آمده‌اند، از محاسبه‌ی تأخیر کنار گذاشته
 * می‌شوند: تأخیرِ آن‌ها اندازه‌ی قطعیِ اینترنت است، نه اندازه‌ی کندیِ سیستم.
 * تعدادشان جداگانه گزارش می‌شود تا حذفشان پنهان نماند.
 */
export async function locationMetrics({ from = null, to = null } = {}) {
  const { rows } = await db.query(
    `SELECT
       COUNT(*)::int                                     AS total,
       COUNT(*) FILTER (WHERE is_queued_replay)::int     AS queued_replays,
       COUNT(*) FILTER (WHERE source = 'simulator')::int AS simulated,
       AVG(accuracy_m)                                   AS avg_accuracy_m,
       COUNT(*) FILTER (WHERE error_m IS NOT NULL AND NOT is_queued_replay AND (accuracy_m IS NULL OR accuracy_m <= 30))::int AS error_samples,
       AVG(error_m) FILTER (WHERE error_m IS NOT NULL AND NOT is_queued_replay AND (accuracy_m IS NULL OR accuracy_m <= 30)) AS avg_error_m,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY error_m) FILTER (WHERE error_m IS NOT NULL AND NOT is_queued_replay AND (accuracy_m IS NULL OR accuracy_m <= 30)) AS p50_error_m,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY accuracy_m) AS p50_accuracy_m,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY accuracy_m) AS p95_accuracy_m,
       AVG(e2e_latency_ms)     FILTER (WHERE NOT is_queued_replay) AS avg_e2e_ms,
       AVG(process_ms)                                             AS avg_process_ms,
       COUNT(DISTINCT user_id)::int                                AS users
     FROM location_telemetry
     WHERE ($1::timestamptz IS NULL OR created_at >= $1)
       AND ($2::timestamptz IS NULL OR created_at <= $2)`,
    [from, to],
  );

  // صدک تأخیر جداگانه محاسبه می‌شود چون percentile_cont با FILTER ترکیب نمی‌شود
  const { rows: pct } = await db.query(
    `SELECT
       percentile_cont(0.50) WITHIN GROUP (ORDER BY e2e_latency_ms) AS p50_e2e_ms,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY e2e_latency_ms) AS p95_e2e_ms
     FROM location_telemetry
     WHERE is_queued_replay = FALSE
       AND ($1::timestamptz IS NULL OR created_at >= $1)
       AND ($2::timestamptz IS NULL OR created_at <= $2)`,
    [from, to],
  );

  const r = rows[0] ?? {};
  const p = pct[0] ?? {};
  return {
    total: r.total ?? 0,
    users: r.users ?? 0,
    queuedReplays: r.queued_replays ?? 0,
    simulated: r.simulated ?? 0,
    accuracy: {
      avgM: num(r.avg_accuracy_m),
      p50M: num(r.p50_accuracy_m),
      p95M: num(r.p95_accuracy_m),
      note: 'دقت اعلامی خود GPS؛ معیار پروپوزال نیست',
    },
    positionError: {
      samples: r.error_samples ?? 0,
      avgM: num(r.avg_error_m),
      p50M: num(r.p50_error_m),
      unit: 'meter',
      definition: 'فاصله نقطه مرجع واقعی تا مختصات ثبت‌شده',
      rule: 'نمونه معتبر: نقطه مرجع دارد، بازپخش آفلاین نیست، و دقت اعلامی GPS حداکثر ۳۰ متر است',
    },
    latency: {
      avgE2eMs: num(r.avg_e2e_ms),
      p50E2eMs: num(p.p50_e2e_ms),
      p95E2eMs: num(p.p95_e2e_ms),
      avgProcessMs: num(r.avg_process_ms),
    },
  };
}

/** سنجه‌های تحویل هشدار، به تفکیک کانال. */
export async function deliveryMetrics({ from = null, to = null } = {}) {
  const { rows } = await db.query(
    `SELECT channel,
            COUNT(*)::int                                       AS total,
            COUNT(*) FILTER (WHERE status = 'failed')::int      AS failed,
            COUNT(*) FILTER (WHERE acknowledged_at IS NOT NULL)::int AS acknowledged,
            AVG(latency_ms)                                     AS avg_ms,
            percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms) AS p95_ms
       FROM alert_deliveries
      WHERE ($1::timestamptz IS NULL OR created_at >= $1)
        AND ($2::timestamptz IS NULL OR created_at <= $2)
      GROUP BY channel
      ORDER BY total DESC`,
    [from, to],
  );
  return rows.map((r) => ({
    channel: r.channel,
    total: r.total,
    failed: r.failed,
    acknowledged: r.acknowledged,
    avgMs: num(r.avg_ms),
    p95Ms: num(r.p95_ms),
  }));
}

/** نمودار روزانه‌ی حجم درخواست و تأخیر — ورودی نمودار پنل ادمین. */
export async function dailyRequestSeries({ days = 7 } = {}) {
  const { rows } = await db.query(
    `SELECT date_trunc('day', created_at) AS day,
            COUNT(*)::int                 AS count,
            AVG(latency_ms)               AS avg_ms,
            COUNT(*) FILTER (WHERE status_code >= 500)::int AS errors
       FROM request_logs
      WHERE created_at >= now() - ($1 || ' days')::interval
      GROUP BY 1
      ORDER BY 1 ASC`,
    [String(days)],
  );
  return rows.map((r) => ({
    day: new Date(r.day).toISOString(),
    count: r.count,
    avgMs: num(r.avg_ms),
    errors: r.errors,
  }));
}

/**
 * پاک‌سازی لاگ‌های قدیمی.
 * لاگ بی‌نهایت نگه داشته نمی‌شود: هم دیتابیس را بزرگ می‌کند و هم با اصل
 * کمینه‌سازی داده در تضاد است.
 */
export async function purgeOlderThan(days) {
  const interval = `${Number(days)} days`;
  const req = await db.query(
    `DELETE FROM request_logs WHERE created_at < now() - $1::interval`,
    [interval],
  );
  const tel = await db.query(
    `DELETE FROM location_telemetry WHERE created_at < now() - $1::interval`,
    [interval],
  );
  return { requestLogs: req.rowCount, locationTelemetry: tel.rowCount };
}

export async function getLocationReference(userId) {
  const { rows } = await db.query(
    `SELECT lat, lng, label, updated_at FROM location_references WHERE user_id = $1`,
    [userId],
  );
  if (!rows[0]) return null;
  return {
    lat: rows[0].lat,
    lng: rows[0].lng,
    label: rows[0].label,
    updatedAt: rows[0].updated_at,
  };
}

export async function upsertLocationReference(userId, { lat, lng, label }) {
  const { rows } = await db.query(
    `INSERT INTO location_references (user_id, lat, lng, label)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id) DO UPDATE
       SET lat = EXCLUDED.lat, lng = EXCLUDED.lng, label = EXCLUDED.label, updated_at = now()
     RETURNING lat, lng, label, updated_at`,
    [userId, lat, lng, label ?? null],
  );
  return {
    lat: rows[0].lat,
    lng: rows[0].lng,
    label: rows[0].label,
    updatedAt: rows[0].updated_at,
  };
}

/** نمرهٔ SUS از ده پاسخ ۱ تا ۵. گویه‌های فرد: امتیاز−۱، زوج: ۵−امتیاز، جمع × ۲٫۵ */
export function scoreSus(answers) {
  if (!Array.isArray(answers) || answers.length !== 10) {
    throw new Error('SUS_ANSWERS');
  }
  let sum = 0;
  answers.forEach((raw, index) => {
    const value = Number(raw);
    if (!Number.isInteger(value) || value < 1 || value > 5) throw new Error('SUS_ANSWERS');
    sum += index % 2 === 0 ? value - 1 : 5 - value;
  });
  return sum * 2.5;
}

export async function insertSusResponse(userId, role, answers, score) {
  const { rows } = await db.query(
    `INSERT INTO sus_responses (user_id, role, answers, score)
     VALUES ($1, $2, $3::jsonb, $4)
     RETURNING id, score, created_at`,
    [userId, role, JSON.stringify(answers), score],
  );
  return { id: rows[0].id, score: rows[0].score, createdAt: rows[0].created_at };
}

export async function susMetrics() {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total, AVG(score) AS avg_score,
            percentile_cont(0.50) WITHIN GROUP (ORDER BY score) AS p50_score
       FROM sus_responses`,
  );
  const r = rows[0] ?? {};
  return { total: r.total ?? 0, avgScore: num(r.avg_score), p50Score: num(r.p50_score) };
}

export default {
  insertRequestLogs,
  insertLocationTelemetry,
  getLocationReference,
  upsertLocationReference,
  scoreSus,
  insertSusResponse,
  susMetrics,
  insertAuditLog,
  insertAlertDeliveries,
  acknowledgeDelivery,
  listRequestLogs,
  countRequestLogs,
  listAuditLogs,
  countAuditLogs,
  requestMetrics,
  slowestRoutes,
  locationMetrics,
  deliveryMetrics,
  dailyRequestSeries,
  purgeOlderThan,
};
