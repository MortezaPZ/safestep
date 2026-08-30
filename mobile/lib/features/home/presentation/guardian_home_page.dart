import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/accessibility/a11y.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/state_views.dart';
import '../../alerts/presentation/alerts_page.dart';
import '../../pairing/domain/pairing_models.dart';
import '../../realtime/realtime_controller.dart';
import '../../watching/domain/watched_person.dart';
import '../../watching/presentation/watching_controller.dart';

/// خانه‌ی مراقب — فهرست افراد تحت پایش با وضعیت زنده.
///
/// ── چه چیزی روی هر کارت است و چرا ───────────────────────────────────────
/// نام، وضعیت محدوده، زمان آخرین به‌روزرسانی، و باتری. همین چهارتا.
///
/// «زمان آخرین به‌روزرسانی» مهم‌ترینشان است و معمولاً همان چیزی است که جا
/// می‌افتد: نقطه‌ای روی نقشه که ندانیم برای کِی است، اطلاعات نیست. مراقبی
/// که فکر می‌کند موقعیت زنده است ولی در واقع مال دو ساعت پیش است، بدتر از
/// مراقبی است که می‌داند خبری ندارد.
class GuardianHomePage extends ConsumerStatefulWidget {
  const GuardianHomePage({super.key});

  @override
  ConsumerState<GuardianHomePage> createState() => _GuardianHomePageState();
}

