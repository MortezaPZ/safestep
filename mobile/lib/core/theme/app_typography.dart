import 'package:flutter/material.dart';

/// مقیاس تایپوگرافی فارسی.
///
/// ── چند نکته که مخصوص فارسی است ────────────────────────────────────────
///
/// ۱) `height` (ارتفاع خط) عمداً سخاوتمندانه است. حروف فارسی زیرنویس و
///    نقطه‌های زیرین دارند (ژ، چ، ی) و با ارتفاع خطِ پیش‌فرضِ لاتین، خطوط
///    به هم می‌چسبند و متن «شلوغ» به نظر می‌رسد.
///
/// ۲) `letterSpacing` صفر است و هرگز مثبت نمی‌شود. فاصله‌گذاری بین حروف در
///    خط فارسی، اتصال حروف را می‌شکند و کلمه را ناخوانا می‌کند — کاری که
///    در لاتین بی‌خطر است، اینجا نتیجه‌ی فاجعه‌بار دارد.
///
/// ۳) وزن‌ها محدود به چهار وزنِ موجود در فایل فونت‌اند. درخواست وزنی که در
///    فونت نیست، باعث می‌شود Flutter وزن مصنوعی بسازد که در فارسی زشت
///    درمی‌آید.
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Vazirmatn';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// ساخت مقیاس متن با رنگ‌های داده‌شده.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    TextStyle style(double size, FontWeight weight, double height, Color color) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
        color: color,
      );
    }

    return TextTheme(
      // تیتر بزرگ صفحه‌های خوش‌آمد
      displaySmall: style(30, bold, 1.5, primary),

      // عنوان صفحه
      headlineMedium: style(24, bold, 1.5, primary),
      headlineSmall: style(20, semiBold, 1.5, primary),

      // عنوان کارت و بخش
      titleLarge: style(18, semiBold, 1.55, primary),
      titleMedium: style(16, semiBold, 1.6, primary),
      titleSmall: style(14, medium, 1.6, secondary),

      // متن اصلی
      bodyLarge: style(16, regular, 1.75, primary),
      bodyMedium: style(14, regular, 1.8, secondary),
      bodySmall: style(12, regular, 1.8, secondary),

      // برچسب دکمه و چیپ
      labelLarge: style(16, semiBold, 1.4, primary),
      labelMedium: style(13, medium, 1.5, secondary),
      labelSmall: style(11, medium, 1.5, secondary),
    );
  }

  /// سبک عددی — برای نمایش اعداد لاتین در جایی که فارسی‌سازی نمی‌خواهیم
  /// (مثل کد دعوت که باید رقم‌به‌رقم خوانده و تایپ شود).
  static const TextStyle mono = TextStyle(
    fontFamily: fontFamily,
    fontWeight: bold,
    fontSize: 28,
    // تنها جایی که فاصله‌ی حرفی مثبت مجاز است: رشته‌ای از ارقام مجزا که
    // اصلاً به هم متصل نمی‌شوند و جدا بودنشان به خواندن کمک می‌کند.
    letterSpacing: 8,
    height: 1.4,
  );
}
