/**
 * مخزن پنل مدیریت.
 *
 * کوئری‌های این فایل عمداً از مخزن‌های موجود (userRepository و
 * deviceRepository) جدا نگه داشته شده‌اند: آن‌ها همیشه محدود به «داده‌ی خودِ
 * کاربر» هستند و همین محدودیت، بخشی از تضمین امنیتی‌شان است. کوئری‌هایی که
 * سرتاسر کاربران را می‌بینند نباید در همان فایل بنشینند، وگرنه یک روز
 * تصادفاً از مسیر غیرادمین صدا زده می‌شوند.
 *
 * دسترسی به این مخزن فقط از مسیر `requireRole('admin')` ممکن است.
 */
import db from '../db/index.js';

const d = (v) => (v ? new Date(v).toISOString() : null);

const mapAdminUser = (row) => ({
  id: row.id,
  phone: row.phone,
  fullName: row.full_name,
  role: row.role,
  status: row.status,
  suspendedReason: row.suspended_reason ?? null,
  avatarColor: row.avatar_color,
  createdAt: d(row.created_at),
  lastLoginAt: d(row.last_login_at),
  deletedAt: d(row.deleted_at),
  healthCondition: row.health_condition ?? null,
  verificationStatus: row.verification_status ?? null,
  // شمارنده‌ها فقط وقتی هستند که کوئری فهرست، آن‌ها را حساب کرده باشد
  ...(row.device_count !== undefined ? { deviceCount: Number(row.device_count) } : {}),
  ...(row.guardian_count !== undefined ? { guardianCount: Number(row.guardian_count) } : {}),
  ...(row.watching_count !== undefined ? { watchingCount: Number(row.watching_count) } : {}),
  ...(row.last_ping_at !== undefined ? { lastPingAt: d(row.last_ping_at) } : {}),
});

const mapIdentityDocument = (row) => ({
  id: row.id,
  userId: row.user_id,
  userName: row.user_name,
  userPhone: row.user_phone,
  type: row.document_type,
  imageUrl: row.image_url,
  status: row.status,
  healthCondition: row.health_condition ?? null,
  rejectionReason: row.rejection_reason ?? null,
  createdAt: d(row.created_at),
  reviewedAt: d(row.reviewed_at),
});

export async function listIdentityDocumentsForUser(userId) {
  const { rows } = await db.query(
    `SELECT d.*, u.full_name AS user_name, u.phone AS user_phone, u.health_condition
       FROM identity_documents d JOIN users u ON u.id = d.user_id
      WHERE d.user_id = $1
         OR d.user_id IN (
           SELECT primary_user_id FROM guardianships
            WHERE guardian_user_id = $1 AND status = 'active' AND is_main_supervisor = true
         )
      ORDER BY d.created_at DESC`,
    [userId],
  );
  return rows.map(mapIdentityDocument);
}

export async function listIdentityDocuments({ status = 'pending', limit = 50, offset = 0 } = {}) {
  const { rows } = await db.query(
    `SELECT d.*, u.full_name AS user_name, u.phone AS user_phone, u.health_condition
       FROM identity_documents d JOIN users u ON u.id = d.user_id
      WHERE ($1::text IS NULL OR d.status = $1)
      ORDER BY d.created_at DESC LIMIT $2 OFFSET $3`,
    [status, limit, offset],
  );
  return rows.map(mapIdentityDocument);
}

