-- تأیید شماره با پیامک: جدول OTP.

CREATE TABLE IF NOT EXISTS phone_otps (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone        VARCHAR(16) NOT NULL,
  code_hash    VARCHAR(64) NOT NULL,
  purpose      VARCHAR(16) NOT NULL,
  attempts     INTEGER NOT NULL DEFAULT 0,
  expires_at   TIMESTAMPTZ NOT NULL,
  consumed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE phone_otps DROP CONSTRAINT IF EXISTS phone_otps_purpose_check;
ALTER TABLE phone_otps ADD CONSTRAINT phone_otps_purpose_check
  CHECK (purpose IN ('register', 'login', 'change_phone'));

CREATE INDEX IF NOT EXISTS idx_phone_otps_lookup
  ON phone_otps(phone, purpose, created_at DESC);
