-- This transactional index can block writes; deploy during a planned window.
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_main_supervisor
  ON guardianships(primary_user_id)
  WHERE status = 'active' AND is_main_supervisor = TRUE;
