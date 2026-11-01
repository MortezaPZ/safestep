-- Only explicit field-evaluation fixes count as position-error samples.
-- Raw observed coordinates are intentionally not retained.
CREATE TABLE IF NOT EXISTS location_reference_samples (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  error_m     REAL NOT NULL CHECK (error_m >= 0),
  accuracy_m  REAL NOT NULL CHECK (accuracy_m >= 0),
  valid       BOOLEAN NOT NULL,
  sampled_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_location_reference_samples_time
  ON location_reference_samples(sampled_at DESC);
