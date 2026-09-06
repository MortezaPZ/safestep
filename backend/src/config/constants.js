/** ثابت‌های مشترک دامنه — تنها منبع حقیقت برای مقادیر مجاز. */

/** سطوح دسترسی که یک کاربر اصلی می‌تواند به عضو خانواده بدهد. */
export const PERMISSIONS = Object.freeze({
  VIEW_LOCATION: 'view_location',
  RECEIVE_ALERTS: 'receive_alerts',
  EMERGENCY: 'emergency',
});
export const ALL_PERMISSIONS = Object.freeze(Object.values(PERMISSIONS));

/** برچسب فارسی سطوح دسترسی — برای نمایش در رابط کاربری. */
export const PERMISSION_LABELS = Object.freeze({
  [PERMISSIONS.VIEW_LOCATION]: 'مشاهده‌ی موقعیت',
  [PERMISSIONS.RECEIVE_ALERTS]: 'دریافت هشدار',
  [PERMISSIONS.EMERGENCY]: 'دسترسی اضطراری',
});

export const ROLES = Object.freeze({ PRIMARY: 'primary', GUARDIAN: 'guardian', ADMIN: 'admin' });
export const ALL_ROLES = Object.freeze(Object.values(ROLES));

/** نقش‌هایی که کاربر می‌تواند هنگام ثبت‌نام برای خودش انتخاب کند — ادمین از این مسیر ساخته نمی‌شود. */
export const SELF_SIGNUP_ROLES = Object.freeze([ROLES.PRIMARY, ROLES.GUARDIAN]);

export const ROLE_LABELS = Object.freeze({
  [ROLES.PRIMARY]: 'کاربر اصلی',
  [ROLES.GUARDIAN]: 'مراقب',
  [ROLES.ADMIN]: 'مدیر سامانه',
});

/** وضعیت حساب کاربری. حساب معلق می‌تواند وارد شود اما هیچ عملیاتی انجام نمی‌دهد. */
export const USER_STATUS = Object.freeze({
  ACTIVE: 'active',
  SUSPENDED: 'suspended',
  DELETED: 'deleted',
});
export const ALL_USER_STATUSES = Object.freeze(Object.values(USER_STATUS));

export const GUARDIANSHIP_STATUS = Object.freeze({ ACTIVE: 'active', REVOKED: 'revoked' });

/** انواع هشدار. هر نوع یک سطح اهمیت ثابت دارد. */
export const ALERT_TYPES = Object.freeze({
  SOS: 'sos',
  ZONE_EXIT: 'zone_exit',
  ZONE_ENTER: 'zone_enter',
  LONG_STOP: 'long_stop',
  GPS_LOST: 'gps_lost',
  LOW_BATTERY: 'low_battery',
  /** فاز سوم — فعلاً هیچ منطقی آن را تولید نمی‌کند، اما شما و رابط کاربری پذیرایش هستند. */
  FALL_DETECTED: 'fall_detected',
});
export const ALL_ALERT_TYPES = Object.freeze(Object.values(ALERT_TYPES));

export const SEVERITY = Object.freeze({ INFO: 'info', WARNING: 'warning', CRITICAL: 'critical' });

/**
 * نگاشت نوع هشدار به سطح اهمیت.
 * قاعده‌ی طراحی: قرمز (critical) فقط و فقط برای SOS.
 */
export const ALERT_SEVERITY = Object.freeze({
  [ALERT_TYPES.SOS]: SEVERITY.CRITICAL,
  [ALERT_TYPES.ZONE_EXIT]: SEVERITY.WARNING,
  [ALERT_TYPES.LONG_STOP]: SEVERITY.WARNING,
  [ALERT_TYPES.GPS_LOST]: SEVERITY.WARNING,
  [ALERT_TYPES.LOW_BATTERY]: SEVERITY.INFO,
  [ALERT_TYPES.ZONE_ENTER]: SEVERITY.INFO,
  [ALERT_TYPES.FALL_DETECTED]: SEVERITY.CRITICAL,
});

