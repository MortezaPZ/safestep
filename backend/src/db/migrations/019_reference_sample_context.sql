-- Existing samples have unknown context; do not invent a label or environment.
ALTER TABLE location_reference_samples ADD COLUMN IF NOT EXISTS environment TEXT;
ALTER TABLE location_reference_samples ADD COLUMN IF NOT EXISTS reference_label TEXT;
ALTER TABLE location_reference_samples DROP CONSTRAINT IF EXISTS location_reference_environment_check;
ALTER TABLE location_reference_samples ADD CONSTRAINT location_reference_environment_check
  CHECK (environment IS NULL OR environment IN ('open', 'urban'));
