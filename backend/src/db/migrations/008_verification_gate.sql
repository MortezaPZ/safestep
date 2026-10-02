-- تا مدیر مدارک را تأیید نکند، قابلیت‌های مراقبتی قفل می‌مانند.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS verification_status VARCHAR(16) NOT NULL DEFAULT 'unverified';

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_verification_status_check;
ALTER TABLE users ADD CONSTRAINT users_verification_status_check
  CHECK (verification_status IN ('unverified', 'pending', 'verified', 'rejected'));

-- حساب‌های نمونهٔ دمو از قبل کامل‌اند و نباید قفل شوند.
UPDATE users
   SET verification_status = 'verified'
 WHERE phone IN ('09121110001', '09121110002', '09121110003', '09121110009');
