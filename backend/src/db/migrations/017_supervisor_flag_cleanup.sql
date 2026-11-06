-- When multiple active supervisors exist, retain the most recently created
-- relationship, using ID as a deterministic tie-breaker; archive every change.
WITH ranked AS (
  SELECT id, status, to_jsonb(g) AS original_row,
         ROW_NUMBER() OVER (PARTITION BY primary_user_id, status
                            ORDER BY created_at DESC, id ASC) AS position
    FROM guardianships g WHERE is_main_supervisor = TRUE
), changed AS (
  SELECT * FROM ranked WHERE status <> 'active' OR position > 1
)
INSERT INTO supervisor_flag_cleanup_archive (guardianship_id, original_row)
SELECT id, original_row FROM changed ON CONFLICT (guardianship_id) DO NOTHING;

WITH ranked AS (
  SELECT id, status,
         ROW_NUMBER() OVER (PARTITION BY primary_user_id, status
                            ORDER BY created_at DESC, id ASC) AS position
    FROM guardianships WHERE is_main_supervisor = TRUE
)
UPDATE guardianships SET is_main_supervisor = FALSE
 WHERE id IN (SELECT id FROM ranked WHERE status <> 'active' OR position > 1);
