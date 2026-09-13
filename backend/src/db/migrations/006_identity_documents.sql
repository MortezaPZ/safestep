-- مدارک هویتی ارسالی کاربران برای بررسی مدیر سامانه.
CREATE TABLE IF NOT EXISTS identity_documents (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  document_type VARCHAR(40) NOT NULL,
  image_url    TEXT NOT NULL,
  status       VARCHAR(16) NOT NULL DEFAULT 'pending',
  rejection_reason TEXT,
  reviewed_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT identity_documents_status_check CHECK (status IN ('pending', 'approved', 'rejected'))
);

CREATE INDEX IF NOT EXISTS idx_identity_documents_status_created
  ON identity_documents(status, created_at DESC);