export async function createIdentityDocument(userId, documentType, imageUrl) {
  const { rows } = await db.query(
    `INSERT INTO identity_documents (user_id, document_type, image_url)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [userId, documentType, imageUrl],
  );
  return mapIdentityDocument(rows[0]);
}

export async function reviewIdentityDocument(id, status, reviewerId, rejectionReason = null) {
  const { rows } = await db.query(
    `UPDATE identity_documents
        SET status = $2, reviewed_by = $3, reviewed_at = now(), rejection_reason = $4
      WHERE id = $1
      RETURNING *`,
    [id, status, reviewerId, rejectionReason],
  );
  return rows[0] ? mapIdentityDocument(rows[0]) : null;
}

/* ═══════════════════════════ کاربران ═══════════════════════════ */

/**
 * فهرست کاربران با جست‌وجو و فیلتر.
 *
 * جست‌وجو روی نام و شماره است و با پارامتر انجام می‌شود، نه با چسباندن رشته
 * به SQL. کاراکترهای ویژه‌ی LIKE (‎%‎ و ‎_‎) هم در لایه‌ی سرویس بی‌اثر می‌شوند.
 */
export async function listUsers({
  search = null,
  role = null,
  status = null,
  limit = 50,
  offset = 0,
} = {}) {
  const { rows } = await db.query(
    `SELECT u.*,
            (SELECT COUNT(*) FROM devices dv WHERE dv.user_id = u.id AND dv.revoked_at IS NULL) AS device_count,
            (SELECT COUNT(*) FROM guardianships g
               WHERE g.primary_user_id = u.id AND g.status = 'active')                          AS guardian_count,
            (SELECT COUNT(*) FROM guardianships g
               WHERE g.guardian_user_id = u.id AND g.status = 'active')                         AS watching_count,
            (SELECT MAX(p.recorded_at) FROM location_pings p WHERE p.user_id = u.id)            AS last_ping_at
       FROM users u
      WHERE ($1::text IS NULL OR u.full_name ILIKE '%' || $1 || '%' OR u.phone LIKE '%' || $1 || '%')
        AND ($2::text IS NULL OR u.role = $2)
        AND ($3::text IS NULL OR u.status = $3)
      ORDER BY u.created_at DESC
      LIMIT $4 OFFSET $5`,
    [search, role, status, limit, offset],
  );
  return rows.map(mapAdminUser);
}

export async function countUsers({ search = null, role = null, status = null } = {}) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total
       FROM users u
      WHERE ($1::text IS NULL OR u.full_name ILIKE '%' || $1 || '%' OR u.phone LIKE '%' || $1 || '%')
        AND ($2::text IS NULL OR u.role = $2)
        AND ($3::text IS NULL OR u.status = $3)`,
    [search, role, status],
  );
  return rows[0]?.total ?? 0;
}

/** یک کاربر با جزئیات کامل — صفحه‌ی جزئیات پنل ادمین. */
export async function getUser(id) {
  const { rows } = await db.query(
    `SELECT u.*,
            (SELECT COUNT(*) FROM devices dv WHERE dv.user_id = u.id AND dv.revoked_at IS NULL) AS device_count,
            (SELECT COUNT(*) FROM guardianships g
               WHERE g.primary_user_id = u.id AND g.status = 'active')                          AS guardian_count,
            (SELECT COUNT(*) FROM guardianships g
               WHERE g.guardian_user_id = u.id AND g.status = 'active')                         AS watching_count,
            (SELECT MAX(p.recorded_at) FROM location_pings p WHERE p.user_id = u.id)            AS last_ping_at
       FROM users u
      WHERE u.id = $1`,
    [id],
  );
  return rows[0] ? mapAdminUser(rows[0]) : null;
}

/** تغییر وضعیت حساب. برگرداندن ردیف به‌روزشده یا null اگر کاربر نبود. */
export async function setUserStatus(id, status, reason = null) {
  const { rows } = await db.query(
    `UPDATE users
        SET status            = $2::text,
            -- تبدیل صریح لازم است: بدون آن، همان پارامتر یک‌جا varchar و
            -- یک‌جا text استنتاج می‌شود و Postgres کوئری را رد می‌کند
            suspended_reason  = CASE WHEN $2::text = 'suspended' THEN $3::text ELSE NULL END,
            deleted_at        = CASE WHEN $2::text = 'deleted'   THEN now() ELSE NULL END,
            updated_at        = now()
      WHERE id = $1
      RETURNING *`,
    [id, status, reason],
  );
  return rows[0] ? mapAdminUser(rows[0]) : null;
}

export async function setUserRole(id, role) {
  const { rows } = await db.query(
    `UPDATE users SET role = $2, updated_at = now() WHERE id = $1 RETURNING *`,
    [id, role],
  );
  return rows[0] ? mapAdminUser(rows[0]) : null;
}

/** ثبت زمان آخرین ورود موفق. */
export async function touchLastLogin(id) {
  await db.query('UPDATE users SET last_login_at = now() WHERE id = $1', [id]);
}

