# گام ۲ — تکمیل بک‌اند، نقش ادمین و لایه‌ی سنجش

این سند فهرست تغییرات گام دوم و مرجع سریع endpointهای تازه است. مستند کامل OpenAPI در گام ۷ تولید می‌شود.

---

## ۱. فایل‌های جدید

| فایل | نقش |
|---|---|
| `src/middleware/requestLog.js` | شناسه‌ی درخواست، زمان‌سنجی، ثبت الگوی مسیر |
| `src/services/telemetryService.js` | بافر نوشتن سنجه‌ها + هش IP |
| `src/services/auditService.js` | ثبت لاگ حسابرسی با پاک‌سازی اجباری داده‌ی حساس |
| `src/services/adminService.js` | منطق پنل مدیریت |
| `src/repositories/logRepository.js` | نوشتن و تجمیع لاگ‌ها و سنجه‌ها |
| `src/repositories/adminRepository.js` | کوئری‌های سرتاسری کاربران و دستگاه‌ها |
| `src/controllers/adminController.js` | کنترلرهای پنل |
| `src/db/createAdmin.js` | ساخت اولین ادمین از خط فرمان |
| `tests/admin.integration.test.js` | ۲۸ تست جدید |

## ۲. فایل‌های تغییریافته

- `middleware/auth.js` — `requireAdmin`، خواندن نقش و وضعیت از دیتابیس با حافظه‌ی نهانِ ۱۵ ثانیه‌ای
- `middleware/error.js` — گذاشتن `errorCode` برای لاگ درخواست
- `services/authService.js` — ثبت آخرین ورود، لاگ حسابرسی، پیام روشن برای حساب معلق
- `services/locationService.js` — تله‌متری هر پینگ + `ingestBatch`
- `services/alertService.js` — ثبت تحویل هشدار و لحظه‌ی مشاهده
- `repositories/locationRepository.js` — درج دسته‌ای و بی‌اثرسازی تکرار
- `repositories/deviceRepository.js` — `installId`، نسخه‌ی اپ، ابطال دستگاه
- `repositories/userRepository.js` — کلیدهای تنظیمات فاز اول، `updatePassword`
- `app.js` · `server.js` — نصب میان‌افزار لاگ، تخلیه‌ی بافر هنگام خاموش شدن

---

## ۳. endpointهای تازه

### موقعیت و پیکربندی

| متد | مسیر | توضیح |
|---|---|---|
| `POST` | `/api/v1/locations/batch` | تخلیه‌ی صف آفلاین، تا ۲۰۰ نقطه؛ تکراری‌ها بی‌صدا رد می‌شوند |
| `GET` | `/api/v1/config/client` | بازه‌ی پینگ، آستانه‌ها، نام رویدادهای WebSocket، پرچم فازهای بعد |

`POST /locations/ping` فیلدهای اختیاری تازه گرفت: `clientUuid`، `provider`، `isQueuedReplay`.
`POST /devices` فیلدهای تازه گرفت: `installId`، `appVersion`، `osVersion`، `model`.
`PATCH /settings` کلیدهای تازه گرفت: `pingIntervalSec`، `backgroundTrackingEnabled`، `textScale`، `highContrastEnabled`، `hapticFeedbackEnabled`، `locationRetentionDays`.

### پنل مدیریت — همه پشت `requireAuth` + `requireAdmin`

| متد | مسیر |
|---|---|
| `GET` | `/api/v1/admin/overview` |
| `GET` | `/api/v1/admin/users` (`search`, `role`, `status`, `limit`, `offset`) |
| `GET` | `/api/v1/admin/users/:id` |
| `POST` | `/api/v1/admin/users/:id/suspend` |
| `POST` | `/api/v1/admin/users/:id/activate` |
| `DELETE` | `/api/v1/admin/users/:id` (حذف نرم) |
| `PATCH` | `/api/v1/admin/users/:id/role` |
| `GET` | `/api/v1/admin/devices` |
| `POST` | `/api/v1/admin/devices/:id/revoke` |
| `GET` | `/api/v1/admin/logs/requests` |
| `GET` | `/api/v1/admin/logs/audit` |
| `POST` | `/api/v1/admin/logs/purge` |
| `GET` | `/api/v1/admin/metrics` |

**آنچه عمداً وجود ندارد:** هیچ مسیری که به ادمین اجازه‌ی دیدن موقعیت یا تاریخچه‌ی مسیر کاربران را بدهد. یک تست اختصاصی این را تضمین می‌کند؛ اگر روزی چنین مسیری اضافه شود، آن تست می‌شکند.

---

## ۴. سه تصمیم که ارزش توضیح دارند

**الف) وضعیت حساب از دیتابیس خوانده می‌شود، نه از توکن.**
توکن access پانزده دقیقه اعتبار دارد. اگر فقط به آن تکیه می‌کردیم، حسابی که ادمین همین حالا معلق کرده تا ربع ساعت به کار خود ادامه می‌داد. یک کوئری سبک با حافظه‌ی نهانِ ۱۵ ثانیه‌ای اضافه شد: حداکثر تأخیر اثرگذاریِ تعلیق ۱۵ ثانیه است، و پس از هر تغییرِ وضعیت یا نقش، همان لحظه بی‌اعتبار می‌شود. تست، بی‌اثر شدنِ فوریِ توکن قبلی را اثبات می‌کند.

**ب) لاگ سنجش بافر می‌شود.**
میان‌افزار لاگ روی مسیر داغِ هر درخواست است. یک `INSERT` اضافه به‌ازای هر درخواست، به همان عددی اضافه می‌کرد که قرار است اندازه بگیریم. رکوردها در حافظه جمع و هر ۵ ثانیه دسته‌ای نوشته می‌شوند. بافر سقف دارد و خطای نوشتن لاگ هرگز به کاربر نمی‌رسد — ابزار اندازه‌گیری حق ندارد سرویس را از کار بیندازد.

**ج) در ارسال دسته‌ای، فقط جدیدترین نقطه وارد خط لوله‌ی هشدار می‌شود.**
دسته معمولاً دقایقی از حرکتِ گذشته است. اگر موتور Geofence روی تک‌تکشان اجرا شود، کاربری که نیم‌ساعت پیش بیرون رفته و برگشته، همین حالا چند هشدارِ منقضی تولید می‌کند. تاریخچه کامل ذخیره می‌شود، اما وضعیتِ لحظه‌ای فقط از آخرین نقطه محاسبه می‌گردد.

---

## ۵. اجرا و تأیید

```bash
cd safestep/backend && npm install && npm run migrate
```

ساخت اولین ادمین (هیچ مسیر APIای برای این کار وجود ندارد):

```bash
npm run create:admin -- --phone 09121234567 --name "مدیر سامانه"
```

رمز تصادفی یک بار روی ترمینال چاپ می‌شود. برای رمز دلخواه، `--password` را اضافه کنید.

```bash
npm test
```

**وضعیت فعلی: ۱۱۱ تست، همگی سبز** (۸۳ تست قبلی + ۲۸ تست تازه). هیچ‌کدام از تست‌های قبلی نیاز به تغییر نداشتند — یعنی هیچ قرارداد موجودی شکسته نشده است.
