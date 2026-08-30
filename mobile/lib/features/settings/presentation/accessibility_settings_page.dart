import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/accessibility/accessibility_settings.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../auth/presentation/auth_controller.dart';

/// تنظیمات دسترس‌پذیری.
///
/// ── چرا این صفحه پیش از ورود هم در دسترس است ────────────────────────────
/// کاربری که نمی‌تواند متنِ صفحه‌ی ورود را بخواند، هرگز به تنظیماتِ داخل
/// حساب نمی‌رسد. دکمه‌ی این صفحه از همان صفحه‌ی خوش‌آمد در دسترس است.
///
/// ── و چرا نمونه‌ی زنده دارد ─────────────────────────────────────────────
/// عدد «۱٫۳ برابر» برای کاربر معنایی ندارد. آنچه معنا دارد این است که
/// همین حالا ببیند متن چقدر بزرگ می‌شود. کارت نمونه بلافاصله تغییر می‌کند.
class AccessibilitySettingsPage extends ConsumerWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AccessibilitySettings settings = ref.watch(accessibilityProvider);
    final AccessibilityController controller =
        ref.read(accessibilityProvider.notifier);

    /// پس از هر تغییر، ترجیح روی سرور هم ذخیره می‌شود تا با تعویض گوشی از
    /// دست نرود. اگر کاربر وارد نشده باشد یا شبکه قطع باشد، بی‌صدا رد
    /// می‌شود — تنظیم محلی همیشه اعمال شده است.
    Future<void> sync() =>
        ref.read(authControllerProvider.notifier).pushAccessibilitySettings();

    return AppScaffold(
      title: 'نمایش و دسترس‌پذیری',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          /* ─────────────────── اندازه‌ی متن ─────────────────── */

          Text('اندازه‌ی متن', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'این تنظیم روی اندازه‌ی متنِ خودِ گوشی اضافه می‌شود.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _ScaleButton(
                      icon: Icons.remove_rounded,
                      label: 'کوچک‌تر',
                      onPressed: settings.textScale <= AccessibilitySettings.minScale
                          ? null
                          : () async {
                              AppHaptics.tap(ref);
                              await controller.decreaseTextScale();
                              await sync();
                              if (context.mounted) {
                                A11y.announce(context, 'اندازه‌ی متن کوچک‌تر شد');
                              }
                            },
                    ),
                    Expanded(
                      child: Semantics(
                        // مقدار به‌صورت خوانا اعلام می‌شود، نه «1.3»
                        label: 'اندازه‌ی فعلی متن',
                        value: '${Fa.digits(_scaleLabel(settings.textScale))} برابر',
                        liveRegion: true,
                        child: ExcludeSemantics(
                          child: Text(
                            '${Fa.digits(_scaleLabel(settings.textScale))}×',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                      ),
                    ),
                    _ScaleButton(
                      icon: Icons.add_rounded,
                      label: 'بزرگ‌تر',
                      onPressed: settings.textScale >= AccessibilitySettings.maxScale
                          ? null
                          : () async {
                              AppHaptics.tap(ref);
                              await controller.increaseTextScale();
                              await sync();
                              if (context.mounted) {
                                A11y.announce(context, 'اندازه‌ی متن بزرگ‌تر شد');
                              }
                            },
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.lg),

                // نمونه‌ی زنده — با هر تغییر، همین‌جا بزرگ و کوچک می‌شود
                Semantics(
                  label: 'نمونه‌ی متن با اندازه‌ی انتخاب‌شده',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('نمونه', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'مریم در محدوده‌ی «خانه» است. آخرین موقعیت، ۳ دقیقه پیش دریافت شد.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          /* ─────────────────── کنتراست و لرزش ─────────────────── */

          Text('خوانایی', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                SwitchListTile.adaptive(
                  value: settings.highContrast,
                  onChanged: (bool value) async {
                    AppHaptics.tap(ref);
                    await controller.setHighContrast(value);
                    await sync();
                    if (context.mounted) {
                      A11y.announce(
                        context,
                        value ? 'کنتراست بالا روشن شد' : 'کنتراست بالا خاموش شد',
                      );
                    }
                  },
                  title: const Text('کنتراست بالا'),
                  subtitle: const Text('رنگ‌ها پررنگ‌تر و مرزها واضح‌تر می‌شوند'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xxs,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: settings.hapticFeedback,
                  onChanged: (bool value) async {
                    await controller.setHapticFeedback(value);
                    await sync();
                    if (value) AppHaptics.success(ref);
                  },
                  title: const Text('بازخورد لمسی'),
                  subtitle: const Text('با هر لمس، گوشی کمی می‌لرزد'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xxs,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          /* ─────────────────── تم ─────────────────── */

          Text('حالت نمایش', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (final ThemeMode mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: mode,
                    groupValue: settings.themeMode,
                    onChanged: (ThemeMode? value) async {
                      if (value == null) return;
                      AppHaptics.tap(ref);
                      await controller.setThemeMode(value);
                    },
                    title: Text(_themeLabel(mode)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xxs,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          Text(
            'این تنظیم‌ها پس از ورود به حساب، با سرور همگام می‌شوند تا با '
            'تعویض گوشی از دست نروند.',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// «۱» و «۱٫۳» — بدون صفرهای اضافی
  static String _scaleLabel(double scale) {
    final String raw = scale.toStringAsFixed(2);
    return raw
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', '٫');
  }

  static String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'مطابق تنظیم گوشی';
      case ThemeMode.light:
        return 'روشن';
      case ThemeMode.dark:
        return 'تیره';
    }
  }
}

class _ScaleButton extends StatelessWidget {
  const _ScaleButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 28,
        // هدف لمسی بزرگ‌تر از پیش‌فرض: این دکمه‌ها را دقیقاً کسانی استفاده
        // می‌کنند که در لمس دقیق مشکل دارند
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTapTarget,
          minHeight: AppSpacing.minTapTarget,
        ),
      ),
    );
  }
}