class _GuardianHomePageState extends ConsumerState<GuardianHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchingControllerProvider.notifier).load();
      ref.read(alertsControllerProvider.notifier).load();
    });
  }

  Future<void> _openRedeem() async {
    await context.push<bool>(AppRoutes.redeem);
    if (!mounted) return;
    await ref.read(watchingControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WatchingState state = ref.watch(watchingControllerProvider);
    final int unread = ref.watch(unreadAlertsProvider);

    // هشدار بحرانی، در هر صفحه‌ای که باشیم دیده می‌شود
    ref.listen<LiveAlert?>(
      realtimeControllerProvider.select((RealtimeState s) => s.latestAlert),
      (LiveAlert? previous, LiveAlert? next) {
        if (next == null || next.id == previous?.id) return;

        if (next.isCritical) {
          AppHaptics.emergency();
          A11y.announceAssertive(context, '${next.title}. ${next.body}');
        }

        AppSnackBar.show(
          context,
          next.body.isEmpty ? next.title : next.body,
          kind: next.isCritical ? AppSnackKind.error : AppSnackKind.warning,
          duration: next.isCritical
              ? const Duration(seconds: 10)
              : const Duration(seconds: 5),
          actionLabel: 'مشاهده',
          onAction: () => context.push(AppRoutes.alerts),
        );
      },
    );

    return AppScaffold(
      title: 'افراد تحت پایش',
      showBackButton: false,
      scrollable: true,
      onRefresh: () async {
        await ref.read(watchingControllerProvider.notifier).load();
        await ref.read(alertsControllerProvider.notifier).load();
      },
      actions: <Widget>[
        const _ConnectionDot(),
        _AlertsButton(unread: unread),
        IconButton(
          onPressed: () => context.push(AppRoutes.settings),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'تنظیمات',
        ),
      ],
      body: Builder(
        builder: (BuildContext context) {
          if (state.loading && state.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: AppSpacing.lg),
              child: LoadingSkeleton(lines: 2, height: 120),
            );
          }

          if (state.error != null && state.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: ErrorView(
                error: state.error!,
                onRetry: () =>
                    ref.read(watchingControllerProvider.notifier).load(),
              ),
            );
          }

          if (state.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyView(
                icon: Icons.group_outlined,
                title: 'هنوز به کسی وصل نشده‌اید',
                message: 'از فردی که می‌خواهید همراهش باشید بخواهید کد دعوت '
                    'شش‌رقمی‌اش را برایتان بفرستد.',
                actionLabel: 'وارد کردن کد دعوت',
                onAction: _openRedeem,
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.md),

              for (int i = 0; i < state.people.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AnimatedEntrance(
                    index: i,
                    child: _PersonStatusCard(person: state.people[i]),
                  ),
                ),

              const SizedBox(height: AppSpacing.md),

              AppButton(
                label: 'اتصال به فرد تازه',
                icon: Icons.qr_code_scanner_rounded,
                variant: AppButtonVariant.outlined,
                onPressed: _openRedeem,
              ),

              const SizedBox(height: AppSpacing.md),

              Text(
                'برای دیدن نقشه‌ی زنده، روی هر نفر ضربه بزنید.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

/* ═══════════════════════════ اجزا ═══════════════════════════ */

class _ConnectionDot extends ConsumerWidget {
  const _ConnectionDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool connected = ref.watch(
      realtimeControllerProvider.select(
        (RealtimeState s) => s.status == SocketStatus.connected,
      ),
    );

    return Semantics(
      label: connected ? 'اتصال زنده برقرار است' : 'اتصال زنده برقرار نیست',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? AppColors.success : AppColors.lightTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertsButton extends StatelessWidget {
  const _AlertsButton({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: unread > 0
          ? 'هشدارها، ${Fa.digits(unread.toString())} مورد نخوانده'
          : 'هشدارها',
      button: true,
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          IconButton(
            onPressed: () => context.push(AppRoutes.alerts),
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'هشدارها',
          ),
          if (unread > 0)
            Positioned(
              top: 8,
              // در چیدمان راست‌به‌چپ، `right` سمت راستِ بصری است؛ نشان‌گر
              // باید روی گوشه‌ی بالا-راستِ آیکون بنشیند
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  Fa.digits(unread > 99 ? '99+' : unread.toString()),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonStatusCard extends StatelessWidget {
  const _PersonStatusCard({required this.person});

  final WatchedPerson person;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color avatarColor = AppColors.parse(person.person.avatarColor);
    final TrackPoint? point = person.location;

    // فهرست خالی یعنی سرور سطوح دسترسی را در این پاسخ نفرستاده، نه اینکه
    // دسترسی وجود ندارد؛ در آن حالت پیام هشدار نمایش داده نمی‌شود.
    final bool canView = person.permissions.isEmpty ||
        person.permissions.contains(SharePermission.viewLocation);

    return AppCard(
      accentColor: _statusColor(person),
      onTap: () => context.push(AppRoutes.mapFor(person.userId)),
      semanticLabel: _semanticLabel(person),
      semanticHint: 'برای دیدن نقشه، دو بار ضربه بزنید',
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              A11y.decorative(
                Stack(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: avatarColor.withOpacity(0.15),
                      child: Text(
                        Fa.initials(person.person.fullName),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: avatarColor),
                      ),
                    ),
                    if (person.isOnline)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(person.person.fullName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _statusText(person),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _statusColor(person),
                      ),
                    ),
                  ],
                ),
              ),
              A11y.decorative(const Icon(Icons.chevron_left_rounded)),
            ],
          ),

          if (point != null && !person.hidden) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                A11y.decorative(const Icon(Icons.schedule_rounded, size: 16)),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  Fa.timeAgo(point.recordedAt),
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                if (point.batteryLevel != null) ...<Widget>[
                  A11y.decorative(
                    Icon(
                      point.batteryLevel! <= 15
                          ? Icons.battery_alert_rounded
                          : Icons.battery_full_rounded,
                      size: 16,
                      color: point.batteryLevel! <= 15 ? AppColors.warning : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    Fa.percent(point.batteryLevel!),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (point.isSimulated) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'حالت نمایش',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.simulated),
                  ),
                ],
              ],
            ),
          ],

          if (!canView) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            Text(
              'شما به موقعیت این فرد دسترسی ندارید.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  static String _statusText(WatchedPerson person) {
    if (person.hidden) return 'اشتراک‌گذاری موقتاً خاموش است';
    if (!person.hasLocation) return 'هنوز موقعیتی ثبت نشده';
    if (person.gpsStale) return 'موقعیت قدیمی است';
    if (person.zoneStatus == 'inside' && person.zoneNames.isNotEmpty) {
      return 'در «${person.zoneNames.first}»';
    }
    if (person.zoneStatus == 'outside') return 'خارج از محدوده‌های امن';
    return 'در حال پایش';
  }

  static Color _statusColor(WatchedPerson person) {
    if (person.hidden || !person.hasLocation) return AppColors.lightTextMuted;
    if (person.gpsStale) return AppColors.warning;
    if (person.zoneStatus == 'inside') return AppColors.success;
    if (person.zoneStatus == 'outside') return AppColors.warning;
    return AppColors.primary;
  }

  static String _semanticLabel(WatchedPerson person) {
    final StringBuffer buffer = StringBuffer()
      ..write('${person.person.fullName}. ')
      ..write('${_statusText(person)}. ');

    final TrackPoint? point = person.location;
    if (point != null && !person.hidden) {
      buffer.write('آخرین به‌روزرسانی ${Fa.timeAgo(point.recordedAt)}. ');
      if (point.batteryLevel != null) {
        buffer.write('باتری ${Fa.percent(point.batteryLevel!)}.');
      }
    }

    return buffer.toString();
  }
}
