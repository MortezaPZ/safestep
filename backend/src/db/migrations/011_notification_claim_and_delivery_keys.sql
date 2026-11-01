ALTER TABLE notification_outbox
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY alert_id, recipient_user_id, channel
    ORDER BY created_at DESC, id DESC
  ) AS row_number
  FROM alert_deliveries
)
DELETE FROM alert_deliveries d
 USING ranked r
 WHERE d.id = r.id AND r.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_alert_deliveries_target_channel
  ON alert_deliveries(alert_id, recipient_user_id, channel);
