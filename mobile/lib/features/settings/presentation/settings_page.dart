import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:safestep/l10n/app_localizations.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/main_nav.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/accessibility/accessibility_settings.dart';
import '../../../core/utils/fa.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../fall/data/fall_repository.dart';
import '../../tracking/data/location_repository.dart';
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
      showBackButton: false,
      scrollable: true,
      bottomBar: const MainNav(current: 'settings'),
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
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            '${user.role.label} · ${user.phone}',
                            style: theme.textTheme.bodySmall,
                          ),
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
                  onTap: () async {
                    try {
                      final String reason = await ref.read(pushServiceProvider).enableAndConfirm();
                      ref.read(pushStatusProvider.notifier).state = PushStatus(
                        available: true,
                        reason: reason,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('اعلان لحظه‌ای فعال شد')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('اعلان فعال نشد: $error')),
                        );
                      }
                    }
                  },
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
                  subtitle: 'روشن یا خاموش کردن دیدن موقعیت توسط ناظر',
                  onTap: () async {
                    final bool? enable = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                        title: const Text('اشتراک موقعیت'),
                        content: const Text('ناظر اصلی حتی پس از خاموش کردن هم می‌تواند موقعیت را ببیند.'),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('خاموش')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('روشن')),
                        ],
                      ),
                    );
                    if (enable == null) return;
                    await ref.read(locationRepositoryProvider).setSharing(enable);
                  },
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
                  subtitle: 'با زدن این گزینه گزارش سقوط برای ناظر و مدیر ثبت می‌شود',
                  onTap: () async {
                    if (ref.read(currentUserProvider)?.role == UserRole.admin) {
                      context.go(AppRoutes.adminFalls);
                      return;
                    }
                    try {
                      await ref.read(fallRepositoryProvider).reportMissed();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('گزارش سقوط ثبت شد و برای ناظر و مدیر ارسال شد')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('گزارش ثبت نشد: $error')),
                        );
                      }
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
          const _DocumentsCard(),
          const SizedBox(height: AppSpacing.md),
          const _SupportCard(),
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

class _DocumentsCard extends ConsumerStatefulWidget {
  const _DocumentsCard();

  @override
  ConsumerState<_DocumentsCard> createState() => _DocumentsCardState();
}

class _DocumentsCardState extends ConsumerState<_DocumentsCard> {
  final TextEditingController _condition = TextEditingController();
  String _list = '';
  String? _subjectUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _condition.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ApiClient api = ref.read(apiClientProvider);
    try {
      final links = await api.get<Map<String, dynamic>>(
        '/guardianships',
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      );
      final primaries = (links['primaries'] as List?) ?? const [];
      for (final dynamic item in primaries) {
        final map = Map<String, dynamic>.from(item as Map);
        if (map['isMainSupervisor'] == true) {
          _subjectUserId = map['primaryUserId'] as String?;
          break;
        }
      }
      final data = await api.get<Map<String, dynamic>>(
        '/documents/mine',
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      );
      final docs = (data['documents'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _list = docs.isEmpty
            ? 'مدرکی ارسال نشده است.'
            : docs.map((dynamic item) {
                final map = Map<String, dynamic>.from(item as Map);
                final status = map['status'] == 'approved'
                    ? 'تأیید شده'
                    : map['status'] == 'pending'
                        ? 'در انتظار'
                        : '${map['status']}';
                final health = map['status'] == 'approved' ? map['healthCondition'] : null;
                final name = map['userName'] ?? '';
                return '$name $status${health == null ? '' : ' — مشکل: $health'}';
              }).join('\n');
      });
    } catch (_) {
      if (mounted) setState(() => _list = 'مدارک بارگذاری نشد.');
    }
  }

  Future<void> _send() async {
    final ByteData bytes = await rootBundle.load('assets/images/logo-hamghadam.jpg');
    final String imageUrl =
        'data:image/jpeg;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
    final Map<String, dynamic> body = <String, dynamic>{
      'documentType': 'identity',
      'imageUrl': imageUrl,
    };
    final String condition = _condition.text.trim();
    if (condition.length >= 2) body['healthCondition'] = condition;
    if (_subjectUserId != null) body['subjectUserId'] = _subjectUserId;
    await ref.read(apiClientProvider).post<Map<String, dynamic>>(
      '/documents',
      (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      body: body,
    );
    _condition.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _subjectUserId == null ? 'ارسال مدارک' : 'ارسال مدارک کاربر اصلی',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _condition,
            decoration: const InputDecoration(hintText: 'مشکل شخص، مثلاً بیماری قلبی'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'ارسال مدرک', onPressed: _send),
          if (_list.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(_list),
          ],
        ],
      ),
    );
  }
}

class _SupportCard extends ConsumerStatefulWidget {
  const _SupportCard();

  @override
  ConsumerState<_SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends ConsumerState<_SupportCard> {
  final TextEditingController _body = TextEditingController();
  String _log = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
        '/support/messages',
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      );
      final messages = (data['messages'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _log = messages.map((dynamic item) {
          final map = Map<String, dynamic>.from(item as Map);
          final who = map['senderRole'] == 'admin' ? 'پشتیبانی' : 'شما';
          return '$who: ${map['body']}';
        }).join('\n');
      });
    } catch (_) {
      if (mounted) setState(() => _log = 'پیامی بارگذاری نشد.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('پیام به پشتیبانی', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _body, minLines: 2, maxLines: 4),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'ارسال پیام',
            onPressed: () async {
              final text = _body.text.trim();
              if (text.length < 2) return;
              await ref.read(apiClientProvider).post<Map<String, dynamic>>(
                '/support/messages',
                (dynamic raw) => Map<String, dynamic>.from(raw as Map),
                body: <String, dynamic>{'body': text},
              );
              _body.clear();
              await _load();
            },
          ),
          if (_log.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(_log),
          ],
        ],
      ),
    );
  }
}
