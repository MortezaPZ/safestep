# وضعیت رسیدگی به بازخوردهای ۵۹ تا ۸۵

این گزارش وضعیت شاخه در حال کار است؛ «انجام شد» به تغییر و آزمون محلی بیان‌شده محدود است و به معنی استقرار یا آزمون میدانی نیست. شماره‌ها مطابق فهرست کامل کارفرما هستند. مسیرها نسبت به ریشه مخزن‌اند.

| مورد | وضعیت | شواهد و کار باقی‌مانده |
|---|---|---|
| ۵۹ | مسدود | کد Firebase، ثبت توکن و callback در `mobile/lib/core/push/` و رسید مجاز سرور در `backend/tests/fcm.receipt.test.js` وجود دارد. `notification.outbox.test.js` قرارداد پیام و آزمون‌های موبایل منطق محلی را بررسی می‌کنند. وابستگی‌ها با lockfile حل و debug بدون تنظیمات Firebase ساخته شد؛ پیکربندی Firebase و آزمون گوشی هنوز لازم‌اند. رسید فقط زمان ثبت سروری است، نه اثبات نمایش. |
| ۶۰ | مسدود | راهنما در `docs/deployment/mobile-release-and-container.md` و `docs/mobile-client.md`. سرور عمومی، دامنه HTTPS، کلید امضای انتشار و APK انتشار امضاشده موجود یا تأیید نشده‌اند. ساخت debug آزمایشی در کپی مستقل موفق شد؛ این APK فاقد پیکربندی واقعی Firebase است. |
| ۶۱ | انجام شد | مهاجرت `019_reference_sample_context.sql`، صفحه `mobile/lib/features/evaluation/presentation/evaluation_page.dart` و آزمون‌های `evaluation.reference.test.js` و `evaluation_page_test.dart`؛ نمونه واقعی هنوز باید جمع‌آوری شود. |
| ۶۲ | انجام شد | `backend/src/repositories/evaluationExportRepository.js`، `backend/src/utils/evaluationCsv.js` و `backend/tests/evaluation.export.api.test.js`. برچسب مرجع را از اطلاعات شخصی پاک نگه دارید؛ شناسه‌ها ناشناس‌سازی کامل نیستند. |
| ۶۳ | انجام شد | بازآموزی مشترک روی آرشیو تأییدشده، `docs/evaluation/fall-out-of-fold-scores.csv` با ۴٬۵۰۵ ردیف و پنج انتخاب fold را در `model.json` تولید کرد؛ تعداد، برچسب‌ها و گروه‌بندی ۳۸ فرد کنترل شدند. |
| ۶۴ | انجام شد | API و پایگاه در `backend/src/repositories/locationRepository.js` و مهاجرت ۰۱۴؛ همگام‌سازی در `mobile/lib/features/tracking/data/tracking_intent_sync.dart`. آزمون‌های `tracking.intent.test.js` و `tracking_intent_sync_test.dart`. اجرای میدانی مستقل لازم است. |
| ۶۵ | انجام شد | `web/js/views/history.js` و `backend/tests/web.browser.smoke.test.js` دسترسی و انتخاب کاربر را در Chromium کنترل می‌کنند. |
| ۶۶ | انجام شد | ضریب و توضیح در `backend/scripts/falls/convert_sisfall.js` و `backend/data/falls/README.md`؛ آزمون fixture در `fall.training.test.js` و بازآموزی مشترک با ۷۰ روی داده خام با هش تأییدشده انجام شد. |
| ۶۷ | انجام شد | `backend/scripts/loadtest-helpers.js` و `loadtest-postgres.js` بسته‌شدن سرور و نرخ محقق را اصلاح می‌کنند؛ `loadtest.shutdown.test.js` پاسخ در جریان را می‌آزماید. گزارش `docs/evaluation/load-test-postgres-2026-11-06-isolated-pg17.md`: در PostgreSQL 17 ایزوله، ۳۰۰۰ درخواست SOS در ۶۰ ثانیه و صفر خطای گزارش‌شده؛ در لاگ این اجرا خطای بستن زودهنگام pool دیده نشد. این نتیجه تضمین رفتار در همه شرایط یا آزمون PostgreSQL 16 نیست. |
| ۶۸ | مسدود | اعلان محلی و دکمه‌ها در `mobile/lib/core/push/push_service.dart` و `fall_check_page.dart`؛ آزمون‌های `push_service_test.dart` و `fall_check_page_test.dart`. رفتار کامل در پس‌زمینه و قفل صفحه و رسید هشدار ورودی نیازمند گوشی و FCM واقعی است. |
| ۶۹ | انجام شد | ارسال آخرین موقعیت در `mobile/lib/features/fall/data/fall_repository.dart` و آزمون‌های `fall_repository_test.dart`؛ آزمون روی گوشی واقعی انجام نشده است. |
| ۷۰ | انجام شد | پنجره‌های یکسان در `backend/scripts/falls/convert_sisfall.js` و آزمون `fall.training.test.js`؛ یک اجرای کامل ۴٬۵۰۵ پنجره، مدل جدید و ۴۸ سطر جاروب را تولید کرد. این داده شامل سقوط شبیه‌سازی‌شده است. |
| ۷۱ | انجام شد | پاک‌سازی قله در `mobile/lib/features/fall/data/fall_detector_service.dart` و آزمون `fall_detector_service_test.dart`؛ آزمون حسگر واقعی باقی است. |
| ۷۲ | انجام شد | محدودسازی و تلاش دوباره در `mobile/lib/features/fall/data/fall_request_limiter.dart` و `fall_repository.dart`؛ آزمون‌های detector و repository، از جمله شمارش همه درخواست‌های اولیه و retry در سقف و حفظ شناسه رخداد. |
| ۷۳ | انجام شد | نگهداری رخداد فعال و هماهنگ‌کننده پاسخ در `mobile/lib/features/tracking/presentation/tracking_controller.dart` و `mobile/lib/features/fall/data/fall_response_coordinator.dart`؛ `fall_response_coordinator_test.dart` و `fall_check_page_test.dart`. آزمون دستگاه باقی است. |
| ۷۴ | انجام شد | `backend/src/repositories/adminRepository.js` و `adminService.js` ارسال مجدد کاربر تأییدشده را می‌بندند؛ `admin.integration.test.js` و `mobile/test/document_policy_test.dart`. |
| ۷۵ | انجام شد | مهاجرت‌های ۰۱۶ تا ۰۱۸ و `backend/src/repositories/guardianshipRepository.js`؛ `supervisor.migration.test.js` و `supervisor.reinvite.test.js`. پیش از اجرا یادداشت مهاجرت در راهنمای استقرار بررسی شود. |
| ۷۶ | انجام‌نشده | وابستگی در `backend/Dockerfile` افزوده شده و `docker.import.test.js` بارگذاری را در ساختار حداقلی می‌آزماید؛ ساخت و اجرای ایمیج واقعی به Docker در دسترس نیاز دارد. |
| ۷۷ | انجام شد | `backend/src/app.js`، `backend/src/server.js`، راهنمای استقرار و `backend/tests/cors.origin.test.js`. پیکربندی proxy و HTTPS محیط مقصد همچنان لازم است. |
| ۷۸ | انجام شد | کنترل قبل از migration در `backend/src/db/migrate.js` و `sensitiveDataRepository.js`؛ آزمون `sensitive-key.startup.test.js`. بررسی یک ciphertext تضمین سالم‌بودن همه رکوردها نیست. |
| ۷۹ | انجام شد | `backend/src/repositories/locationRepository.js` و `backend/src/services/locationService.js`؛ `backend/tests/tracking.intent.test.js` بازه، توقف و نرسیدن نخستین پینگ پس از شروع را پوشش می‌دهد. منطق شروع بدون پینگ و توقف همچنین روی PostgreSQL 17 ایزوله بررسی شد. |
| ۸۰ | انجام شد | `web/js/utils/sos-location.js`، `web/js/views/history.js` و `zones.js`؛ `web.sos-location.test.js` و `web.browser.smoke.test.js`. |
| ۸۱ | انجام شد | خروجی جداگانه مدل عمومی و محافظ نمودار در `backend/scripts/falls/train.js`، `backend/scripts/evaluation/export-charts.js` و `synthetic-roc.js`؛ `evaluation.export.test.js` و `fall.training.test.js`. hash آرشیو در README آمده است. |
| ۸۲ | انجام شد | مستندات `docs/mobile-client.md`، `docs/client-delivery-note.md` و `docs/deployment/mobile-release-and-container.md`؛ بسته واقعی و نام فایل‌های آن باید هنگام تحویل کنترل شوند. |
| ۸۳ | انجام شد | هشدار حسگر، سقف شرح و وضعیت مجوز در `fall_detector_service.dart`، `mobile/lib/features/settings/presentation/settings_page.dart` و `mobile/lib/core/push/push_service.dart`؛ آزمون‌های موبایل مرتبط. تأیید سخت‌افزاری باقی است. |
| ۸۴ | انجام شد | سناریوی خاموش بودن اشتراک و دسترسی اضطراری در `backend/tests/sos.integration.test.js`. |
| ۸۵ | انجام شد | محافظ production در `backend/src/db/seed.js` و آزمون ایزوله `backend/tests/seed.production.test.js`. |

