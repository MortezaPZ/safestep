-- دقت موقعیت‌یابی طبق پروپوزال: فاصلهٔ نقطهٔ مرجع واقعی تا مختصات ثبت‌شده، به متر.
-- accuracy_m همچنان دقت اعلامی خود GPS است و با error_m عوض نمی‌شود.

ALTER TABLE location_telemetry
  ADD COLUMN IF NOT EXISTS reference_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS reference_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS error_m       REAL;

CREATE TABLE IF NOT EXISTS location_references (
  user_id     UUID        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  label       VARCHAR(120),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- پرسشنامهٔ SUS: ده گویه، هر کدام ۱ تا ۵.
CREATE TABLE IF NOT EXISTS sus_responses (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role         VARCHAR(16) NOT NULL,
  answers      JSONB       NOT NULL,
  score        REAL        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sus_user_time ON sus_responses(user_id, created_at DESC);
