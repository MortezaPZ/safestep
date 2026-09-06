import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../data/permission_service.dart';
import '../domain/location_sample.dart';
import 'tracking_controller.dart';

/// کارت کنترل ردیابی: روشن/خاموش، وضعیت، و صف آفلاین.
///
/// ── چرا کلید ردیابی در صفحه‌ی اول است ───────────────────────────────────
/// در بیشتر اپ‌های ردیابی، خاموش کردنش پشت چند لایه منو پنهان است — چون
/// محصول نمی‌خواهد کاربر خاموشش کند. اینجا برعکس است: این کلید، همان
/// «استقلال» است که در عنوان محصول آمده و باید در دسترس‌ترین جای ممکن
/// باشد.
class TrackingCard extends ConsumerStatefulWidget {
  const TrackingCard({super.key});

  @override
  ConsumerState<TrackingCard> createState() => _TrackingCardState();
}

class _TrackingCardState extends ConsumerState<TrackingCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trackingControllerProvider.notifier).refreshPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // کاربر ممکن است به تنظیمات سیستم رفته و مجوز را عوض کرده باشد؛ با
    // برگشت به اپ، وضعیت دوباره خوانده می‌شود. بدون این، کاربری که همین
    // حالا مجوز داده، همچنان پیام «دسترسی ندارید» می‌بیند.
    if (state == AppLifecycleState.resumed) {
      ref.read(trackingControllerProvider.notifier).refreshPermission();
    }
  }

  /* ═══════════════════════ درخواست مجوز ═══════════════════════ */

  /// توضیح پیش از درخواست.
  ///
  /// اندروید فقط **دو بار** اجازه‌ی پرسیدن می‌دهد؛ بار سوم یعنی «دیگر
  /// نپرس» و تنها راهش رفتن دستی به تنظیمات. پس نباید بدون توضیح پرسید.
  Future<bool> _explainThenRequest() async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('دسترسی به موقعیت'),
          content: const Text(
            'برای اینکه مراقبانتان بدانند کجا هستید و در صورت نیاز به کمکتان '
            'بیایند، اپ به موقعیت شما نیاز دارد.\n\n'
            'شما تعیین می‌کنید چه کسی موقعیتتان را ببیند، و هر لحظه می‌توانید '
            'اشتراک‌گذاری را خاموش کنید.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('الان نه'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('اجازه می‌دهم'),
            ),
          ],
        );
      },
    );

    if (proceed != true || !mounted) return false;

    final LocationPermissionService service =
        ref.read(locationPermissionServiceProvider);

    LocationPermissionState result = await service.requestForeground();

    if (!mounted) return false;

    // مرحله‌ی دوم: مجوز پس‌زمینه. عمداً جداگانه و با توضیح خودش، چون
    // اندروید ۱۱ به بعد اجازه‌ی درخواست هم‌زمان نمی‌دهد.
    if (result == LocationPermissionState.whileInUseOnly) {
      final bool? background = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('وقتی اپ بسته است'),
            content: const Text(
              'اگر می‌خواهید حتی وقتی اپ بسته است هم موقعیتتان به مراقبانتان '
              'برسد، در صفحه‌ی بعد گزینه‌ی «همیشه اجازه بده» را انتخاب کنید.\n\n'
              'اگر نخواهید، اپ فقط هنگام باز بودن کار می‌کند.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('همین کافی است'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ادامه'),
              ),
            ],
          );
        },
      );

      if (background == true && mounted) {
        result = await service.requestBackground();
      }
    }

    if (!mounted) return false;

    await ref.read(trackingControllerProvider.notifier).refreshPermission();

    return result == LocationPermissionState.granted ||
        result == LocationPermissionState.whileInUseOnly;
  }

  Future<void> _toggle(bool value) async {
    final TrackingController controller =
        ref.read(trackingControllerProvider.notifier);

    if (!value) {
      await controller.stop();
      if (mounted) A11y.announce(context, 'ارسال موقعیت متوقف شد');
      return;
    }

    final LocationPermissionState permission =
        ref.read(trackingControllerProvider).permission;

    if (permission == LocationPermissionState.serviceDisabled) {
      await ref.read(locationPermissionServiceProvider).openLocationSettings();
      return;
    }

    if (permission == LocationPermissionState.permanentlyDenied) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        'دسترسی به موقعیت رد شده است. از تنظیمات گوشی آن را روشن کنید.',
        kind: AppSnackKind.warning,
        actionLabel: 'تنظیمات',
        onAction: () =>
            ref.read(locationPermissionServiceProvider).openAppSettings(),
      );
      return;
    }

    if (permission != LocationPermissionState.granted &&
        permission != LocationPermissionState.whileInUseOnly) {
      final bool granted = await _explainThenRequest();
      if (!granted) return;
    }

    final bool started = await controller.start();

    if (!mounted) return;

    if (started) {
      AppHaptics.success(ref);
      A11y.announce(context, 'ارسال موقعیت آغاز شد');
    } else {
      final String message = ref.read(trackingControllerProvider).error?.message ??
          'شروع ردیابی ممکن نشد.';
      AppSnackBar.show(context, message, kind: AppSnackKind.error);
    }
  }

  /* ═══════════════════════ نمایش ═══════════════════════ */

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TrackingState state = ref.watch(trackingControllerProvider);

    final _Visual visual = _Visual.of(state);

    return AppCard(
      accentColor: visual.color,
      semanticLabel: 'وضعیت ارسال موقعیت: ${visual.title}. ${visual.detail}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              A11y.decorative(Icon(visual.icon, size: 32, color: visual.color)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(visual.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(visual.detail, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Semantics(
                label: 'ارسال موقعیت',
                toggled: state.isActive,
                excludeSemantics: true,
                child: Switch.adaptive(
                  value: state.isActive,
                  onChanged: (bool value) => _toggle(value),
                ),
              ),
            ],
          ),

          // صف آفلاین: کاربر باید بداند داده‌اش گم نشده، فقط منتظر است
          if (state.queuedCount > 0) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                A11y.decorative(
                  const Icon(Icons.cloud_off_rounded,
                      size: 20, color: AppColors.warning),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '${Fa.digits(state.queuedCount.toString())} موقعیت در انتظار ارسال است. '
                    'با وصل شدن اینترنت، خودکار فرستاده می‌شود.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],

          // مجوز ناقص: ردیابی هنگام باز بودن اپ کار می‌کند ولی پس‌زمینه نه
          if (state.permission == LocationPermissionState.whileInUseOnly &&
              state.isActive) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            Text(
              'وقتی اپ بسته باشد، موقعیت ارسال نمی‌شود.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'اجازه‌ی دسترسی همیشگی',
              variant: AppButtonVariant.text,
              onPressed: () async {
                await ref
                    .read(locationPermissionServiceProvider)
                    .requestBackground();
                await ref
                    .read(trackingControllerProvider.notifier)
                    .refreshPermission();
              },
            ),
          ],

          // مکان‌یاب خاموش است
          if (state.permission == LocationPermissionState.serviceDisabled) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            AppButton(
              label: 'روشن کردن مکان‌یاب گوشی',
              icon: Icons.location_on_outlined,
              variant: AppButtonVariant.outlined,
              onPressed: () => ref
                  .read(locationPermissionServiceProvider)
                  .openLocationSettings(),
            ),
          ],
        ],
      ),
    );
  }
}

