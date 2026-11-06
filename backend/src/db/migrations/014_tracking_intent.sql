-- Tracking intent is distinct from location-sharing permissions.
-- Existing installations retain the previous watchdog behavior.
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS tracking_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS tracking_started_at TIMESTAMPTZ;
