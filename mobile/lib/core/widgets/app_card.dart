import 'package:flutter/material.dart';

import '../accessibility/a11y.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// کارت پایه‌ی اپ.
///
/// جایگزین `Card` استاندارد است، به دو دلیل:
///   ۱) نوعِ `cardTheme` بین نسخه‌های Flutter تغییر کرده و وابسته نشدن به
///      آن، پروژه را از یک بازه‌ی نسخه‌ی خاص آزاد می‌کند.
///   ۲) کارتِ قابل لمس باید یک گره‌ی معنایی واحد باشد؛ اینجا این رفتار
///      پیش‌فرض است، نه چیزی که هر بار یادمان بماند اضافه کنیم.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.semanticLabel,
    this.semanticHint,
    this.accentColor,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// اگر داده شود، کل کارت به‌صورت یک واحد برای صفحه‌خوان خوانده می‌شود.
  final String? semanticLabel;
  final String? semanticHint;

  /// نوار رنگی کناری — برای کارت‌هایی که وضعیت دارند (هشدار، خطر).
  /// رنگ به‌تنهایی حامل معنا نیست و همیشه متن هم کنارش هست؛ این فقط
  /// کمکِ بصری برای پیدا کردن سریع است.
  final Color? accentColor;

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSurface surface = AppSurface.of(context);
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusLg);

    Widget content = Padding(padding: padding, child: child);

    if (accentColor != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // در RTL، این نوار به‌طور خودکار سمت راست قرار می‌گیرد
          A11y.decorative(
            Container(width: 5, color: accentColor),
          ),
          Expanded(child: content),
        ],
      );
    }

    Widget card = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.fast),
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: radius,
        border: Border.all(color: surface.border, width: surface.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: content,
              ),
            ),
    );

    if (semanticLabel != null) {
      card = A11y.mergedCard(
        label: semanticLabel!,
        hint: semanticHint,
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}
