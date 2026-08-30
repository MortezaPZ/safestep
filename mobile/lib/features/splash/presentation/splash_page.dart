import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_controller.dart';

/// صفحه‌ی آغازین.
///
/// ── چرا اصلاً وجود دارد ─────────────────────────────────────────────────
/// این صفحه تزئینی نیست. در گام ۴، جایی است که توکن ذخیره‌شده خوانده و
/// اعتبارسنجی می‌شود و کاربر بر اساس نقشش به خانه‌ی درست هدایت می‌گردد.
/// آن کار زمان می‌برد و بدون این صفحه، اپ با یک صفحه‌ی سفیدِ بی‌توضیح
/// شروع می‌شد.
///
/// ── و چرا مدتش کوتاه است ────────────────────────────────────────────────
/// تأخیر مصنوعی برای «دیده شدن لوگو» به کاربر بی‌احترامی است. این صفحه فقط
/// تا وقتی که کار واقعی تمام شود می‌ماند، با یک کف کوتاه که پرش بصری
/// نداشته باشیم.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// کف زمان نمایش. کمتر از این، ظاهر شدن و ناپدید شدنِ آنی است که بیشتر
  /// شبیه خطا به نظر می‌رسد تا گذار.
  static const Duration _minimumVisible = Duration(milliseconds: 700);

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // شروع از اینجا و نه از initState: خواندن MediaQuery (برای تشخیص
    // «کاهش حرکت») پیش از اولین وابستگی‌سنجی، خطا می‌دهد.
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!mounted) return;

    if (!AppMotion.reduced(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }

    // بازیابی نشست و کف زمان نمایش، هم‌زمان اجرا می‌شوند: اگر توکن سریع
    // خوانده شد، باز هم صفحه یک لحظه دیده می‌شود؛ و اگر خواندن طول کشید،
    // منتظرش می‌مانیم. جمع کردن این دو در یک `wait`، هر دو حالت را پوشش
    // می‌دهد بدون آنکه زمان الکی تلف شود.
    await Future.wait<void>(<Future<void>>[
      ref.read(authControllerProvider.notifier).restore(),
      Future<void>.delayed(_minimumVisible),
    ]);

    if (!mounted) return;

    // هدایت را روتر انجام می‌دهد: با تغییر وضعیت ورود، `redirect` دوباره
    // ارزیابی می‌شود و کاربر به صفحه‌ی درست می‌رود. اینجا فقط اعلام
    // می‌کنیم که آماده شدیم.
    final bool signedIn = ref.read(authControllerProvider).isAuthenticated;
    A11y.announce(context, signedIn ? 'خوش آمدید' : 'آماده است');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CurvedAnimation curved =
        CurvedAnimation(parent: _controller, curve: AppMotion.enter);

    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'هم‌قدم، در حال آماده‌سازی',
          liveRegion: true,
          child: AnimatedBuilder(
            animation: curved,
            builder: (BuildContext context, Widget? child) {
              return Opacity(
                opacity: curved.value,
                child: Transform.scale(
                  scale: 0.92 + (curved.value * 0.08),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 6),
                  ),
                  child: const Icon(
                    Icons.directions_walk_rounded,
                    size: 56,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(AppConfig.appName, style: theme.textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'همراه امن، بدون از دست دادن استقلال',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
