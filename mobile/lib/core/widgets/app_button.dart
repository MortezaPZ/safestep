import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accessibility/a11y.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// دکمه‌ی اصلی اپ.
///
/// سه چیزی که در دکمه‌ی خام Flutter نیست و اینجا پیش‌فرض است:
///
/// ۱) **حالت در حال انجام**: هنگام کار، دکمه غیرفعال می‌شود و نشانگر نشان
///    می‌دهد. بدون این، کاربر روی «ثبت‌نام» دو بار می‌زند و دو درخواست
///    می‌رود — که در ثبت SOS یعنی دو هشدار برای مراقب.
///
/// ۲) **بازخورد لمسی** با احترام به تنظیم کاربر.
///
/// ۳) **برچسب معنایی مستقل**: متن دکمه گاهی کوتاه است («ارسال») ولی
///    کاربر صفحه‌خوان باید بداند چه چیزی ارسال می‌شود.
class AppButton extends ConsumerWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.variant = AppButtonVariant.filled,
    this.semanticLabel,
    this.fullWidth = true,
    this.destructive = false,
  });

  final String label;

  /// null یعنی غیرفعال. حالت غیرفعال از حالت «در حال انجام» جداست:
  /// اولی یعنی «هنوز نمی‌شود»، دومی یعنی «دارد انجام می‌شود».
  final VoidCallback? onPressed;

  final IconData? icon;
  final bool loading;
  final AppButtonVariant variant;
  final String? semanticLabel;
  final bool fullWidth;

  /// عملیات بازگشت‌ناپذیر (قطع دسترسی، حذف تاریخچه)
  final bool destructive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = onPressed != null && !loading;

    void handlePress() {
      AppHaptics.tap(ref);
      onPressed?.call();
    }

    final Color destructiveColor = theme.colorScheme.error;

    final Widget content = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.fast),
      child: loading
          ? SizedBox(
              key: const ValueKey<String>('loading'),
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: variant == AppButtonVariant.filled
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
              ),
            )
          : Row(
              key: const ValueKey<String>('label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  A11y.decorative(Icon(icon, size: 22)),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    // متن دکمه با بزرگ‌نمایی زیاد نباید بشکند و ناخوانا شود
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    final Widget button;

    switch (variant) {
      case AppButtonVariant.filled:
        button = FilledButton(
          onPressed: enabled ? handlePress : null,
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: destructiveColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                )
              : null,
          child: content,
        );

      case AppButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: enabled ? handlePress : null,
          style: destructive
              ? OutlinedButton.styleFrom(
                  foregroundColor: destructiveColor,
                  side: BorderSide(color: destructiveColor, width: 1.5),
                  minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                )
              : null,
          child: content,
        );

      case AppButtonVariant.text:
        button = TextButton(
          onPressed: enabled ? handlePress : null,
          style: destructive
              ? TextButton.styleFrom(foregroundColor: destructiveColor)
              : null,
          child: content,
        );
    }

    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      enabled: enabled,
      // وقتی دکمه در حال کار است، صفحه‌خوان باید بداند — وگرنه کاربر نابینا
      // فکر می‌کند لمسش ثبت نشده و دوباره می‌زند
      hint: loading ? 'در حال انجام' : null,
      excludeSemantics: true,
      child: fullWidth ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

enum AppButtonVariant { filled, outlined, text }
