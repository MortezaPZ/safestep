ALTER TABLE notification_outbox
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;

-- Keep the removed delivery attempts so the uniqueness cleanup is reversible.
CREATE TABLE IF NOT EXISTS alert_delivery_dedup_archive (
  original_id  BIGINT PRIMARY KEY,
  original_row JSONB NOT NULL,
  archived_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

WITH ranked AS (
  SELECT id, to_jsonb(d) AS original_row, ROW_NUMBER() OVER (
    PARTITION BY alert_id, recipient_user_id, channel
    ORDER BY created_at DESC, id DESC
  ) AS row_number
  FROM alert_deliveries d
)
INSERT INTO alert_delivery_dedup_archive (original_id, original_row)
SELECT id, original_row
FROM ranked
WHERE row_number > 1
ON CONFLICT (original_id) DO NOTHING;

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
