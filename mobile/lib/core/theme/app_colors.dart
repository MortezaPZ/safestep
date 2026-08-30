import 'package:flutter/material.dart';

/// پالت رنگ سامانه.
///
/// ── چرا رنگ‌ها اینجا و نه پراکنده در ویجت‌ها ─────────────────────────────
/// یکی از گروه‌های هدف این محصول، افراد با کم‌بینایی‌اند. حالت «کنتراست بالا»
/// باید بتواند کل پالت را یک‌جا عوض کند؛ این تنها وقتی ممکن است که هیچ
/// `Color(0xFF...)` در بدنه‌ی ویجت‌ها نمانده باشد.
///
/// ── قاعده‌ی کنتراست ────────────────────────────────────────────────────
/// هر جفت متن/زمینه در حالت عادی حداقل نسبت ۴.۵:۱ (استاندارد WCAG AA) و در
/// حالت کنتراست بالا حداقل ۷:۱ (AAA) دارد. رنگ‌های زیر با همین معیار
/// انتخاب شده‌اند، نه بر اساس سلیقه.
class AppColors {
  const AppColors._();

  /* ─────────────────────────── برند ─────────────────────────── */

  /// آبی اصلی — دکمه‌ها، لینک‌ها، وضعیت «همه‌چیز عادی است»
  static const Color primary = Color(0xFF2F6FED);
  static const Color primaryDark = Color(0xFF1E4FB8);
  static const Color primaryLight = Color(0xFFE8F0FE);

  /* ─────────────────────── رنگ‌های معنایی ─────────────────────── */

  /// قرمز فقط و فقط برای وضعیت اضطراری استفاده می‌شود.
  /// اگر قرمز را برای خطای فرم هم به کار ببریم، دکمه‌ی SOS دیگر در چشم
  /// کاربر «آن رنگ خاص» نیست — و این در محصولی که یک دکمه‌اش جان آدم را
  /// نجات می‌دهد، تصمیم بصری نیست، تصمیم ایمنی است.
  static const Color danger = Color(0xFFD32F2F);
  static const Color dangerDark = Color(0xFF9A0007);
  static const Color dangerLight = Color(0xFFFFEBEE);

  /// نارنجی برای هشدارهای غیربحرانی (خروج از محدوده، توقف طولانی)
  static const Color warning = Color(0xFFE65100);
  static const Color warningLight = Color(0xFFFFF3E0);

  /// سبز برای تأیید و وضعیت سالم
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);

  /// خطای فرم — عمداً از قرمزِ اضطراری متمایز است
  static const Color formError = Color(0xFFB3261E);

  /// بنفش، برچسب «حالت نمایش» (داده‌ی شبیه‌سازی‌شده)
  static const Color simulated = Color(0xFF6A3DE8);
  static const Color simulatedLight = Color(0xFFEDE7FB);

  /* ─────────────────────── روشن ─────────────────────── */

  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEFF1F5);
  static const Color lightBorder = Color(0xFFDCE0E7);
  static const Color lightTextPrimary = Color(0xFF14181F);
  static const Color lightTextSecondary = Color(0xFF525A69);
  static const Color lightTextMuted = Color(0xFF79808D);

  /* ─────────────────────── تیره ─────────────────────── */

  static const Color darkBackground = Color(0xFF10141A);
  static const Color darkSurface = Color(0xFF181D26);
  static const Color darkSurfaceAlt = Color(0xFF222833);
  static const Color darkBorder = Color(0xFF313947);
  static const Color darkTextPrimary = Color(0xFFF2F4F8);
  static const Color darkTextSecondary = Color(0xFFB6BDC9);
  static const Color darkTextMuted = Color(0xFF8A93A2);

  /* ───────────────────── کنتراست بالا ───────────────────── */

  /// در این حالت خاکستری‌های ملایم حذف می‌شوند: متن سیاهِ خالص روی سفیدِ
  /// خالص (۲۱:۱) و مرزها پررنگ و ضخیم‌تر. ظاهر «شیک»تر نیست، اما خواندنی‌تر
  /// است — و برای کاربر کم‌بینا، خواندنی بودن تنها معیار است.
  static const Color hcLightBackground = Color(0xFFFFFFFF);
  static const Color hcLightSurface = Color(0xFFFFFFFF);
  static const Color hcLightBorder = Color(0xFF000000);
  static const Color hcLightText = Color(0xFF000000);
  static const Color hcLightPrimary = Color(0xFF0B3FA8);

  static const Color hcDarkBackground = Color(0xFF000000);
  static const Color hcDarkSurface = Color(0xFF000000);
  static const Color hcDarkBorder = Color(0xFFFFFFFF);
  static const Color hcDarkText = Color(0xFFFFFFFF);
  static const Color hcDarkPrimary = Color(0xFF7FB0FF);

  /* ─────────────────────── آواتار ─────────────────────── */

  /// همان پالتی که بک‌اند برای `avatarColor` استفاده می‌کند؛ هم‌راستا نگه
  /// داشتنشان یعنی یک نفر در وب و موبایل یک رنگ دارد.
  static const List<Color> avatars = <Color>[
    Color(0xFF2F6FED),
    Color(0xFF7C4DFF),
    Color(0xFF00897B),
    Color(0xFFF4511E),
    Color(0xFFC2185B),
    Color(0xFF5D4037),
  ];

  /// تبدیل رشته‌ی رنگ سرور («#2F6FED») به Color، با بازگشت امن.
  static Color parse(String? hex, {Color fallback = primary}) {
    if (hex == null) return fallback;
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    return value == null ? fallback : Color(value);
  }
}
