import 'package:flutter/material.dart';
// SemanticsService و Assertiveness از این ماژول می‌آیند و material آن را
// به‌طور کامل صادر نمی‌کند؛ ایمپورت صریح لازم است.
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_spacing.dart';
import 'accessibility_settings.dart';

/// ابزارهای دسترس‌پذیری.
///
/// ── چرا یک فایل جدا ─────────────────────────────────────────────────────
/// یکی از گروه‌های هدف این محصول نابیناست. دسترس‌پذیری اینجا یک «ویژگی
/// اضافه» نیست که در انتها اضافه شود؛ اگر در هر صفحه دستی و از نو نوشته
/// شود، در نیمی از صفحه‌ها فراموش می‌شود. این فایل، ابزارِ آماده می‌دهد تا
/// راهِ درست، آسان‌ترین راه هم باشد.
class A11y {
  const A11y._();

  /// آیا صفحه‌خوان (TalkBack / VoiceOver) روشن است؟
  ///
  /// برای تصمیم‌های رفتاری استفاده می‌شود، نه برای ساختن دو رابط جدا:
  /// مثلاً وقتی صفحه‌خوان روشن است، ژست «کشیدن برای رفرش» عملاً در دسترس
  /// نیست و باید دکمه‌ی صریح هم وجود داشته باشد.
  static bool screenReaderOn(BuildContext context) =>
      MediaQuery.accessibleNavigationOf(context);

  /// اعلام یک پیام به صفحه‌خوان، بدون آنکه چیزی روی صفحه عوض شود.
  ///
  /// موارد استفاده: «موقعیت ارسال شد»، «اتصال قطع شد»، «هشدار تازه».
  /// کاربر بینا این‌ها را از تغییر رنگ یک نشانگر می‌فهمد؛ کاربر نابینا فقط
  /// از همین اعلام.
  static void announce(BuildContext context, String message) {
    if (message.trim().isEmpty) return;
    SemanticsService.announce(message, Directionality.of(context));
  }

  /// اعلام فوری و پرتکرار — برای رویدادهای بحرانی مثل فعال شدن SOS.
  static void announceAssertive(BuildContext context, String message) {
    if (message.trim().isEmpty) return;
    SemanticsService.announce(
      message,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    );
  }

  /// تضمین حداقل اندازه‌ی هدف لمسی.
  ///
  /// هر عنصر قابل لمسی که ویجت آماده‌ی Material نیست، باید از این عبور کند.
  static Widget tapTarget({
    required Widget child,
    double size = AppSpacing.minTapTarget,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      child: Center(child: child),
    );
  }

  /// پنهان کردن یک عنصر صرفاً تزئینی از صفحه‌خوان.
  ///
  /// آیکونی که کنارش همان معنا به‌صورت متن نوشته شده، اگر برچسب داشته باشد
  /// کاربر نابینا آن را دو بار می‌شنود.
  static Widget decorative(Widget child) =>
      ExcludeSemantics(child: child);

  /// ادغام معنایی یک کارت به یک گره‌ی واحد.
  ///
  /// بدون این، کاربر صفحه‌خوان مجبور است برای عبور از یک کارتِ چهارخطی،
  /// چهار بار انگشت بکشد. با این، کل کارت یک بار و یک‌جا خوانده می‌شود.
  static Widget mergedCard({
    required String label,
    required Widget child,
    String? hint,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: onTap != null,
      container: true,
      child: MergeSemantics(child: child),
    );
  }
}

/// بازخورد لمسی، با احترام به تنظیم کاربر.
///
/// هیچ‌جای اپ نباید مستقیم `HapticFeedback` را صدا بزند: کاربری که لرزش را
/// خاموش کرده، باید همه‌جا خاموش باشد.
class AppHaptics {
  const AppHaptics._();

  static bool _enabled(WidgetRef ref) =>
      ref.read(accessibilityProvider).hapticFeedback;

  /// لمس معمولی — دکمه، سوییچ، انتخاب
  static void tap(WidgetRef ref) {
    if (_enabled(ref)) HapticFeedback.selectionClick();
  }

  /// تأیید یک عملیات موفق
  static void success(WidgetRef ref) {
    if (_enabled(ref)) HapticFeedback.lightImpact();
  }

  /// خطا یا رد شدن عملیات
  static void error(WidgetRef ref) {
    if (_enabled(ref)) HapticFeedback.heavyImpact();
  }

  /// هشدار اضطراری — قوی‌ترین بازخورد موجود.
  /// این یکی حتی اگر کاربر لرزش را خاموش کرده باشد هم اجرا می‌شود:
  /// تأییدِ اینکه «درخواست کمک واقعاً ثبت شد» از ترجیح ظاهری مهم‌تر است.
  static void emergency() {
    HapticFeedback.heavyImpact();
  }
}