/** شمارش ادمین‌های فعال — برای جلوگیری از حذف آخرین ادمین. */
export async function countActiveAdmins(excludeId = null) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total
       FROM users
      WHERE role = 'admin' AND status = 'active'
        AND ($1::uuid IS NULL OR id <> $1)`,
    [excludeId],
  );
  return rows[0]?.total ?? 0;
}

/**
 * وضعیت حساب برای گاردِ احراز هویت.
 * سبک نگه داشته شده چون ممکن است روی هر درخواست اجرا شود.
 */
export async function setVerificationStatus(userId, status) {
  await db.query('UPDATE users SET verification_status = $2 WHERE id = $1', [userId, status]);
}

export async function accountState(id) {
  const { rows } = await db.query(
    'SELECT id, role, status, verification_status FROM users WHERE id = $1',
    [id],
  );
  return rows[0] ?? null;
}

/* ═══════════════════════════ دستگاه‌ها ═══════════════════════════ */

const mapAdminDevice = (row) => ({
  id: row.id,
  userId: row.user_id,
  userName: row.user_name ?? null,
  userPhone: row.user_phone ?? null,
  platform: row.platform,
  deviceName: row.device_name,
  model: row.model,
  appVersion: row.app_version,
  osVersion: row.os_version,
  hasPushToken: Boolean(row.push_token),
  batteryLevel: row.battery_level,
  lastSeenAt: d(row.last_seen_at),
  lastPingAt: d(row.last_ping_at),
  revokedAt: d(row.revoked_at),
  createdAt: d(row.created_at),
});

export async function listDevices({
  userId = null,
  platform = null,
  includeRevoked = false,
  limit = 50,
  offset = 0,
} = {}) {
  const { rows } = await db.query(
    `SELECT dv.*, u.full_name AS user_name, u.phone AS user_phone
       FROM devices dv
       JOIN users u ON u.id = dv.user_id
      WHERE ($1::uuid IS NULL OR dv.user_id = $1)
        AND ($2::text IS NULL OR dv.platform = $2)
        AND ($3::boolean IS TRUE OR dv.revoked_at IS NULL)
      ORDER BY dv.last_seen_at DESC
      LIMIT $4 OFFSET $5`,
    [userId, platform, includeRevoked, limit, offset],
  );
  return rows.map(mapAdminDevice);
}

export async function countDevices({ userId = null, platform = null, includeRevoked = false } = {}) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS total
       FROM devices dv
      WHERE ($1::uuid IS NULL OR dv.user_id = $1)
        AND ($2::text IS NULL OR dv.platform = $2)
        AND ($3::boolean IS TRUE OR dv.revoked_at IS NULL)`,
    [userId, platform, includeRevoked],
  );
  return rows[0]?.total ?? 0;
}

/**
 * ابطال دستگاه.
 * ردیف حذف نمی‌شود و فقط `revoked_at` پر و توکن Push پاک می‌شود: تاریخچه‌ی
 * «این دستگاه وجود داشته» برای حسابرسی لازم است، ولی از این لحظه به بعد
 * هیچ نوتیفیکیشنی به آن نمی‌رود.
 */
export async function revokeDevice(id) {
  const { rows } = await db.query(
    `UPDATE devices
        SET revoked_at = now(), push_token = NULL
      WHERE id = $1 AND revoked_at IS NULL
      RETURNING *`,
    [id],
  );
  return rows[0] ? mapAdminDevice(rows[0]) : null;
}

/* ═══════════════════════════ آمار کلی ═══════════════════════════ */

