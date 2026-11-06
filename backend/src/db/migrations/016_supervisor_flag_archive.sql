-- Preserve the complete pre-cleanup row for every changed supervisor flag.
CREATE TABLE IF NOT EXISTS supervisor_flag_cleanup_archive (
  guardianship_id UUID PRIMARY KEY,
  original_row JSONB NOT NULL,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
