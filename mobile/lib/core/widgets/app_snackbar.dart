import 'package:flutter/material.dart';

import '../accessibility/a11y.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// پیام‌های گذرا.
///
/// ── چرا هر پیام هم‌زمان به صفحه‌خوان اعلام می‌شود ────────────────────────
/// SnackBar روی صفحه ظاهر می‌شود و می‌رود. کاربر نابینا آن را نمی‌بیند و
/// چون فوکوس را نمی‌گیرد، صفحه‌خوان هم لزوماً نمی‌خواندش. نتیجه: کاربر
/// نابینا هرگز نمی‌فهمد «موقعیت ارسال شد» یا «خطا رخ داد». اعلام صریح،
/// این شکاف را می‌بندد.
class AppSnackBar {
  const AppSnackBar._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackKind kind = AppSnackKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // پیام قبلی کنار می‌رود تا پیام‌ها روی هم تلنبار نشوند
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            A11y.decorative(Icon(_icon(kind), color: _color(kind), size: 22)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        duration: duration,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                onPressed: onAction,
                textColor: AppColors.primaryLight,
              )
            : null,
      ),
    );

    // خطاها با اولویت بالا اعلام می‌شوند تا خواندنِ جاری را قطع کنند
    if (kind == AppSnackKind.error) {
      A11y.announceAssertive(context, message);
    } else {
      A11y.announce(context, message);
    }
  }

  static IconData _icon(AppSnackKind kind) {
    switch (kind) {
      case AppSnackKind.success:
        return Icons.check_circle_outline_rounded;
      case AppSnackKind.error:
        return Icons.error_outline_rounded;
      case AppSnackKind.warning:
        return Icons.warning_amber_rounded;
      case AppSnackKind.info:
        return Icons.info_outline_rounded;
    }
  }

  static Color _color(AppSnackKind kind) {
    switch (kind) {
      case AppSnackKind.success:
        return AppColors.successLight;
      case AppSnackKind.error:
        return AppColors.dangerLight;
      case AppSnackKind.warning:
        return AppColors.warningLight;
      case AppSnackKind.info:
        return AppColors.primaryLight;
    }
  }
}

enum AppSnackKind { info, success, warning, error }