/** اعداد بالای صفحه‌ی نخست پنل ادمین. */
export async function overview() {
  const { rows } = await db.query(
    `SELECT
       (SELECT COUNT(*)::int FROM users)                                        AS users_total,
       (SELECT COUNT(*)::int FROM users WHERE status = 'active')                AS users_active,
       (SELECT COUNT(*)::int FROM users WHERE status = 'suspended')             AS users_suspended,
       (SELECT COUNT(*)::int FROM users WHERE role = 'primary')                 AS users_primary,
       (SELECT COUNT(*)::int FROM users WHERE role = 'guardian')                AS users_guardian,
       (SELECT COUNT(*)::int FROM users WHERE role = 'admin')                   AS users_admin,
       (SELECT COUNT(*)::int FROM users WHERE created_at >= now() - interval '7 days') AS users_new_7d,
       (SELECT COUNT(*)::int FROM devices WHERE revoked_at IS NULL)             AS devices_active,
       (SELECT COUNT(*)::int FROM guardianships WHERE status = 'active')        AS guardianships_active,
       (SELECT COUNT(*)::int FROM safe_zones WHERE is_active)                   AS zones_active,
       (SELECT COUNT(*)::int FROM alerts WHERE created_at >= now() - interval '24 hours') AS alerts_24h,
       (SELECT COUNT(*)::int FROM alerts WHERE type = 'sos' AND created_at >= now() - interval '24 hours') AS sos_24h,
       (SELECT COUNT(*)::int FROM location_pings WHERE recorded_at >= now() - interval '24 hours') AS pings_24h,
       (SELECT COUNT(*)::int FROM location_pings
          WHERE recorded_at >= now() - interval '24 hours' AND is_simulated)    AS pings_24h_simulated`,
  );
  const r = rows[0] ?? {};
  return {
    users: {
      total: r.users_total ?? 0,
      active: r.users_active ?? 0,
      suspended: r.users_suspended ?? 0,
      new7d: r.users_new_7d ?? 0,
      byRole: {
        primary: r.users_primary ?? 0,
        guardian: r.users_guardian ?? 0,
        admin: r.users_admin ?? 0,
      },
    },
    devicesActive: r.devices_active ?? 0,
    guardianshipsActive: r.guardianships_active ?? 0,
    zonesActive: r.zones_active ?? 0,
    alerts24h: r.alerts_24h ?? 0,
    sos24h: r.sos_24h ?? 0,
    pings24h: r.pings_24h ?? 0,
    // صادقانه گزارش می‌شود چند درصد داده‌ی امروز از شبیه‌ساز آمده است
    pings24hSimulated: r.pings_24h_simulated ?? 0,
  };
}

/** آخرین هشدارهای کل سامانه — نمای نظارتی ادمین. */
export async function recentAlerts(limit = 20) {
  const { rows } = await db.query(
    `SELECT a.id, a.type, a.severity, a.title, a.created_at, a.resolved_at,
            u.id AS subject_id, u.full_name AS subject_name
       FROM alerts a
       JOIN users u ON u.id = a.user_id
      ORDER BY a.created_at DESC
      LIMIT $1`,
    [limit],
  );
  // توجه: lat/lng عمداً برنمی‌گردد. ادمین به موقعیت زنده‌ی کاربران دسترسی
  // ندارد؛ نقش او مدیریت سامانه است، نه نظارت بر افراد.
  return rows.map((r) => ({
    id: r.id,
    type: r.type,
    severity: r.severity,
    title: r.title,
    createdAt: d(r.created_at),
    resolvedAt: d(r.resolved_at),
    subject: { id: r.subject_id, fullName: r.subject_name },
  }));
}

