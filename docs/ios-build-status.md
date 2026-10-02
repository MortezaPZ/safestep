# ساخت iOS — وضعیت واقعی و شکاف‌های برطرف‌شده

**وضعیت:** ساخت واقعی انجام نشده است.

**دلیل دقیق:** این ماشین ویندوز است و Xcode روی آن وجود ندارد (Xcode فقط روی
macOS اجرا می‌شود). بدون آن نه `xcodebuild` و نه `codesign` در دسترس‌اند و
هیچ IPA واقعی نمی‌تواند ساخته شود. هیچ IPA‌ای جعل نشد و هیچ‌کجا ادعا نشده
که کامپایل شده است.

**چیزی که انجام شد:** شکاف‌های مشخصی در کد فلاتر که ساخت iOS را می‌شکستند
برطرف شد. این موارد از نظر فنی قطعی بودند — یعنی اپ روی iOS یا کرش
می‌کرد، یا قابلیت اصلی‌اش را از دست می‌داد:

## ۱. کلیدهای مورد نیاز Info.plist وجود نداشتند — اصل شکاف

فایل `ios/Runner/Info.plist` هیچ کلید مربوط به مکان، سنسور یا پس‌زمینه
نداشت. بدون این‌ها:

- `Geolocator` روی iOS **هیچ اجازه‌ای نمی‌گیرد** و درخواست موقعیت با خطای
  `kCLAuthorizationStatusDenied` رد می‌شود → ردیابی، هشدار خروج و SOS همگی
  از کار می‌افتادند. این یک شکاف کاملاً قطعی بود، نه تنظیمات زیبایی.
- `sensors_plus` بدون `NSMotionUsageDescription` در نخستین خواندن حسگر کرش
  می‌کند.
- `flutter_local_notifications` بدون `UIBackgroundModes` نمی‌توانست هشدارها
  را در پس‌زمینه نشان دهد.
- `url_launcher` بدون `LSApplicationQueriesSchemes` نمی‌توانست تماس
  `tel:` را از صفحهٔ هشدار شماره‌گیری کند (فقط در اندروید کار می‌کرد).

این کلیدها اضافه شدند (`ios/Runner/Info.plist`):

| کلید | چرا |
|---|---|
| `NSLocationWhenInUseUsageDescription` | اجازهٔ مکان در حین استفاده — اجباری برای `Geolocator` روی iOS |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | اجازهٔ دائمی — پایهٔ اشتراک موقعیت و `location` background mode |
| `NSMotionUsageDescription` | `sensors_plus` شتاب‌سنج/ژیروسکوپ را می‌خواند؛ بدون این کلید کرش می‌کند |
| `UIBackgroundModes` = `fetch`, `location`, `remote-notification` | ارسال موقعیت زنده و دریافت هشدار در پس‌زمینه |
| `LSApplicationQueriesSchemes` = `https`, `tel` | `url_launcher` برای باز کردن لینک و شماره‌گیری از صفحهٔ هشدار |
| `UIRequiresPersistentWiFi` = false | رفتار پیش‌فرض صحیح |

## ۲. صف پس‌زمینه‌ی iOS پایدار نیست (شکاف واقعی دوم)

این مسئله یک محدودیت پلتفرمی است، نه یک باگ در کد، ولی باید ثبت شود:

`flutter_foreground_task` یک سرویس اعلان دائمی روی iOS ارائه نمی‌دهد. کد
این موضوع را درست مدیریت می‌کند — `_startForegroundService()` با
`if (!defaultTargetPlatform.isAndroidLike) return;` محدود شده. یعنی روی
iOS هیچ اعلان «هم‌قدم فعال است» نشان داده نمی‌شود و iOS پس از حدود ۳۰
ثانیهٔ پردازش پس‌زمینه، موقعیت را متوقف می‌کند.

**چرا این فعلاً قابل قبول است:** اپ روی iOS وقتی باز است یا
`background location` مجاز است کار می‌کند. `UIBackgroundModes: location`
که اضافه شد، عمر پس‌زمینه را افزایش می‌دهد. ولی برای ردیابی واقعاً
پایدار در iOS، به `BGTaskScheduler` (پلتفرم iOS بومی) نیاز است.

**این پیاده‌سازی نشد.** ثبت `BGTaskScheduler` نیازمند کد Swift واقعی در
`AppDelegate.swift` به همراه `BGTaskSchedulerPermittedIdentifiers` در
Info.plist و یک قابلیت `background-processing` است. این کار فقط روی
macOS با امکان تست روی دستگاه واقعی معنادار است — نوشتن کد Swift که
نمی‌توانستیم حتی آن را کامپایل کنیم، نقطهٔ ضعفی بود. فقط یک کامنت در
`AppDelegate.swift` گذاشته شد تا این شکاف برای توسعه‌دهندهٔ بعدی ثبت
بماند.

## ۳. لیست نهایی کارهای iOS برای اجرای واقعی

این موارد برای نخستین آرشیوipa واقعی لازم است و هیچ‌کدام روی این ویندوز
امکان‌پذیر نیستند:

1. **macOS با Xcode 15+** — برای `xcodebuild`.
2. **حساب توسعه‌دهندهٔ اپل** — برای کد-ساین کردن و TestFlight.
3. **گواهی توسعه/توزیع + Provisioning Profile** — `CODE_SIGN_STYLE` روی
   `Automatic` است.
4. **مرحلهٔ `pod install`** — اولین بار باید روی mac انجام شود.
5. **آیکون و لانچر صحیح iOS** — `Assets.xcassets` ایمپورت‌شده‌ی پیش‌فرضِ
   فلاتر هنوز در جای خود است و باید با آیکون‌های واقعی پروژه جایگزین شود.
6. **تأیید `NSLocationAlwaysAndWhenInUseUsageDescription`** توسط اپل
   هنگام بررسی اپ — برای این نوع اپ، اپل این درخواست را موقتاً رد می‌کند
   مگر اینکه دلیلی روشن در متن برگه‌ی تأیید داده شود.
7. **App Store Connect listing** — اسکرین‌شات‌ها، شرح، و رأی سنتی.
8. **مرور دستی**: `NSMotionUsageDescription` و `location` background mode
   باعث بررسیٔ دستی توسط اپل می‌شوند.

## دستور ساخت (وقتی Xcode در دسترس بود)

```bash
cd mobile
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  --no-codesign   # فقط برای تست محلی
```

برای انتشار واقعی، `--no-codesign` باید حذف شود و یک حساب توسعه‌دهنده
وصل گردد. سپس:

```bash
xcrun altool --upload-app --type ios -f build/ios/ipa/SafeStep.ipa \
  --apiKey <APPLE_API_KEY> --apiIssuer <APPLE_API_ISSUER>
```

## جمع‌بندی

- **آیا IPA ساخته شد؟** خیر.
- **آیا شکاف‌های کد فلاتر برطرف شد؟** بله — کلیدهای Info.plist که بدون
  آن‌ها اپ روی iOS از کار می‌افتاد، اضافه شدند.
- **آیا اپ بدون این کار روی iOS کار می‌کرد؟** خیر — بدون
  `NSLocationWhenInUseUsageDescription` اپ اجازهٔ مکان نمی‌گرفت و کل
  کارکرد اصلی آن از دست می‌رفت.
