/**
 * مخزن دستگاه‌ها — نگهداری توکن‌های Push و آخرین وضعیت باتری.
 */
import db from '../db/index.js';
import { mapDevice } from './mappers.js';

/**
 * ثبت یا به‌روزرسانی دستگاه.
 * کلید یکتایی روی (user_id, push_token) است، پس نصب مجدد اپ روی همان دستگاه
 * ردیف تکراری نمی‌سازد و توکن قدیمی بی‌صاحب رها نمی‌شود.
 */
/**
 * ثبت یا به‌روزرسانی دستگاه.
 *
 * دو کلید یکتاسازی وجود دارد و ترتیبشان مهم است:
 *
 *   ۱) `install_id` — شناسه‌ی پایدارِ نصب که خودِ اپ می‌سازد. توکن FCM با هر
 *      پاک‌سازی داده یا نصب مجدد عوض می‌شود؛ اگر فقط به آن تکیه کنیم، هر
 *      کاربر پس از چند ماه ده‌ها ردیف دستگاه پیدا می‌کند و نوتیفیکیشن به
 *      توکن‌های مرده فرستاده می‌شود.
 *   ۲) `push_token` — مسیر سازگاری با کلاینت‌هایی (مثل داشبورد وب) که
 *      شناسه‌ی نصب ندارند.
 *
 * `ON CONFLICT` فقط یک محدودیت را می‌تواند استنتاج کند، برای همین بسته به
 * اینکه کدام شناسه آمده، یکی از دو مسیر انتخاب می‌شود.
 */
export async function register({
  userId, platform, pushToken, deviceName, batteryLevel,
  installId, appVersion, osVersion, model,
}) {
  const params = [
    userId,
    platform,
    pushToken ?? null,
    deviceName ?? null,
    batteryLevel ?? null,
    installId ?? null,
    appVersion ?? null,
    osVersion ?? null,
    model ?? null,
  ];

  const columns = `(user_id, platform, push_token, device_name, battery_level,
                    install_id, app_version, os_version, model)`;
  const values = '($1, $2, $3, $4, $5, $6, $7, $8, $9)';
  const updates = `
       platform      = EXCLUDED.platform,
       push_token    = COALESCE(EXCLUDED.push_token, devices.push_token),
       device_name   = COALESCE(EXCLUDED.device_name, devices.device_name),
       battery_level = COALESCE(EXCLUDED.battery_level, devices.battery_level),
       install_id    = COALESCE(EXCLUDED.install_id, devices.install_id),
       app_version   = COALESCE(EXCLUDED.app_version, devices.app_version),
       os_version    = COALESCE(EXCLUDED.os_version, devices.os_version),
       model         = COALESCE(EXCLUDED.model, devices.model),
       -- ثبت مجدد یعنی دستگاه دوباره در دسترس است؛ ابطال قبلی برداشته می‌شود
       revoked_at    = NULL,
       last_seen_at  = now()`;

  const conflictTarget = installId
    ? '(user_id, install_id) WHERE install_id IS NOT NULL'
    : '(user_id, push_token)';

  const { rows } = await db.query(
    `INSERT INTO devices ${columns}
     VALUES ${values}
     ON CONFLICT ${conflictTarget} DO UPDATE SET ${updates}
     RETURNING *`,
    params,
  );
  const device = mapDevice(rows[0]);
  if (pushToken) {
    await db.query(
      `UPDATE devices SET push_token = NULL
        WHERE push_token = $1 AND id <> $2`,
      [pushToken, device.id],
    );
  }
  return device;
}

/** ابطال توکنی که FCM دیگر آن را نمی‌شناسد. */
export async function clearPushToken(token) {
  if (!token) return 0;
  const { rowCount } = await db.query(
    'UPDATE devices SET push_token = NULL WHERE push_token = $1',
    [token],
  );
  return rowCount;
}

export async function listByUser(userId) {
  const { rows } = await db.query(
    'SELECT * FROM devices WHERE user_id = $1 ORDER BY last_seen_at DESC',
    [userId],
  );
  return rows.map(mapDevice);
}

/** توکن‌های Push یک کاربر — ورودی آداپتور نوتیفیکیشن. */
export async function pushTokensFor(userIds) {
  if (!Array.isArray(userIds) || userIds.length === 0) return [];
  const { rows } = await db.query(
    `SELECT user_id, push_token, platform FROM devices
     WHERE user_id = ANY($1::uuid[]) AND push_token IS NOT NULL AND revoked_at IS NULL`,
    [userIds],
  );
  return rows.map((r) => ({ userId: r.user_id, token: r.push_token, platform: r.platform }));
}

/** به‌روزرسانی باتری و آخرین بازدید — همراه هر پینگ موقعیت صدا زده می‌شود. */
export async function touch(userId, { batteryLevel, isPing = true } = {}) {
  await db.query(
    `UPDATE devices SET
       last_seen_at  = now(),
       last_ping_at  = CASE WHEN $3 THEN now() ELSE last_ping_at END,
       battery_level = COALESCE($2, battery_level)
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId, batteryLevel ?? null, Boolean(isPing)],
  );
}

export async function remove(id, userId) {
  const { rowCount } = await db.query('DELETE FROM devices WHERE id = $1 AND user_id = $2', [
    id,
    userId,
  ]);
  return rowCount > 0;
}
