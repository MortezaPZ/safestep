-- فاز سوم: ستون‌های تشخیص سقوط، بازخورد و تنظیمات شمارش معکوس.

ALTER TABLE fall_events
  ADD COLUMN IF NOT EXISTS detection_source VARCHAR(16) NOT NULL DEFAULT 'device';

ALTER TABLE fall_events DROP CONSTRAINT IF EXISTS fall_events_source_check;
ALTER TABLE fall_events ADD CONSTRAINT fall_events_source_check
  CHECK (detection_source IN ('device', 'manual', 'simulator', 'watchdog'));

ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS svm_margin REAL;
ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS knn_agree REAL;
ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS feedback_at TIMESTAMPTZ;
ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS responded_within_sec INTEGER;
ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS classified_as_fall BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE fall_events ADD COLUMN IF NOT EXISTS client_event_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_fall_events_client
  ON fall_events(user_id, client_event_id)
  WHERE client_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_fall_events_feedback ON fall_events(user_feedback);
CREATE INDEX IF NOT EXISTS idx_fall_events_pending
  ON fall_events(classified_as_fall, user_feedback, detected_at);

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS fall_detection_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS fall_countdown_sec INTEGER NOT NULL DEFAULT 30;

ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_fall_countdown_check;
ALTER TABLE user_settings ADD CONSTRAINT user_settings_fall_countdown_check
  CHECK (fall_countdown_sec BETWEEN 10 AND 120);