export async function listFamilies() {
  const { rows } = await db.query(
    `SELECT p.id AS primary_id, p.full_name AS primary_name, p.phone AS primary_phone,
            p.health_condition, p.verification_status,
            g.full_name AS guardian_name, g.phone AS guardian_phone,
            gs.is_main_supervisor, gs.permissions
       FROM users p
       LEFT JOIN guardianships gs ON gs.primary_user_id = p.id AND gs.status = 'active'
       LEFT JOIN users g ON g.id = gs.guardian_user_id
      WHERE p.role = 'primary' AND p.deleted_at IS NULL
      ORDER BY p.full_name, g.full_name`,
  );
  const families = new Map();
  for (const row of rows) {
    if (!families.has(row.primary_id)) {
      families.set(row.primary_id, {
        primaryId: row.primary_id,
        primaryName: row.primary_name,
        primaryPhone: row.primary_phone,
        healthCondition: row.verification_status === 'verified' ? row.health_condition : null,
        verificationStatus: row.verification_status,
        guardians: [],
        zoneLabel: null,
      });
    }
    if (row.guardian_name) {
      families.get(row.primary_id).guardians.push({
        fullName: row.guardian_name,
        phone: row.guardian_phone,
        isMainSupervisor: row.is_main_supervisor === true,
        permissions: row.permissions ?? [],
      });
    }
  }
  const ids = [...families.keys()];
  if (ids.length > 0) {
    const { rows: zoneRows } = await db.query(
      `SELECT z.user_id, s.state, z.name
         FROM safe_zones z
         LEFT JOIN zone_states s ON s.zone_id = z.id AND s.user_id = z.user_id
        WHERE z.user_id = ANY($1::uuid[]) AND z.is_active = TRUE`,
      [ids],
    );
    for (const zone of zoneRows) {
      const family = families.get(zone.user_id);
      if (!family) continue;
      const label = zone.state === 'inside'
        ? `داخل «${zone.name}»`
        : zone.state === 'outside'
          ? `خارج از «${zone.name}»`
          : `محدوده «${zone.name}»`;
      if (zone.state === 'inside') family.zoneLabel = label;
      else if (!family.zoneLabel) family.zoneLabel = label;
    }
  }
  return [...families.values()];
}

export async function listAlertsWithoutLocation(limit = 80) {
  const { rows } = await db.query(
    `SELECT a.id, a.type, a.title, a.body, a.severity, a.created_at, u.full_name, u.id AS subject_id
       FROM alerts a JOIN users u ON u.id = a.user_id
      ORDER BY a.created_at DESC LIMIT $1`,
    [limit],
  );
  return rows.map((row) => ({
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    severity: row.severity,
    createdAt: d(row.created_at),
    subjectId: row.subject_id,
    subjectName: row.full_name,
  }));
}

export async function setHealthCondition(userId, condition) {
  await db.query('UPDATE users SET health_condition = $2 WHERE id = $1', [userId, condition]);
}

export async function listSupportMessages(userId) {
  const { rows } = await db.query(
    `SELECT id, user_id, sender_role, body, created_at
       FROM support_messages WHERE user_id = $1 ORDER BY created_at`,
    [userId],
  );
  return rows.map((row) => ({
    id: row.id,
    userId: row.user_id,
    senderRole: row.sender_role,
    body: row.body,
    createdAt: d(row.created_at),
  }));
}

export async function addSupportMessage(userId, senderRole, body) {
  const { rows } = await db.query(
    `INSERT INTO support_messages (user_id, sender_role, body)
     VALUES ($1, $2, $3) RETURNING id, created_at`,
    [userId, senderRole, body],
  );
  return { id: rows[0].id, createdAt: d(rows[0].created_at) };
}

export async function listSupportThreads() {
  const { rows } = await db.query(
    `SELECT m.user_id, u.full_name, u.phone, u.role,
            count(*)::int AS message_count,
            max(m.created_at) AS last_at
       FROM support_messages m JOIN users u ON u.id = m.user_id
      GROUP BY m.user_id, u.full_name, u.phone, u.role
      ORDER BY max(m.created_at) DESC`,
  );
  return rows.map((row) => ({
    userId: row.user_id,
    fullName: row.full_name,
    phone: row.phone,
    role: row.role,
    messageCount: row.message_count,
    lastAt: d(row.last_at),
  }));
}

export async function isMainSupervisor(guardianId, primaryId) {
  const { rows } = await db.query(
    `SELECT 1 FROM guardianships
      WHERE guardian_user_id = $1 AND primary_user_id = $2
        AND status = 'active' AND is_main_supervisor = true`,
    [guardianId, primaryId],
  );
  return rows.length > 0;
}

export default {
  listUsers,
  countUsers,
  getUser,
  setUserStatus,
  setUserRole,
  touchLastLogin,
  countActiveAdmins,
  accountState,
  setVerificationStatus,
  listDevices,
  countDevices,
  revokeDevice,
  overview,
  recentAlerts,
  listIdentityDocuments,
  listIdentityDocumentsForUser,
  createIdentityDocument,
  reviewIdentityDocument,
  setHealthCondition,
  listSupportMessages,
  addSupportMessage,
  listSupportThreads,
  isMainSupervisor,
  listFamilies,
  listAlertsWithoutLocation,
};
