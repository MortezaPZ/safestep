-- فاز دوم: شکل چندضلعی، زمان‌بندی محدوده، هشدار ماندگاری، پینگ تطبیقی.

ALTER TABLE safe_zones
  ADD COLUMN IF NOT EXISTS shape VARCHAR(8) NOT NULL DEFAULT 'circle';

ALTER TABLE safe_zones DROP CONSTRAINT IF EXISTS safe_zones_shape_check;
ALTER TABLE safe_zones ADD CONSTRAINT safe_zones_shape_check
  CHECK (shape IN ('circle', 'polygon'));

ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS polygon JSONB;
ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS schedule JSONB;
ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS alert_on_enter BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS alert_on_exit BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS dwell_alert_minutes INTEGER;

ALTER TABLE safe_zones DROP CONSTRAINT IF EXISTS safe_zones_dwell_check;
ALTER TABLE safe_zones ADD CONSTRAINT safe_zones_dwell_check
  CHECK (dwell_alert_minutes IS NULL OR dwell_alert_minutes BETWEEN 1 AND 1440);

ALTER TABLE zone_states ADD COLUMN IF NOT EXISTS last_dwell_alert_at TIMESTAMPTZ;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS adaptive_ping_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS ping_interval_stationary_sec INTEGER NOT NULL DEFAULT 120;

ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_stationary_ping_check;
ALTER TABLE user_settings ADD CONSTRAINT user_settings_stationary_ping_check
  CHECK (ping_interval_stationary_sec BETWEEN 30 AND 1800);

ALTER TABLE notification_outbox
  ADD COLUMN IF NOT EXISTS recipient_channel_meta JSONB;
