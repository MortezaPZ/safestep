import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/app_snackbar.dart';
import 'sos_controller.dart';

/// دکمه‌ی درخواست کمک اضطراری.
///
/// ── چرا «نگه داشتن» و نه «یک ضربه» ──────────────────────────────────────
/// یک ضربه در جیب یا با تماس تصادفی رخ می‌دهد. نگه داشتن، نیت را ثابت
/// می‌کند. اما نگه داشتنِ طولانی هم پذیرفتنی نیست: کسی که افتاده و دستش
/// می‌لرزد، نباید سه ثانیه انگشتش را ثابت نگه دارد.
///
/// راه‌حل: **نگه داشتن کوتاه (۱٫۲ ثانیه) + شمارش معکوس سه‌ثانیه‌ای قابل
/// لغو**. حرکتِ لمسی سخت‌گیر است تا تصادفی فعال نشود؛ ولی وقتی فعال شد،
/// کاربر سه ثانیه فرصت لغو دارد و نیازی نیست انگشتش را نگه دارد.
///
/// ── دسترس‌پذیری این دکمه با بقیه فرق دارد ────────────────────────────────
/// کاربر نابینا نمی‌تواند «نگه داشتن روی یک دایره‌ی مشخص» را انجام دهد.
/// وقتی صفحه‌خوان روشن است، رفتار به «دو بار ضربه» تغییر می‌کند — همان
/// حرکتی که TalkBack و VoiceOver برای فعال کردن دکمه استفاده می‌کنند —
/// و شمارش معکوس با اعلام صوتی همراه می‌شود.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key, this.enabled = true});

  /// اگر کاربر هنوز به کسی وصل نشده، دکمه غیرفعال است — ولی **پنهان
  /// نمی‌شود**: کاربر باید بداند این قابلیت وجود دارد و چرا هنوز کار نمی‌کند.
  final bool enabled;

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  /// مدت نگه داشتن لازم برای فعال شدن
  static const Duration _holdDuration = Duration(milliseconds: 1200);

  /// فرصت لغو پس از فعال شدن
  static const int _countdownSeconds = 3;

  Timer? _holdTimer;
  Timer? _countdownTimer;
  int _remaining = _countdownSeconds;
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: AppMotion.pulse,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosControllerProvider.notifier).loadContacts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // نبض ملایم، فقط برای اینکه دکمه «زنده» به نظر برسد. با «کاهش حرکت»
    // خاموش می‌شود.
    if (AppMotion.reduced(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /* ═══════════════════════ جریان فعال‌سازی ═══════════════════════ */

  void _onPressStart() {
    if (!widget.enabled) return;

    setState(() => _pressing = true);

    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, _startCountdown);
  }

  void _onPressEnd() {
    _holdTimer?.cancel();
    if (mounted) setState(() => _pressing = false);
  }

  /// مسیر جایگزین برای صفحه‌خوان: یک بار فعال‌سازی، بدون نیاز به نگه داشتن.
  void _onSemanticActivate() {
    if (!widget.enabled) return;
    _startCountdown();
  }

  void _startCountdown() {
    if (ref.read(sosControllerProvider).phase != SosPhase.idle) return;

    // لرزش قوی — این یکی حتی با خاموش بودن بازخورد لمسی هم اجرا می‌شود
    AppHaptics.emergency();

    ref.read(sosControllerProvider.notifier).beginCountdown();

    setState(() {
      _remaining = _countdownSeconds;
      _pressing = false;
    });

    A11y.announceAssertive(
      context,
      'درخواست کمک تا ${Fa.digits(_countdownSeconds.toString())} ثانیه‌ی دیگر ارسال می‌شود. '
      'برای لغو، دکمه‌ی لغو را بزنید.',
    );

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _remaining -= 1);

      if (_remaining <= 0) {
        timer.cancel();
        unawaited(_send());
      } else {
        AppHaptics.emergency();
        A11y.announceAssertive(context, Fa.digits(_remaining.toString()));
      }
    });
  }

  void _cancel() {
    _countdownTimer?.cancel();
    ref.read(sosControllerProvider.notifier).cancel();

    setState(() => _remaining = _countdownSeconds);

    A11y.announceAssertive(context, 'درخواست کمک لغو شد');
    AppSnackBar.show(context, 'درخواست کمک لغو شد.', kind: AppSnackKind.info);
  }

  Future<void> _send() async {
    final bool ok = await ref.read(sosControllerProvider.notifier).trigger();

    if (!mounted) return;

    final SosState state = ref.read(sosControllerProvider);

    if (ok) {
      AppHaptics.emergency();

      final SosResultSummary summary = SosResultSummary.of(state);

      A11y.announceAssertive(context, summary.message);
      AppSnackBar.show(
        context,
        summary.message,
        kind: summary.warning ? AppSnackKind.warning : AppSnackKind.success,
        duration: const Duration(seconds: 8),
      );
    } else {
      AppHaptics.error(ref);

      final String message = state.error?.message ??
          'ارسال درخواست کمک ممکن نشد. لطفاً مستقیم تماس بگیرید.';

      A11y.announceAssertive(context, message);
      AppSnackBar.show(
        context,
        message,
        kind: AppSnackKind.error,
        duration: const Duration(seconds: 10),
      );
    }

    // پس از چند ثانیه، دکمه به حالت آماده برمی‌گردد
    Timer(const Duration(seconds: 6), () {
      if (mounted) ref.read(sosControllerProvider.notifier).reset();
    });
  }

  /* ═══════════════════════ نمایش ═══════════════════════ */

  @override
  Widget build(BuildContext context) {
    final SosState state = ref.watch(sosControllerProvider);
    final bool screenReader = A11y.screenReaderOn(context);

    final Widget circle = switch (state.phase) {
      SosPhase.countdown => _CountdownCircle(
          remaining: _remaining,
          onCancel: _cancel,
        ),
      SosPhase.sending => const _StateCircle(
          icon: Icons.wifi_tethering_rounded,
          label: 'در حال ارسال…',
          color: AppColors.warning,
          spinning: true,
        ),
      SosPhase.sent => _StateCircle(
          icon: Icons.check_circle_outline_rounded,
          label: SosResultSummary.of(state).short,
          color: AppColors.success,
        ),
      SosPhase.failed => const _StateCircle(
          icon: Icons.error_outline_rounded,
          label: 'ارسال نشد',
          color: AppColors.danger,
        ),
      SosPhase.idle => _IdleCircle(
          pressing: _pressing,
          enabled: widget.enabled,
          pulse: _pulse,
        ),
    };

    return Column(
      children: <Widget>[
        Semantics(
          label: 'دکمه‌ی درخواست کمک اضطراری',
          hint: widget.enabled
              ? (screenReader
                  ? 'برای ارسال، دو بار ضربه بزنید. سه ثانیه فرصت لغو دارید.'
                  : 'برای ارسال، دکمه را نگه دارید')
              : 'ابتدا باید یک مراقب با دسترسی اضطراری اضافه کنید',
          button: true,
          enabled: widget.enabled,
          // صفحه‌خوان به‌جای نگه داشتن، از همین کنش استفاده می‌کند
          onTap: state.phase == SosPhase.idle ? _onSemanticActivate : null,
          excludeSemantics: true,
          child: GestureDetector(
            onTapDown: (_) => _onPressStart(),
            onTapUp: (_) => _onPressEnd(),
            onTapCancel: _onPressEnd,
            child: circle,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // کاربر باید **قبل از** اضطرار بداند هشدارش به چه کسی می‌رسد
        _ContactsHint(contacts: state.contacts, enabled: widget.enabled),
      ],
    );
  }
}

/// خلاصه‌ی نتیجه‌ی ارسال، به زبان کاربر.
class SosResultSummary {
  const SosResultSummary({
    required this.message,
    required this.short,
    required this.warning,
  });

  final String message;
  final String short;

  /// آیا نتیجه با اینکه موفق بوده، جای نگرانی دارد؟
  final bool warning;

  static SosResultSummary of(SosState state) {
    final SosResult? result = state.result;

    if (result == null) {
      return const SosResultSummary(
        message: 'درخواست کمک ارسال شد.',
        short: 'ارسال شد',
        warning: false,
      );
    }

    // موفق، ولی به هیچ‌کس نرسیده — این باید صریح گفته شود
    if (!result.deliveredToSomeone) {
      return const SosResultSummary(
        message: 'درخواست ثبت شد، اما هیچ مخاطب اضطراری‌ای ندارید که به او '
            'اطلاع داده شود. لطفاً مستقیم تماس بگیرید.',
        short: 'بدون مخاطب',
        warning: true,
      );
    }

    final String names = result.recipientNames.join('، ');
    final String count = Fa.digits(result.recipientCount.toString());

    if (result.isStale) {
      return SosResultSummary(
        message: 'درخواست کمک به $names اطلاع داده شد. موقعیت ارسالی مربوط به '
            'چند دقیقه پیش است، چون موقعیت لحظه‌ای در دسترس نبود.',
        short: 'ارسال شد',
        warning: true,
      );
    }

    return SosResultSummary(
      message: 'درخواست کمک به $count نفر اطلاع داده شد: $names',
      short: 'ارسال شد',
      warning: false,
    );
  }
}

/* ═══════════════════════ اجزای نمایشی ═══════════════════════ */

class _IdleCircle extends StatelessWidget {
  const _IdleCircle({
    required this.pressing,
    required this.enabled,
    required this.pulse,
  });

  final bool pressing;
  final bool enabled;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final Color base = enabled ? AppColors.danger : Theme.of(context).disabledColor;

    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        // هنگام فشردن، دکمه کمی کوچک می‌شود: بازخورد بصری فوری که «لمس
        // ثبت شد» را می‌گوید، پیش از آنکه نگه داشتن کامل شود.
        final double scale = pressing ? 0.94 : 1 + (pulse.value * 0.015);

        return Transform.scale(
          scale: scale,
          child: Container(
            width: AppSpacing.sosButtonSize,
            height: AppSpacing.sosButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? AppColors.dangerLight : Colors.transparent,
              border: Border.all(color: base, width: pressing ? 6 : 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.sos_rounded, size: 64, color: base),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'درخواست کمک',
                  style: TextStyle(
                    color: enabled ? AppColors.dangerDark : base,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  enabled ? 'نگه دارید' : 'غیرفعال',
                  style: TextStyle(color: base, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CountdownCircle extends StatelessWidget {
  const _CountdownCircle({required this.remaining, required this.onCancel});

  final int remaining;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: AppSpacing.sosButtonSize,
          height: AppSpacing.sosButtonSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.danger,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                Fa.digits(remaining.toString()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'در حال ارسال…',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // دکمه‌ی لغو عمداً بزرگ و مستقل است، نه یک لینک کوچک
        SizedBox(
          width: AppSpacing.sosButtonSize,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: const Text('لغو'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
            ),
          ),
        ),
      ],
    );
  }
}

class _StateCircle extends StatelessWidget {
  const _StateCircle({
    required this.icon,
    required this.label,
    required this.color,
    this.spinning = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.sosButtonSize,
      height: AppSpacing.sosButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (spinning)
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: color, strokeWidth: 4),
            )
          else
            Icon(icon, size: 56, color: color),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactsHint extends StatelessWidget {
  const _ContactsHint({required this.contacts, required this.enabled});

  final List<String> contacts;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!enabled || contacts.isEmpty) {
      return Text(
        'هنوز کسی با دسترسی اضطراری ندارید. تا وقتی مراقبی اضافه نکنید، '
        'این دکمه به کسی خبر نمی‌دهد.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      'در صورت فشردن، به ${contacts.join('، ')} اطلاع داده می‌شود.',
      style: theme.textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}
