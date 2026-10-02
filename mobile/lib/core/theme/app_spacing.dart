/// فاصله‌ها، شعاع گوشه‌ها و اندازه‌های ثابت.
///
/// مقیاس ۴ واحدی: هر فاصله مضربی از ۴ است. نتیجه‌اش این است که صفحه‌ها
/// خودبه‌خود هم‌تراز درمی‌آیند، بدون آنکه کسی مجبور باشد عددها را چشمی
/// تنظیم کند.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// حاشیه‌ی افقی استاندارد صفحه‌ها
  static const double pageH = 20;

  /* ───────────────────── شعاع گوشه ───────────────────── */

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusPill = 999;

  /* ───────────────────── اندازه‌های لمسی ───────────────────── */

  /// حداقل اندازه‌ی هدف لمسی.
  ///
  /// راهنمای مواد ۴۸ و اپل ۴۴ می‌گوید؛ ما ۵۶ گرفته‌ایم. دلیلش کاربر هدف
  /// است: فرد سالمند با لرزش دست یا کاربری که با TalkBack و کورکورانه لمس
  /// می‌کند، به حاشیه‌ی خطای بیشتری نیاز دارد. هزینه‌اش کمی فضای بیشتر است
  /// که در این محصول اهمیتی ندارد — صفحه‌ها عمداً کم‌عنصرند.
  static const double minTapTarget = 56;

  /// ارتفاع دکمه‌ی اصلی
  static const double buttonHeight = 56;

  /// قطر دکمه‌ی اضطراری. بزرگ است تا با انگشت پیدا شود،
  /// ولی نباید کارت‌های بالای صفحه را بپوشاند.
  static const double sosButtonSize = 112;

  /// ارتفاع نوار ناوبری پایین
  static const double navBarHeight = 72;
}
