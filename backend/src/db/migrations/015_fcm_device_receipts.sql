-- A receipt records the server's first receipt of a device callback. It does
-- not establish when Android displayed the notification or trust device clocks.
CREATE TABLE IF NOT EXISTS fcm_device_receipts (
  alert_id UUID NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (alert_id, recipient_user_id)
);
