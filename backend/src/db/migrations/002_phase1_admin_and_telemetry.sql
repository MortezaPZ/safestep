-- ═══════════════════════════════════════════════════════════════════════════
--  SafeStep / هم‌قدم — مهاجرت فاز اول
--
--  این مهاجرت سه گروه تغییر می‌آورد:
--    ۱) نقش «ادمین» و چرخه‌ی حیات حساب کاربری (تعلیق، حذف نرم، آخرین ورود)
--    ۲) لایه‌ی تله‌متری و لاگ سرور — ابزار سنجشِ «دقت موقعیت‌یابی» و
--       «تأخیر سیستم» که پروپوزال آن‌ها را متغیر ارزیابی تعریف کرده است
--    ۳) آماده‌سازی شمای فازهای دو و سه (صف نوتیفیکیشن، رویداد سقوط)
--       بدون آن‌که منطقی برایشان در این فاز اجرا شود
--
--  روی هر دو درایور (PostgreSQL شبکه‌ای و PGlite) یکسان اجرا می‌شود.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════ ۱) نقش ادمین و چرخه‌ی حیات حساب ═══════════════════════

-- نقش سوم به CHECK اضافه می‌شود. نامِ محدودیت، همان نامی است که Postgres
-- هنگام تعریفِ درون‌خطی در مهاجرت ۰۰۱ ساخته است.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('primary', 'guardian', 'admin'));

-- وضعیت حساب: ادمین می‌تواند حساب را معلق کند بدون آن‌که داده‌اش را از بین ببرد.
-- حذف واقعی ردیف انجام نمی‌شود چون تاریخچه‌ی هشدارها و لاگ‌ها به آن ارجاع دارند
-- و برای سنجش پایان‌نامه لازم‌اند؛ به‌جای آن حذفِ نرم با deleted_at.
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'active';
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
  CHECK (status IN ('active', 'suspended', 'deleted'));

ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_reason  TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at     TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at        TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_status ON users(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_role   ON users(role, created_at DESC);


-- ═══════════════════════ ۲) دستگاه‌ها: شناسنامه‌ی کامل‌تر ═══════════════════════

-- پنل ادمین باید بتواند «دستگاه‌ها» را مدیریت کند؛ برای این کار به نسخه‌ی اپ،
-- نسخه‌ی سیستم‌عامل و آخرین فعالیتِ واقعی (نه فقط آخرین اتصال) نیاز دارد.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS app_version  VARCHAR(24);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS os_version   VARCHAR(48);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model        VARCHAR(64);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS last_ping_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS revoked_at   TIMESTAMPTZ;

-- شناسه‌ی پایدارِ نصب (از سمت اپ ساخته می‌شود). با آن، ثبت مجدد دستگاه پس از
-- تعویض توکن FCM به‌جای ساختن ردیف تکراری، همان ردیف را به‌روزرسانی می‌کند.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS install_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_devices_user_install
  ON devices(user_id, install_id) WHERE install_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at DESC);


-- ═══════════════════════ ۳) پینگ موقعیت: منشأ و بی‌اثرسازی تکرار ═══════════════════════

-- منبع داده. ستون is_simulated حفظ می‌شود (سازگاری عقب‌رو و صداقتِ حالت نمایش)
-- اما source دقیق‌تر است: با ورود اپ Flutter، «دستگاه واقعی» از «شبیه‌ساز» و
-- «داده‌ی وارداتیِ آزمون» جدا می‌شود.
ALTER TABLE location_pings ADD COLUMN IF NOT EXISTS source VARCHAR(16) NOT NULL DEFAULT 'device';
ALTER TABLE location_pings DROP CONSTRAINT IF EXISTS location_pings_source_check;
ALTER TABLE location_pings ADD CONSTRAINT location_pings_source_check
  CHECK (source IN ('device', 'simulator', 'import'));

-- ارائه‌دهنده‌ی موقعیت روی گوشی: gps | fused | network | passive.
-- برای سنجشِ «دقت موقعیت‌یابی» لازم است؛ بدون آن نمی‌توان خطای GPS خالص را از
-- خطای موقعیتِ ترکیبیِ شبکه تفکیک کرد.
ALTER TABLE location_pings ADD COLUMN IF NOT EXISTS provider VARCHAR(16);

-- آیا این پینگ از صف آفلاینِ اپ و با تأخیر ارسال شده است؟ اگر بله، تأخیرِ
-- سرتاسری آن نباید در میانگین «تأخیر سیستم» وارد شود.
ALTER TABLE location_pings ADD COLUMN IF NOT EXISTS is_queued_replay BOOLEAN NOT NULL DEFAULT FALSE;

