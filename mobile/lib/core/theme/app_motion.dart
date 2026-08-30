import 'package:flutter/material.dart';

/// زمان‌بندی و منحنی انیمیشن‌ها.
///
/// ── قاعده‌ی حرکت در این محصول ───────────────────────────────────────────
/// انیمیشن باید «جهت» را توضیح دهد، نه اینکه خودش دیده شود. هر حرکتی که
/// کاربر متوجهش شود، یعنی زیادی طولانی بوده است. سقف ما ۳۰۰ میلی‌ثانیه است
/// و بیشترِ گذارها زیر ۲۰۰.
///
/// ── و چرا قابل خاموش شدن است ────────────────────────────────────────────
/// سیستم‌عامل گزینه‌ی «کاهش حرکت» دارد و بعضی کاربران — از جمله افراد دچار
/// سرگیجه و حساسیت دهلیزی — آن را روشن می‌کنند. `MediaQuery.disableAnimations`
/// همان پرچم است و ما به آن احترام می‌گذاریم: در آن حالت مدت‌ها صفر می‌شوند
/// و گذارها آنی اتفاق می‌افتند.
class AppMotion {
  const AppMotion._();

  static const Duration instant = Duration.zero;

  /// بازخورد فوری لمس، تغییر رنگ، ریپل
  static const Duration fast = Duration(milliseconds: 120);

  /// گذار پیش‌فرض: ظاهر شدن کارت، باز شدن پنل
  static const Duration normal = Duration(milliseconds: 220);

  /// گذار بین صفحه‌ها
  static const Duration page = Duration(milliseconds: 280);

  /// انیمیشن‌های حالت‌دار و تکرارشونده (نبضِ دکمه‌ی اضطراری)
  static const Duration pulse = Duration(milliseconds: 1400);

  /// منحنی پیش‌فرض — شتاب سریع، توقف نرم
  static const Curve curve = Curves.easeOutCubic;

  /// برای عناصری که وارد صفحه می‌شوند
  static const Curve enter = Curves.easeOutCubic;

  /// برای عناصری که خارج می‌شوند — سریع‌تر، چون کسی منتظر خروجشان نیست
  static const Curve exit = Curves.easeInCubic;

  /// فاصله‌ی زمانی بین ظاهر شدن عناصر پشت سر هم در یک فهرست
  static const Duration stagger = Duration(milliseconds: 45);

  /// مدت مؤثر با در نظر گرفتن تنظیم «کاهش حرکت» سیستم‌عامل.
  ///
  /// همه‌جای اپ باید از این تابع استفاده شود، نه از مقادیر خام بالا.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }

  /// آیا حرکت باید حذف شود؟ برای انیمیشن‌های تکرارشونده‌ای که با مدت صفر
  /// هم معنا ندارند و باید کلاً اجرا نشوند (مثل نبض دکمه‌ی SOS).
  static bool reduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);
}
