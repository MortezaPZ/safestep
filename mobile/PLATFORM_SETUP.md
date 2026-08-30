# پیکربندی سکو — لازم پیش از اولین اجرا

پس از اجرای `flutter create`، پوشه‌های `android/` و `ios/` ساخته می‌شوند.
این سند می‌گوید دقیقاً چه چیزی باید در آن‌ها اضافه شود.

بدون این تنظیمات، اپ **بیلد می‌شود و اجرا هم می‌شود** — اما نقشه سفید
می‌ماند، اسکنر QR باز نمی‌شود و ردیابی پس‌زمینه کار نمی‌کند، آن هم اغلب
بدون هیچ پیام خطایی. برای همین این سند جداست و کوتاه.

---

## ۱. اندروید

### ۱.۱ مجوزها

فایل: `android/app/src/main/AndroidManifest.xml`
محل: داخل `<manifest>` و **پیش از** `<application>`

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- موقعیت -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<!-- ردیابی وقتی اپ باز نیست. از اندروید ۱۱ به بعد این مجوز را
     نمی‌توان همراه مجوز پایه گرفت؛ باید در یک گفت‌وگوی جداگانه و
     بعد از آن درخواست شود — اپ همین کار را می‌کند. -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

<!-- سرویس Foreground: بدون این، اندروید ظرف چند دقیقه پردازه را
     می‌کشد و ارسال موقعیت قطع می‌شود -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- اسکن کد دعوت -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.VIBRATE" />
```

### ۱.۲ کلید Google Maps

همان فایل، داخل `<application>`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="کلید_شما" />
```

### ۱.۳ سرویس Foreground

همان فایل، داخل `<application>`:

```xml
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

### ۱.۴ حداقل نسخه

فایل: `android/app/build.gradle`

```gradle
android {
    compileSdk 34

    defaultConfig {
        applicationId "ir.safestep"
        minSdk 23        // geolocator و mobile_scanner حداقل ۲۱ می‌خواهند؛
                         // ۲۳ برای مدل مجوزهای زمان اجرا لازم است
        targetSdk 34
    }
}
```

---

## ۲. iOS

### ۲.۱ توضیح مجوزها

فایل: `ios/Runner/Info.plist`
محل: داخل `<dict>`

اپل بدون این متن‌ها اپ را رد می‌کند — و متن باید **دلیل** را بگوید، نه
اینکه چه چیزی می‌خواهد:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>برای اینکه مراقبتان بتواند در صورت نیاز شما را پیدا کند، به موقعیت شما نیاز داریم.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>برای اینکه حتی وقتی اپ باز نیست هم در صورت بروز مشکل مراقبتان مطلع شود، به دسترسی همیشگی به موقعیت نیاز داریم. هر زمان بخواهید می‌توانید خاموشش کنید.</string>

<key>NSCameraUsageDescription</key>
<string>برای اسکن کد دعوت و اتصال به فرد تحت پایش، به دوربین نیاز داریم.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>
```

### ۲.۲ کلید Google Maps

فایل: `ios/Runner/AppDelegate.swift`

```swift
import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("کلید_شما")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### ۲.۳ حداقل نسخه

فایل: `ios/Podfile` — خط اول

```ruby
platform :ios, '12.0'
```

---

## ۳. کلید Google Maps — چطور ساخته می‌شود

۱. در [Google Cloud Console](https://console.cloud.google.com) یک پروژه بسازید
۲. این دو API را فعال کنید: **Maps SDK for Android** و **Maps SDK for iOS**
۳. در بخش Credentials یک API Key بسازید
۴. **کلید را محدود کنید** — به بسته‌ی `ir.safestep` برای اندروید و به
   Bundle ID برای iOS

> کلید بدون محدودیت، اگر در مخزن عمومی بنشیند، یعنی صورت‌حساب Google برای
> شخص دیگری. محدود کردن کلید یک گام اختیاری نیست.

**نشانه‌ی نداشتن کلید:** نقشه یک مستطیل خاکستری خالی است، بدون هیچ خطایی
در کنسول. این متداول‌ترین حیرتِ اولین اجراست.

---

## ۴. آدرس سرور

| محیط | آدرس |
|---|---|
| شبیه‌ساز اندروید | `http://10.0.2.2:4000` (پیش‌فرض) |
| شبیه‌ساز iOS | `http://localhost:4000` |
| گوشی واقعی | IP کامپیوتر در همان شبکه‌ی وای‌فای |

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
```

در شبیه‌ساز اندروید، `localhost` یعنی خودِ شبیه‌ساز نه کامپیوتر میزبان؛
`10.0.2.2` همان میزبان است.

### اتصال HTTP بدون TLS

هر دو سکو به‌طور پیش‌فرض ترافیک رمزنگاری‌نشده را مسدود می‌کنند. برای
**توسعه‌ی محلی** این استثناها لازم است:

**اندروید** — `AndroidManifest.xml` داخل `<application>`:

```xml
android:usesCleartextTraffic="true"
```

**iOS** — `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

> این دو تنظیم فقط برای توسعه‌اند. در استقرار واقعی، سرور پشت HTTPS
> می‌رود و هر دو باید حذف شوند.

---

## ۵. فهرست بررسی پیش از اولین اجرا

- [ ] `flutter create --platforms=android,ios --org ir.safestep --project-name safestep .`
- [ ] `flutter pub get`
- [ ] مجوزهای AndroidManifest اضافه شد
- [ ] سرویس Foreground در AndroidManifest ثبت شد
- [ ] `minSdk 23` تنظیم شد
- [ ] متن مجوزهای Info.plist اضافه شد
- [ ] `UIBackgroundModes` اضافه شد
- [ ] کلید Google Maps در هر دو سکو گذاشته شد و **محدود** شد
- [ ] بک‌اند بالاست (`cd backend && npm start`)
- [ ] آدرس سرور برای محیط اجرا درست است
