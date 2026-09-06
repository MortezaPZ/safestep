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
import 'package:safestep/l10n/app_localizations.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../pairing/domain/pairing_models.dart';
import '../../pairing/presentation/pairing_controller.dart';
import '../../realtime/realtime_controller.dart';
import '../../sos/presentation/sos_button.dart';
import '../../tracking/presentation/tracking_card.dart';

/// خانه‌ی کاربر اصلی (فرد تحت پایش).
///
/// ── قاعده‌ی طراحی این صفحه ──────────────────────────────────────────────
/// این صفحه باید در یک نگاه سه چیز را بگوید و نه بیشتر:
///   ۱) موقعیتم در حال ارسال هست یا نه
///   ۲) چه کسی الان مرا می‌بیند — شفافیت، شرط استقلال است
///   ۳) اگر کمک لازم داشتم، دکمه کجاست
///
/// هر چیز دیگری به صفحه‌های دیگر می‌رود.
class PrimaryHomePage extends ConsumerStatefulWidget {
  const PrimaryHomePage({super.key});

  @override
  ConsumerState<PrimaryHomePage> createState() => _PrimaryHomePageState();
}

class _PrimaryHomePageState extends ConsumerState<PrimaryHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(currentUserProvider);

    final List<Guardianship> guardians = ref
        .watch(pairingControllerProvider)
        .lists
        .guardians
        .where((Guardianship g) => g.isActive)
        .toList();

    // دکمه‌ی اضطراری فقط وقتی معنا دارد که کسی با دسترسی اضطراری وجود داشته
    // باشد. اما پنهان نمی‌شود — غیرفعال و با توضیح نمایش داده می‌شود.
    final bool hasEmergencyContact = guardians.any(
      (Guardianship g) => g.has(SharePermission.emergency),
    );

    // هشدارهای زنده‌ی خودِ کاربر: او باید بداند چه چیزی درباره‌اش به خانواده
    // گزارش شده. شفافیت یک‌طرفه نیست.
    ref.listen<LiveAlert?>(
      realtimeControllerProvider.select((RealtimeState s) => s.latestAlert),
      (LiveAlert? previous, LiveAlert? next) {
        if (next == null || next.id == previous?.id) return;
        AppSnackBar.show(
          context,
          '${next.title}: ${next.body}',
          kind: next.isCritical ? AppSnackKind.error : AppSnackKind.info,
        );
      },
    );

    return AppScaffold(
      title: AppLocalizations.of(context)?.home ?? 'وضعیت من',
      showBackButton: false,
      scrollable: true,
      onRefresh: () => ref.read(pairingControllerProvider.notifier).load(),
      actions: <Widget>[
        const _ConnectionDot(),
        IconButton(
          onPressed: () => context.push(AppRoutes.settings),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'تنظیمات',
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          if (user != null)
            AnimatedEntrance(
              index: 0,
              child: Text(
                'سلام ${user.fullName.split(' ').first}',
                style: theme.textTheme.headlineSmall,
              ),
            ),

          const SizedBox(height: AppSpacing.md),

          /* ─────────────── ۱) ردیابی ─────────────── */

          const AnimatedEntrance(index: 1, child: TrackingCard()),

          const SizedBox(height: AppSpacing.md),

          /* ─────────────── ۲) چه کسی مرا می‌بیند ─────────────── */

          AnimatedEntrance(
            index: 2,
            child: _WatchersCard(guardians: guardians),
          ),

          const SizedBox(height: AppSpacing.xxl),

          /* ─────────────── ۳) دکمه‌ی اضطراری ─────────────── */

          AnimatedEntrance(
            index: 3,
            child: Center(child: SosButton(enabled: hasEmergencyContact)),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// نشانگر اتصال زنده.
///
/// نقطه‌ی کوچکی که می‌گوید اپ همین حالا با سرور در ارتباط است. برای کاربر
/// بینا یک تأیید بی‌صداست؛ برای صفحه‌خوان، برچسب کامل دارد.
class _ConnectionDot extends ConsumerWidget {
  const _ConnectionDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SocketStatus status =
        ref.watch(realtimeControllerProvider.select((RealtimeState s) => s.status));

    final bool connected = status == SocketStatus.connected;

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

/// کارت «چه کسی موقعیت من را می‌بیند».
class _WatchersCard extends StatelessWidget {
  const _WatchersCard({required this.guardians});

  final List<Guardianship> guardians;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (guardians.isEmpty) {
      return AppCard(
        semanticLabel: 'هیچ‌کس موقعیت شما را نمی‌بیند',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                A11y.decorative(
                  const Icon(Icons.visibility_off_outlined, size: 26),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'هنوز کسی موقعیت شما را نمی‌بیند.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'دعوت از مراقب',
              icon: Icons.person_add_alt_rounded,
              variant: AppButtonVariant.outlined,
              onPressed: () => context.push(AppRoutes.invite),
            ),
          ],
        ),
      );
    }

    final String names = guardians
        .map((Guardianship g) => g.guardianUser?.fullName ?? 'ناشناس')
        .join('، ');

    return AppCard(
      onTap: () => context.push(AppRoutes.guardians),
      semanticLabel:
          '${Fa.digits(guardians.length.toString())} نفر موقعیت شما را می‌بینند: $names',
      semanticHint: 'برای مدیریت دسترسی‌ها، دو بار ضربه بزنید',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              A11y.decorative(const Icon(Icons.visibility_outlined, size: 26)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${Fa.digits(guardians.length.toString())} نفر موقعیت شما را می‌بینند',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              A11y.decorative(const Icon(Icons.chevron_left_rounded)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              for (final Guardianship link in guardians)
                Chip(
                  avatar: CircleAvatar(
                    backgroundColor:
                        AppColors.parse(link.guardianUser?.avatarColor)
                            .withOpacity(0.2),
                    child: Text(
                      Fa.initials(link.guardianUser?.fullName ?? '؟'),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  label: Text(link.guardianUser?.fullName ?? 'ناشناس'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