/** کدام سطح دسترسی برای دریافت هر نوع هشدار لازم است. */
export const ALERT_REQUIRED_PERMISSION = Object.freeze({
  [ALERT_TYPES.SOS]: PERMISSIONS.EMERGENCY,
  [ALERT_TYPES.ZONE_EXIT]: PERMISSIONS.RECEIVE_ALERTS,
  [ALERT_TYPES.ZONE_ENTER]: PERMISSIONS.RECEIVE_ALERTS,
  [ALERT_TYPES.LONG_STOP]: PERMISSIONS.RECEIVE_ALERTS,
  [ALERT_TYPES.GPS_LOST]: PERMISSIONS.RECEIVE_ALERTS,
  [ALERT_TYPES.LOW_BATTERY]: PERMISSIONS.RECEIVE_ALERTS,
  [ALERT_TYPES.FALL_DETECTED]: PERMISSIONS.EMERGENCY,
});

/** وضعیت کاربر نسبت به یک محدوده‌ی امن. */
export const ZONE_STATE = Object.freeze({ INSIDE: 'inside', OUTSIDE: 'outside', UNKNOWN: 'unknown' });

export const ZONE_SHAPES = Object.freeze({ CIRCLE: 'circle', POLYGON: 'polygon' });
export const ALL_ZONE_SHAPES = Object.freeze(Object.values(ZONE_SHAPES));

/** رویدادهای WebSocket — نام‌ها بین بک‌اند، وب و موبایل مشترک است. */
export const WS_EVENTS = Object.freeze({
  LOCATION_UPDATE: 'location:update',
  ALERT_NEW: 'alert:new',
  ALERT_READ: 'alert:read',
  SHARING_CHANGED: 'sharing:changed',
  ZONE_STATE: 'zone:state',
  PRESENCE: 'presence',
  SIMULATOR_STATUS: 'simulator:status',
  /** وضعیت اتصال کاربر تحت پایش، برای نشانگر «آنلاین/آفلاین» در سمت مراقب. */
  DEVICE_STATE: 'device:state',
});

/** منبع تولید یک پینگ موقعیت. */
export const PING_SOURCE = Object.freeze({
  DEVICE: 'device',
  SIMULATOR: 'simulator',
  IMPORT: 'import',
});

/** ارائه‌دهنده‌ی موقعیت روی گوشی — برای تفکیک خطای GPS خالص از موقعیت ترکیبی. */
export const LOCATION_PROVIDERS = Object.freeze(['gps', 'fused', 'network', 'passive']);

/** کانال‌های تحویل هشدار. sms در فاز اول استفاده نمی‌شود. */
export const DELIVERY_CHANNELS = Object.freeze({
  WEBSOCKET: 'websocket',
  FCM: 'fcm',
  LOG: 'log',
  SMS: 'sms',
});

export const DELIVERY_STATUS = Object.freeze({
  QUEUED: 'queued',
  SENT: 'sent',
  DELIVERED: 'delivered',
  FAILED: 'failed',
  SKIPPED: 'skipped',
});

/**
 * کنش‌های قابل ثبت در لاگ حسابرسی.
 * فهرست بسته است تا نام‌ها در طول زمان پراکنده نشوند و گزارش‌گیری ممکن بماند.
 */
export const AUDIT_ACTIONS = Object.freeze({
  USER_LOGIN: 'user.login',
  USER_LOGIN_FAILED: 'user.login_failed',
  USER_REGISTER: 'user.register',
  USER_SUSPEND: 'admin.user.suspend',
  USER_ACTIVATE: 'admin.user.activate',
  USER_DELETE: 'admin.user.delete',
  USER_ROLE_CHANGE: 'admin.user.role_change',
  DEVICE_REVOKE: 'admin.device.revoke',
  GUARDIANSHIP_CREATE: 'guardianship.create',
  GUARDIANSHIP_REVOKE: 'guardianship.revoke',
  GUARDIANSHIP_PERMISSIONS: 'guardianship.permissions',
  SHARING_TOGGLE: 'settings.sharing_toggle',
  HISTORY_DELETE: 'location.history_delete',
  SOS_TRIGGER: 'sos.trigger',
});

export const PLATFORMS = Object.freeze(['android', 'ios', 'web']);
