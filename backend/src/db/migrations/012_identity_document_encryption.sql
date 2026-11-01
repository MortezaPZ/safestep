ALTER TABLE identity_documents
  ADD COLUMN IF NOT EXISTS health_condition_encrypted TEXT;
