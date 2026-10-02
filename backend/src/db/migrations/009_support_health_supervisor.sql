-- پیام پشتیبانی، مشکل سلامت پس از تأیید مدرک، و ناظر اصلی.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS health_condition TEXT;

ALTER TABLE guardianships
  ADD COLUMN IF NOT EXISTS is_main_supervisor BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS support_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender_role VARCHAR(16) NOT NULL CHECK (sender_role IN ('user', 'admin')),
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_user_created
  ON support_messages(user_id, created_at);
