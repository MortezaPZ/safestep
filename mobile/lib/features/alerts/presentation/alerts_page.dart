import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../../../core/utils/jalali_format.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/main_nav.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/state_views.dart';
import 'package:safestep/l10n/app_localizations.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../realtime/realtime_controller.dart';
import '../data/alerts_repository.dart';

/// وضعیت صفحه‌ی هشدارها.
@immutable
class AlertsState {
  const AlertsState({
    this.page = const AlertsPage(),
    this.unreadOnly = false,
    this.loading = false,
    this.error,
  });

  final AlertsPage page;
  final bool unreadOnly;
  final bool loading;
  final AppException? error;

  AlertsState copyWith({
    AlertsPage? page,
    bool? unreadOnly,
    bool? loading,
    AppException? error,
    bool clearError = false,
  }) {
    return AlertsState(
      page: page ?? this.page,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AlertsController extends StateNotifier<AlertsState> {
  AlertsController(this._ref) : super(const AlertsState()) {
    _listenToLive();
  }

  final Ref _ref;

  AlertsRepository get _repository => _ref.read(alertsRepositoryProvider);

  /// با رسیدن هشدار زنده، فهرست تازه می‌شود.
  ///
  /// جایگزینش این بود که هشدار دریافتی را دستی به ابتدای فهرست اضافه
  /// کنیم؛ اما آن شیء با آنچه REST برمی‌گرداند فرق‌های ریز دارد (مثل
  /// `isRead`) و ناسازگاری‌اش دیر و سخت پیدا می‌شود.
  void _listenToLive() {
    _ref.listen<LiveAlert?>(
      realtimeControllerProvider.select((RealtimeState s) => s.latestAlert),
      (LiveAlert? previous, LiveAlert? next) {
        if (next == null || next.id == previous?.id) return;
        load();
      },
    );
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final AlertsPage page = await _repository.list(unreadOnly: state.unreadOnly);
      state = state.copyWith(page: page, loading: false);
    } on AppException catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> setUnreadOnly(bool value) async {
    state = state.copyWith(unreadOnly: value);
    await load();
  }

  Future<void> markRead(String alertId) async {
    // به‌روزرسانی خوش‌بینانه: کاربر نباید منتظر رفت‌وبرگشت شبکه بماند تا
    // ببیند هشدار خوانده شد
    final List<AlertItem> updated = state.page.alerts
        .map((AlertItem a) => a.id == alertId ? _asRead(a) : a)
        .toList(growable: false);

    state = state.copyWith(
      page: AlertsPage(
        alerts: updated,
        unreadCount: (state.page.unreadCount - 1).clamp(0, 1 << 30),
        countsByType: state.page.countsByType,
      ),
    );

    try {
      await _repository.markRead(alertId);
    } on AppException {
      // شکست ثبت، فهرست را دوباره از سرور می‌خواند تا وضعیت واقعی برگردد
      await load();
    }
  }

  Future<void> markAllRead() async {
    try {
      await _repository.markAllRead();
      await load();
    } on AppException catch (error) {
      state = state.copyWith(error: error);
    }
  }

  Future<void> resolve(String alertId) async {
    try {
      await _repository.resolve(alertId);
      await load();
    } on AppException catch (error) {
      state = state.copyWith(error: error);
    }
  }

  static AlertItem _asRead(AlertItem alert) {
    return AlertItem(
      id: alert.id,
      type: alert.type,
      severity: alert.severity,
      title: alert.title,
      body: alert.body,
      createdAt: alert.createdAt,
      subjectName: alert.subjectName,
      subjectId: alert.subjectId,
      zoneName: alert.zoneName,
      isRead: true,
      resolvedAt: alert.resolvedAt,
    );
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final StateNotifierProvider<AlertsController, AlertsState> alertsControllerProvider =
    StateNotifierProvider<AlertsController, AlertsState>((ref) {
  return AlertsController(ref);
});

/// شمارنده‌ی نخوانده‌ها — نشان‌گر روی آیکون هشدارها.
final Provider<int> unreadAlertsProvider = Provider<int>((ref) {
  return ref.watch(alertsControllerProvider).page.unreadCount;
});

/* ═══════════════════════════ صفحه ═══════════════════════════ */

/// فهرست هشدارها.
///
/// ── ترتیب و اولویت ──────────────────────────────────────────────────────
/// هشدارها به ترتیب زمان می‌آیند، نه به ترتیب اهمیت. این عمدی است: مراقب
/// باید بتواند ترتیب رخدادها را بازسازی کند. اهمیت با رنگ و نوار کناری
/// نشان داده می‌شود، نه با جابه‌جا کردن ترتیب — چون فهرستی که ترتیبش با
/// هر رویداد عوض شود، قابل اتکا نیست.
class AlertsListPage extends ConsumerStatefulWidget {
  const AlertsListPage({super.key, this.alertId});

  final String? alertId;

  @override
  ConsumerState<AlertsListPage> createState() => _AlertsListPageState();
}

class _AlertsListPageState extends ConsumerState<AlertsListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(alertsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AlertsState state = ref.watch(alertsControllerProvider);

    ref.listen<AlertsState>(alertsControllerProvider, (AlertsState? _, AlertsState next) {
      final String? message = next.error?.message;
      if (message != null) {
        AppSnackBar.show(context, message, kind: AppSnackKind.error);
        ref.read(alertsControllerProvider.notifier).clearError();
      }
    });

    return AppScaffold(
      title: AppLocalizations.of(context)?.alerts ?? 'هشدارها',
      onRefresh: () => ref.read(alertsControllerProvider.notifier).load(),
      scrollable: true,
      bottomBar: const MainNav(current: 'alerts'),
      actions: <Widget>[
        if (state.page.unreadCount > 0)
          TextButton(
            onPressed: () =>
                ref.read(alertsControllerProvider.notifier).markAllRead(),
            child: const Text('خواندن همه'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),

          Row(
            children: <Widget>[
              Semantics(
                label: 'نمایش فقط هشدارهای نخوانده',
                toggled: state.unreadOnly,
                excludeSemantics: true,
                child: FilterChip(
                  selected: state.unreadOnly,
                  onSelected: (bool value) {
                    AppHaptics.tap(ref);
                    ref.read(alertsControllerProvider.notifier).setUnreadOnly(value);
                  },
                  label: Text(
                    state.page.unreadCount > 0
                        ? 'نخوانده (${Fa.digits(state.page.unreadCount.toString())})'
                        : 'فقط نخوانده‌ها',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          if (state.loading && state.page.alerts.isEmpty)
            const LoadingSkeleton(lines: 4, height: 88)
          else if (state.page.alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyView(
                icon: state.unreadOnly
                    ? Icons.mark_email_read_outlined
                    : Icons.notifications_none_rounded,
                title: state.unreadOnly
                    ? 'همه‌ی هشدارها خوانده شده‌اند'
                    : 'هشداری وجود ندارد',
                message: state.unreadOnly
                    ? null
                    : 'وقتی رویدادی رخ دهد، همین‌جا می‌بینیدش.',
              ),
            )
          else
            for (int i = 0; i < state.page.alerts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AnimatedEntrance(
                  index: i,
                  child: _AlertCard(
                    alert: state.page.alerts[i],
                    onTap: () => ref
                        .read(alertsControllerProvider.notifier)
                        .markRead(state.page.alerts[i].id),
                    onResolve: state.page.alerts[i].isResolved ||
                            ref.watch(currentUserProvider)?.role == UserRole.primary
                        ? null
                        : () => ref
                            .read(alertsControllerProvider.notifier)
                            .resolve(state.page.alerts[i].id),
                  ),
                ),
              ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onTap,
    required this.onResolve,
  });

  final AlertItem alert;
  final VoidCallback onTap;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _severityColor(alert.severity);

    return AppCard(
      accentColor: color,
      onTap: alert.isRead ? null : onTap,
      semanticLabel: _semanticLabel(alert),
      semanticHint: alert.isRead ? null : 'برای علامت‌زدن به‌عنوان خوانده‌شده، دو بار ضربه بزنید',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              A11y.decorative(Icon(_typeIcon(alert.type), color: color, size: 24)),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  alert.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    // نخوانده‌ها پررنگ‌ترند — اما تنها نشانه نیست؛
                    // نقطه‌ی کنارش هم هست
                    fontWeight: alert.isRead ? FontWeight.w400 : FontWeight.w700,
                  ),
                ),
              ),
              if (!alert.isRead)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxs),

          Text(alert.body, style: theme.textTheme.bodyMedium),

          if (alert.type == 'fall_detected' && alert.confidence != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Chip(
              label: Text(
                'اطمینان ${Fa.digits(((alert.confidence! * 100).round()).toString())}٪',
              ),
            ),
          ],

          if (alert.type == 'fall_detected' &&
              alert.subjectPhone != null &&
              alert.subjectPhone!.isNotEmpty) ...<Widget>[
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('tel:${alert.subjectPhone}')),
              icon: const Icon(Icons.call),
              label: const Text('تماس'),
            ),
          ],

          const SizedBox(height: AppSpacing.xs),

          Row(
            children: <Widget>[
              A11y.decorative(
                const Icon(Icons.schedule_rounded, size: 14),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  JalaliFormat.smart(alert.createdAt),
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (alert.isResolved)
                Text(
                  'رسیدگی شد',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.success,
                  ),
                )
              else if (onResolve != null && alert.isCritical)
                TextButton(
                  onPressed: onResolve,
                  child: const Text('رسیدگی شد'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _semanticLabel(AlertItem alert) {
    final StringBuffer buffer = StringBuffer();
    if (!alert.isRead) buffer.write('نخوانده. ');
    buffer.write('${alert.typeLabel}. ${alert.body} ');
    buffer.write(JalaliFormat.smart(alert.createdAt));
    if (alert.isResolved) buffer.write('. رسیدگی شده');
    return buffer.toString();
  }

  static Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return AppColors.danger;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'sos':
        return Icons.sos_rounded;
      case 'zone_exit':
        return Icons.exit_to_app_rounded;
      case 'zone_enter':
        return Icons.home_rounded;
      case 'long_stop':
        return Icons.hourglass_bottom_rounded;
      case 'gps_lost':
        return Icons.gps_off_rounded;
      case 'low_battery':
        return Icons.battery_alert_rounded;
      case 'fall_detected':
        return Icons.personal_injury_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }
}
