import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:safestep/l10n/app_localizations.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/accessibility/accessibility_settings.dart';
import '../../../core/utils/fa.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../fall/data/fall_repository.dart';
import '../../tracking/presentation/tracking_controller.dart';

/// تنظیمات.
///
/// ترتیب بخش‌ها عمدی است: «نمایش و دسترس‌پذیری» اول می‌آید، پیش از حریم
/// خصوصی و حساب. دلیلش این است که کاربری که به این تنظیم نیاز دارد، معمولاً
/// در خواندنِ خودِ همین فهرست هم مشکل دارد و نباید مجبور شود اسکرول کند.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('خروج از حساب'),
          content: const Text(
            'پس از خروج، ارسال موقعیت متوقف می‌شود و مراقبان شما دیگر '
            'موقعیتتان را نمی‌بینند.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('انصراف'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('خروج'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // ترتیب مهم است: اول ردیابی متوقف و صف محلی پاک می‌شود، بعد خروج.
    // اگر برعکس باشد، نمونه‌های باقی‌مانده در صف با توکنِ کاربر بعدی
    // فرستاده می‌شوند — یعنی موقعیت یک نفر به حساب دیگری می‌نشیند.
    final TrackingController tracking =
        ref.read(trackingControllerProvider.notifier);
    await tracking.stop();
    await tracking.clearQueue();

    // هدایت به صفحه‌ی ورود را روتر انجام می‌دهد
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);

    return AppScaffold(
      title: 'تنظیمات',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          if (user != null) ...<Widget>[
            AppCard(
              semanticLabel: '${user.fullName}، ${user.role.label}',
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.transparent,
                    child: Text(
                      Fa.initials(user.fullName),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(user.fullName, style: theme.textTheme.titleMedium),
                        Text(
                          '${user.role.label} · ${Fa.digits(Fa.formatPhone(user.phone))}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(AppLocalizations.of(context)?.language ?? 'زبان',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('فارسی'),
                      selected: ref.watch(accessibilityProvider).localeCode == 'fa',
                      onSelected: (_) => ref
                          .read(accessibilityProvider.notifier)
                          .setLocaleCode('fa'),
                    ),
                    ChoiceChip(
                      label: const Text('English'),
                      selected: ref.watch(accessibilityProvider).localeCode == 'en',
                      onSelected: (_) => ref
                          .read(accessibilityProvider.notifier)
                          .setLocaleCode('en'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _SettingsTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'اعلان لحظه‌ای',
                  subtitle: ref.watch(pushStatusProvider).reason,
                  enabled: false,
                  onTap: null,
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  title: 'نمایش و دسترس‌پذیری',
                  subtitle: 'اندازه‌ی متن، کنتراست، بازخورد لمسی، تم',
                  onTap: () => context.push(AppRoutes.accessibility),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'حریم خصوصی و اشتراک موقعیت',
                  subtitle: 'در گام ۵ فعال می‌شود',
                  enabled: false,
                  onTap: null,
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.people_outline_rounded,
                  title: 'مراقبان و دسترسی‌ها',
                  subtitle: 'چه کسی موقعیت شما را می‌بیند',
                  onTap: () => context.push(AppRoutes.guardians),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'هشدارها',
                  subtitle: 'رویدادهای ثبت‌شده و وضعیت خواندنشان',
                  onTap: () => context.push(AppRoutes.alerts),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.personal_injury_outlined,
                  title: 'تشخیص سقوط',
                  subtitle: 'گزارش سقوط ازدست‌رفته و شبیه‌سازی در حالت اشکال‌زدایی',
                  onTap: () async {
                    await ref.read(fallRepositoryProvider).reportMissed();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('گزارش سقوط ازدست‌رفته ثبت شد')),
                      );
                    }
                  },
                ),
                if (kDebugMode) ...<Widget>[
                  const Divider(height: 1),
                  _SettingsTile(
                    icon: Icons.bug_report_outlined,
                    title: 'شبیه‌سازی سقوط',
                    subtitle: 'فقط در نسخه‌ی اشکال‌زدایی',
                    onTap: () => context.go(
                      '${AppRoutes.fallCheck}?id=debug&sec=5',
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          if (user != null)
            AppButton(
              label: 'خروج از حساب',
              icon: Icons.logout_rounded,
              variant: AppButtonVariant.outlined,
              destructive: true,
              onPressed: () => _confirmLogout(context, ref),
            ),

          const SizedBox(height: AppSpacing.lg),

          Center(
            child: Text(
              '${AppConfig.appName} — نسخه‌ی ۱٫۰٫۰',
              style: theme.textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, size: 26),
      title: Text(title),
      subtitle: Text(subtitle),
      // آیکون فلش خودش با جهت متن نمی‌چرخد؛ در رابط راست‌به‌چپ، «جلو رفتن»
      // یعنی به سمت چپ، پس صریحاً chevron_left انتخاب شده است.
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
    );
  }
}