## آخرین بررسی‌ها و محدودیت‌ها

- PGlite: در اجرای کامل پس از بازآموزی مدل، ۳۶ فایل و ۲۶۰ آزمون موفق شدند؛ یک آزمون PostgreSQL در این اجرا اجرا نشد (skip) و جداگانه روی PostgreSQL 17 ایزوله موفق بود. تست Chromium نیز در اجرای کامل بود.
- Flutter: `flutter pub get --offline --enforce-lockfile` با کش مجزا موفق شد و سپس `flutter test --no-pub` روی پروژه ۴۵ آزمون موفق داشت. آرشیو ۳۹ وابستگی بازیابی‌شده با هش lockfile و هفت بسته Firebase با هش و محتوای کش تطبیق داده شدند. این نتایج جای ساخت Android/iOS یا آزمون Firebase واقعی را نمی‌گیرد.
- PostgreSQL 16 و Docker در این محیط شناسایی نشدند. بخشی از migrationها و چند سناریو قبلاً روی نمونه ایزوله PostgreSQL 17 بررسی شدند؛ این معادل اجرای کل suite روی PostgreSQL 16 نیست.
- آزمون بار شش سناریو روی PostgreSQL 17.11 ایزوله انجام و گزارش جداگانه آن ذخیره شد؛ این سنجش تحویل واقعی اعلان به گوشی یا استقرار عملیاتی را پوشش نمی‌دهد.
- `backend/tests/migrate.lock.test.js` با PostgreSQL 17 ایزوله، اجرای هم‌زمان دو پردازه و آزادشدن قفل هنگام خطا را بررسی کرد؛ اجرای اول به علت کدگذاری WIN1256 شکست خورد و اجرای بعدی روی پایگاه تازه UTF-8 موفق شد.
- `flutter build apk --debug --no-pub` پس از استفاده از مسیر لاتین به دریافت `flutter_embedding_debug` از سرور رسمی رسید و به‌علت HTTP 403 شکست خورد. `flutter analyze` با خطای سرویس تحلیل شکست خورد؛ تحلیل مستقیم Dart در بخش اعلان فقط پیشنهادهای informational داشت.
- تلاش بعدی ساخت debug با آینه Flutter در مسیر موقت به خطای کش Kotlin و سپس در یک کپی آزمایشی به خطای شناسایی افزونه‌ها رسید؛ هیچ APK حاصل از این تلاش‌ها تأیید نشده است.
- پس از بازسازی فهرست افزونه‌ها در همان کپی مستقل، ساخت debug با آینه Flutter موفق شد؛ `apksigner` امضای Android Debug را با روش v2 تأیید کرد. SHA-256 فایل `46fb91b61fd45aff3d67e43a017bad3f113113b2787ed0c61a18fd56e4dbb4d4` است. این نسخه فاقد فایل پیکربندی واقعی Firebase و امضای انتشار است و آزمایش دستگاه نشده است.
- بررسی manifest همان APK، شناسه بسته `ir.hamghadam.safestep`، مجوز اعلان و سرویس‌های Firebase Messaging را نشان داد؛ وجود سرویس در فایل، فعال‌بودن Firebase یا تحویل اعلان را اثبات نمی‌کند. در Windows و Ubuntu موجود، ابزارهای Docker، Podman و Buildah پیدا نشدند.
- آرشیو محلی SisFall با SHA-256 ثبت‌شده تأیید و بازآموزی شد. پیکربندی و اعتبارنامه Firebase، دامنه و سرور عمومی، کلید امضا و گوشی Android در دسترس نیستند؛ نتیجه واقعی تحویل اعلان یا آزمایش میدانی موجود نیست.
