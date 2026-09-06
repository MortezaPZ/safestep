# نوتیفیکیشن: WebSocket و FCM HTTP v1

ارسال هشدار دو مسیر موازی دارد:

- اپ باز: رویداد `alert:new` و `notification:push` روی WebSocket، بدون انتظار FCM.
- اپ بسته: صف `notification_outbox` و ارسال تکی به `https://fcm.googleapis.com/v1/projects/{id}/messages:send`.

API قدیمی Server Key در ۲۰۲۴ بسته شد؛ این پروژه دیگر `FCM_SERVER_KEY` ندارد.

## فعال‌سازی

1. در کنسول Firebase یک پروژه بسازید و Cloud Messaging را روشن کنید.
2. حساب سرویس با نقش Firebase Cloud Messaging API Admin بسازید و JSON را در مسیری خارج از git بگذارید.
3. در `backend/.env`:

```
NOTIFICATION_DRIVER=auto
FCM_SERVICE_ACCOUNT_PATH=C:\secrets\safestep-fcm.json
FCM_PROJECT_ID=
```

اگر `FCM_PROJECT_ID` خالی باشد از فیلد `project_id` داخل JSON خوانده می‌شود. جایگزین: `FCM_SERVICE_ACCOUNT_JSON` (JSON خام یا base64).

4. برای اندروید فایل `google-services.json` را در `mobile/android/app/` بگذارید (این فایل gitignore است). پلاگین Gradle فقط اگر فایل موجود باشد اعمال می‌شود؛ بدون آن بیلد دیباگ سبز می‌ماند و پوش خاموش است.

5. سلامت: `GET /health` باید `notifications.fcmConfigured: true` نشان دهد. تب «صف نوتیفیکیشن» در پنل ادمین ردیف‌های pending/sent/abandoned را نشان می‌دهد.

## راستی‌آزمایی این مخزن

ارسال واقعی به گوگل در تست‌ها با `fetch` و `GoogleAuth` جعلی است. بدون پروژه Firebase کاربر، تحویل انتهابه‌انتها روی دستگاه واقعی تأیید نشده است.
