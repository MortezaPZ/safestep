# زنجیره‌ی ابزار موبایل — نصب روی ویندوز

**تاریخ:** ۱۴ شهریور ۱۴۰۵  
**هدف:** سبز شدن `Flutter` و زنجیره‌ی اندروید در `flutter doctor` تا بیلد `APK` ممکن باشد.

`Chrome` و `Visual Studio` (اپ ویندوز) برای این پروژه لازم نیستند. شبیه‌ساز اندروید اختیاری است؛ معیار پذیرش بیلد دیباگ است نه اجرای شبیه‌ساز.

---

## نسخه‌ها و مسیرها (این ماشین)

| جزء | مقدار |
|---|---|
| سیستم | Windows 11 (build `10.0.28000`) |
| `Node.js` | `v24.18.0` |
| `npm` | `11.16.0` |
| `JDK` | Microsoft OpenJDK `17.0.20.1` در `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot` |
| `JAVA_HOME` | همان مسیر JDK (سطح کاربر) |
| `Flutter` | `3.47.2` کانال `stable`، `C:\src\flutter` |
| `Dart` | `3.13.2` |
| Android SDK | `C:\Android\sdk` (`ANDROID_HOME` و `ANDROID_SDK_ROOT`) |
| پلتفرم اندروید | `android-34` و `android-36` (نسخه‌ی ۳۶ برای `Flutter 3.47`) |
| Build-Tools | `28.0.3`، `34.0.0`، `36.0.0` |
| Platform-Tools | `37.0.1` |
| Command-line tools | `C:\Android\sdk\cmdline-tools\latest` |

خروجی `flutter doctor -v` پس از نصب: `Flutter` و `Android toolchain` سبز؛ `Visual Studio` (توسعه‌ی دسکتاپ ویندوز) قرمز و بی‌ربط به اپ اندروید.

---

## کارهایی که انجام شد

1. نصب JDK با `winget install --id Microsoft.OpenJDK.17`.
2. کلون SDK: `git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter`.
3. افزودن `C:\src\flutter\bin` و `%JAVA_HOME%\bin` به `Path` کاربر.
4. `flutter config --no-analytics` و `flutter config --android-sdk C:\Android\sdk`.
5. دانلود command-line tools گوگل، استخراج به `cmdline-tools\latest`.
6. پذیرش مجوزها با `sdkmanager --licenses` و `flutter doctor --android-licenses`.
7. نصب بسته‌ها با `sdkmanager`: `platform-tools`، `platforms;android-34`، `platforms;android-36`، `build-tools;34.0.0`، `build-tools;36.0.0`، `build-tools;28.0.3`. پوشه‌ی `emulator` از نصب ناقص قبلی باقی است؛ تصویر سیستم `android-34;google_apis;x86_64` در این نشست به‌خاطر حجم و زمان دانلود کامل نشد. ساخت `AVD` انجام نشد.

---

## متغیرهای محیطی کاربر

این‌ها باید در نشست‌های جدید پاورشل هم دیده شوند (پس از بستن و باز کردن ترمینال):

- `JAVA_HOME` = `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot`
- `ANDROID_HOME` = `C:\Android\sdk`
- `ANDROID_SDK_ROOT` = `C:\Android\sdk`
- `Path`: ابتدا `...\jdk-...\bin`، سپس `C:\src\flutter\bin`، سپس `C:\Android\sdk\platform-tools` و `C:\Android\sdk\cmdline-tools\latest\bin`

---

## اگر شبیه‌ساز خواستید (اختیاری)

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
$env:ANDROID_HOME = "C:\Android\sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:Path"
sdkmanager --install "emulator" "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n safestep -k "system-images;android-34;google_apis;x86_64" -d pixel_6 --force
```

اگر شتاب‌دهنده‌ی سخت‌افزاری نباشد، شبیه‌ساز را رد کنید؛ بیلد `flutter build apk --debug` کافی است.
