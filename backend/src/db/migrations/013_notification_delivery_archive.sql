-- Databases that already applied the original 011 migration need the archive
-- table too. Rows removed by that earlier migration cannot be reconstructed
-- here; restore them from a database backup if their history is required.
CREATE TABLE IF NOT EXISTS alert_delivery_dedup_archive (
  original_id  BIGINT PRIMARY KEY,
  original_row JSONB NOT NULL,
  archived_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