/// نگاشت وضعیت به ظاهر و متن.
class _Visual {
  const _Visual({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;

  static _Visual of(TrackingState state) {
    switch (state.status) {
      case TrackingStatus.live:
        final DateTime? sentAt = state.lastSentAt;
        return _Visual(
          title: state.powerSave
              ? 'حالت صرفه‌جویی باتری'
              : 'موقعیت شما در حال ارسال است',
          detail: state.powerSave
              ? 'حرکت کمی است؛ بازه‌ی ارسال طولانی‌تر شده است.'
              : sentAt == null
                  ? 'در انتظار اولین موقعیت…'
                  : 'آخرین ارسال: ${Fa.timeAgo(sentAt)}',
          icon: Icons.location_on_rounded,
          color: AppColors.success,
        );

      case TrackingStatus.offline:
        return const _Visual(
          title: 'اینترنت قطع است',
          detail: 'موقعیت‌ها ذخیره می‌شوند و با وصل شدن ارسال می‌گردند.',
          icon: Icons.cloud_off_rounded,
          color: AppColors.warning,
        );

      case TrackingStatus.starting:
        return const _Visual(
          title: 'در حال آماده‌سازی…',
          detail: 'دریافت موقعیت از گوشی',
          icon: Icons.gps_not_fixed_rounded,
          color: AppColors.warning,
        );

      case TrackingStatus.blocked:
        return _Visual(
          title: 'ردیابی متوقف است',
          detail: state.error?.message ?? 'دسترسی به موقعیت ممکن نیست.',
          icon: Icons.location_disabled_rounded,
          color: AppColors.danger,
        );

      case TrackingStatus.off:
        return const _Visual(
          title: 'ارسال موقعیت خاموش است',
          detail: 'هیچ‌کس موقعیت شما را نمی‌بیند.',
          icon: Icons.location_off_outlined,
          color: AppColors.lightTextMuted,
        );
    }
  }
}
