# تأیید شماره با پیامک

درایور با `SMS_DRIVER` انتخاب می‌شود: `console` (پیش‌فرض، کد در لاگ)، `kavenegar`، یا `ghasedak`.

متغیرها: `SMS_API_KEY`، `SMS_TEMPLATE`، `PHONE_VERIFICATION_REQUIRED` (پیش‌فرض خاموش تا دمو و تست‌های موجود نشکنند).

مسیرها: `POST /auth/otp/request`، `POST /auth/otp/verify`، و `verificationToken` اختیاری در ثبت‌نام.

`GET /config/public` به کلاینت می‌گوید آیا مرحلهٔ OTP لازم است.