-- شناسه‌ی یکتای پینگ که خودِ اپ تولید می‌کند. صف آفلاین ممکن است یک دسته را
-- دو بار بفرستد (قطع اتصال پس از دریافت سرور و پیش از رسیدن پاسخ)؛ این ستون
-- ثبت تکراری را در سطح دیتابیس غیرممکن می‌کند.
ALTER TABLE location_pings ADD COLUMN IF NOT EXISTS client_uuid UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_pings_user_client_uuid
  ON location_pings(user_id, client_uuid) WHERE client_uuid IS NOT NULL;

-- زمان دریافت در سرور، جدا از recorded_at (زمان ثبت روی گوشی).
-- اختلاف این دو، همان «تأخیر سرتاسری» است.
ALTER TABLE location_pings ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;


-- ═══════════════════════ ۴) لاگ درخواست‌های سرور ═══════════════════════

-- پروپوزال «تأخیر سیستم» را با لاگ سمت سرور می‌سنجد. این جدول همان ابزار است:
-- یک ردیف به‌ازای هر درخواست API، با زمان پردازش بر حسب میلی‌ثانیه.
--
-- قاعده‌ی حریم خصوصی: هیچ مختصات، هیچ بدنه‌ی درخواست و هیچ توکنی این‌جا نوشته
-- نمی‌شود. IP هم خام ذخیره نمی‌شود؛ فقط HMAC آن با کلید سرور، تا شمارشِ
-- «چند درخواست از یک مبدأ» ممکن بماند بدون آن‌که خودِ IP قابل بازیابی باشد.
CREATE TABLE IF NOT EXISTS request_logs (
  id             BIGSERIAL   PRIMARY KEY,
  request_id     UUID        NOT NULL,
  user_id        UUID        REFERENCES users(id) ON DELETE SET NULL,
  method         VARCHAR(8)  NOT NULL,
  -- الگوی مسیر (‎/api/v1/alerts/:id‎) نه مسیر واقعی — تا شناسه‌ها در لاگ ننشینند
  route          TEXT        NOT NULL,
  status_code    INTEGER     NOT NULL,
  latency_ms     INTEGER     NOT NULL,
  request_bytes  INTEGER,
  response_bytes INTEGER,
  error_code     VARCHAR(48),
  client_kind    VARCHAR(16),
  app_version    VARCHAR(24),
  ip_hash        VARCHAR(64),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_request_logs_time   ON request_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_route  ON request_logs(route, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_status ON request_logs(status_code, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_user   ON request_logs(user_id, created_at DESC);


-- ═══════════════════════ ۵) تله‌متری ورودِ موقعیت ═══════════════════════

-- جدولِ اختصاصیِ سنجش برای مسیر موقعیت. جدا از request_logs نگه داشته شده
-- چون سؤال پژوهشی متفاوتی می‌پرسد: نه «سرور چقدر طول کشید» بلکه «از لحظه‌ی
-- ثبت مختصات روی گوشی تا لحظه‌ی رسیدنش به سرور چقدر گذشت و دقتش چقدر بود».
CREATE TABLE IF NOT EXISTS location_telemetry (
  id               BIGSERIAL   PRIMARY KEY,
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ping_id          BIGINT      REFERENCES location_pings(id) ON DELETE SET NULL,
  -- زمان ثبت روی گوشی، زمان دریافت در سرور، و اختلافشان
  recorded_at      TIMESTAMPTZ NOT NULL,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  e2e_latency_ms   INTEGER     NOT NULL,
  -- زمان پردازش سمت سرور (ذخیره + موتور Geofence + پخش زنده)
  process_ms       INTEGER,
  accuracy_m       REAL,
  provider         VARCHAR(16),
  source           VARCHAR(16) NOT NULL DEFAULT 'device',
  -- چند پینگ در همان درخواست دسته‌ای ارسال شده بود
  batch_size       INTEGER     NOT NULL DEFAULT 1,
  is_queued_replay BOOLEAN     NOT NULL DEFAULT FALSE,
  -- فاصله‌ی زمانی از پینگ قبلی همان کاربر؛ برای تحلیل پیوستگی ردیابی
  gap_sec          INTEGER,
  battery_level    INTEGER     CHECK (battery_level BETWEEN 0 AND 100),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_loc_telemetry_user_time ON location_telemetry(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_loc_telemetry_time      ON location_telemetry(created_at DESC);


-- ═══════════════════════ ۶) لاگ تحویل هشدار ═══════════════════════

-- «تأخیر سیستم» برای هشدار یعنی: از لحظه‌ی تولید هشدار تا لحظه‌ی رسیدنش به
-- گوشی مراقب. این جدول همان زنجیره را به‌ازای هر گیرنده و هر کانال ثبت می‌کند
-- و در فاز دوم (FCM واقعی) بدون تغییر ساختار، کانال fcm را هم پوشش می‌دهد.
CREATE TABLE IF NOT EXISTS alert_deliveries (
  id                BIGSERIAL   PRIMARY KEY,
  alert_id          UUID        NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  recipient_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel           VARCHAR(16) NOT NULL,
  status            VARCHAR(16) NOT NULL DEFAULT 'queued',
  -- فاصله‌ی زمانی از ساخت هشدار تا واگذاری آن به کانال
  latency_ms        INTEGER,
  attempts          INTEGER     NOT NULL DEFAULT 1,
  error_code        VARCHAR(64),
  delivered_at      TIMESTAMPTZ,
  -- زمانی که مراقب واقعاً هشدار را در اپ باز کرد (اگر باز کرد)
  acknowledged_at   TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE alert_deliveries DROP CONSTRAINT IF EXISTS alert_deliveries_channel_check;
ALTER TABLE alert_deliveries ADD CONSTRAINT alert_deliveries_channel_check
  CHECK (channel IN ('websocket', 'fcm', 'log', 'sms'));

ALTER TABLE alert_deliveries DROP CONSTRAINT IF EXISTS alert_deliveries_status_check;
ALTER TABLE alert_deliveries ADD CONSTRAINT alert_deliveries_status_check
  CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'skipped'));

CREATE INDEX IF NOT EXISTS idx_alert_deliveries_alert ON alert_deliveries(alert_id);
CREATE INDEX IF NOT EXISTS idx_alert_deliveries_time  ON alert_deliveries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alert_deliveries_recip ON alert_deliveries(recipient_user_id, created_at DESC);


-- ═══════════════════════ ۷) لاگ حسابرسی (Audit) ═══════════════════════

-- هر کارِ ادمین و هر تغییر حساسِ کاربر (قطع دسترسی، حذف تاریخچه، خاموش کردن
-- اشتراک‌گذاری) این‌جا ثبت می‌شود. بدون این جدول، «پنل ادمین» یک درِ باز است
-- که هیچ‌کس نمی‌داند از آن چه چیزی رد شده است.
CREATE TABLE IF NOT EXISTS audit_logs (
  id            BIGSERIAL   PRIMARY KEY,
  actor_user_id UUID        REFERENCES users(id) ON DELETE SET NULL,
  actor_role    VARCHAR(16),
  action        VARCHAR(64) NOT NULL,
  entity_type   VARCHAR(32),
  entity_id     TEXT,
  -- بدنه‌ی توضیحی. قاعده: هیچ مختصات و هیچ رازی این‌جا نوشته نمی‌شود.
  metadata      JSONB       NOT NULL DEFAULT '{}'::jsonb,
  ip_hash       VARCHAR(64),
  request_id    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_time   ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor  ON audit_logs(actor_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action, created_at DESC);


-- ═══════════════════════ ۸) آماده‌سازی فاز دوم: صف نوتیفیکیشن ═══════════════════════

-- در فاز اول، آداپتور نوتیفیکیشن مستقیم روی WebSocket تحویل می‌دهد. با فعال
-- شدن FCM در فاز دوم، ارسال باید قابل بازتلاش و قابل پیگیری باشد؛ آن الگو
-- بدون صفِ ماندگار کار نمی‌کند. جدول از همین حالا ساخته می‌شود تا مهاجرتِ
-- فاز دوم فقط کد باشد، نه تغییر شما.
CREATE TABLE IF NOT EXISTS notification_outbox (
  id              BIGSERIAL   PRIMARY KEY,
  user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  alert_id        UUID        REFERENCES alerts(id) ON DELETE CASCADE,
  channel         VARCHAR(16) NOT NULL DEFAULT 'fcm',
  payload         JSONB       NOT NULL DEFAULT '{}'::jsonb,
  status          VARCHAR(16) NOT NULL DEFAULT 'pending',
  attempts        INTEGER     NOT NULL DEFAULT 0,
  last_error      TEXT,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE notification_outbox DROP CONSTRAINT IF EXISTS notification_outbox_status_check;
ALTER TABLE notification_outbox ADD CONSTRAINT notification_outbox_status_check
  CHECK (status IN ('pending', 'sent', 'failed', 'abandoned'));

CREATE INDEX IF NOT EXISTS idx_outbox_pending ON notification_outbox(status, next_attempt_at);


-- ═══════════════════════ ۹) آماده‌سازی فاز سوم: تشخیص سقوط ═══════════════════════

-- هیچ منطق یادگیری ماشینی در فاز اول اجرا نمی‌شود. فقط نوع هشدار و جدول
-- رویداد اضافه می‌شود تا در فاز سوم، خروجیِ مدل SVM/KNN جایی برای نشستن
-- داشته باشد و رابط کاربریِ همین فاز بتواند بدون تغییر آن را نمایش دهد.
ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_type_check;
ALTER TABLE alerts ADD CONSTRAINT alerts_type_check
  CHECK (type IN ('sos','zone_exit','zone_enter','long_stop','gps_lost','low_battery','fall_detected'));

CREATE TABLE IF NOT EXISTS fall_events (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  alert_id      UUID        REFERENCES alerts(id) ON DELETE SET NULL,
  detected_at   TIMESTAMPTZ NOT NULL,
  -- خروجی مدل: نام مدل، نسخه، و درجه‌ی اطمینان
  model_name    VARCHAR(32),
  model_version VARCHAR(16),
  confidence    REAL        CHECK (confidence BETWEEN 0 AND 1),
  -- ویژگی‌های استخراج‌شده از پنجره‌ی شتاب‌سنج/ژیروسکوپ (بردار ویژگی، نه داده‌ی خام)
  features      JSONB       NOT NULL DEFAULT '{}'::jsonb,
  lat           DOUBLE PRECISION CHECK (lat BETWEEN -90  AND 90),
  lng           DOUBLE PRECISION CHECK (lng BETWEEN -180 AND 180),
  -- بازخورد کاربر: آیا واقعاً سقوط بود؟ ورودیِ محاسبه‌ی ماتریس درهم‌ریختگی.
  user_feedback VARCHAR(16),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE fall_events DROP CONSTRAINT IF EXISTS fall_events_feedback_check;
ALTER TABLE fall_events ADD CONSTRAINT fall_events_feedback_check
  CHECK (user_feedback IS NULL OR user_feedback IN ('confirmed', 'false_alarm', 'no_response'));

CREATE INDEX IF NOT EXISTS idx_fall_events_user ON fall_events(user_id, detected_at DESC);


-- ═══════════════════════ ۱۰) تنظیمات: کلیدهای فاز اول ═══════════════════════

-- بازه‌ی ارسال موقعیت از سمت اپ. کاربر باید بتواند بین «دقت بیشتر» و
-- «مصرف باتری کمتر» انتخاب کند؛ این تنظیم از سرور به اپ داده می‌شود تا
-- تغییرش نیاز به انتشار نسخه‌ی جدید اپ نداشته باشد.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS ping_interval_sec INTEGER NOT NULL DEFAULT 30;
ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_ping_interval_check;
ALTER TABLE user_settings ADD CONSTRAINT user_settings_ping_interval_check
  CHECK (ping_interval_sec BETWEEN 5 AND 900);

-- ردیابی در پس‌زمینه (سرویس Foreground در اندروید). خاموشش، انتخابِ خودِ کاربر است.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS background_tracking_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- ترجیحات دسترس‌پذیری. سمت اپ اعمال می‌شود اما سمت سرور نگهداری می‌شود تا
-- کاربر نابینا با تعویض گوشی، تنظیماتش را از دست ندهد.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS text_scale REAL NOT NULL DEFAULT 1.0;
ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_text_scale_check;
ALTER TABLE user_settings ADD CONSTRAINT user_settings_text_scale_check
  CHECK (text_scale BETWEEN 0.8 AND 2.0);

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS high_contrast_enabled   BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS haptic_feedback_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- نگهداشتِ داده: پس از این تعداد روز، پینگ‌های موقعیت پاک می‌شوند.
-- صفر یعنی «نگهداری نامحدود». پیش‌فرض ۹۰ روز، مطابق اصل کمینه‌سازی داده.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS location_retention_days INTEGER NOT NULL DEFAULT 90;
ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_retention_check;
ALTER TABLE user_settings ADD CONSTRAINT user_settings_retention_check
  CHECK (location_retention_days BETWEEN 0 AND 3650);
