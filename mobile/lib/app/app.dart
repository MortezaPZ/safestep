import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:safestep/l10n/app_localizations.dart';

import '../core/accessibility/accessibility_settings.dart';
import '../core/constants/app_config.dart';
import '../core/push/push_service.dart';
import '../core/theme/app_theme.dart';
import '../features/realtime/realtime_controller.dart';
import 'router.dart';

class SafeStepApp extends ConsumerStatefulWidget {
  const SafeStepApp({super.key});

  static const double _maxEffectiveScale = 2.2;

  @override
  ConsumerState<SafeStepApp> createState() => _SafeStepAppState();
}

class _SafeStepAppState extends ConsumerState<SafeStepApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final PushService push = ref.read(pushServiceProvider);
      await push.initialize(
        onOpenAlert: (String alertId) {
          ref.read(routerProvider).go('${AppRoutes.alerts}?alertId=$alertId');
        },
      );
      ref.read(pushStatusProvider.notifier).state = PushStatus(
        available: push.available,
        reason: push.reason,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AccessibilitySettings a11y = ref.watch(accessibilityProvider);
    final GoRouter router = ref.watch(routerProvider);

    // لایه‌ی اتصال زنده باید در تمام عمر اپ زنده بماند، نه فقط وقتی صفحه‌ی
    // نقشه باز است: هشدار اضطراری باید در هر صفحه‌ای دریافت شود.
    ref.watch(realtimeControllerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,

      theme: AppTheme.light(highContrast: a11y.highContrast),
      darkTheme: AppTheme.dark(highContrast: a11y.highContrast),
      themeMode: a11y.themeMode,

      locale: Locale(a11y.localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);

        // ضریب سیستم × ضریب کاربر، با سقف امن
        final double systemScale = media.textScaler.scale(1);
        final double effective =
            (systemScale * a11y.textScale).clamp(0.8, SafeStepApp._maxEffectiveScale);

        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(effective)),
          child: Directionality(
            textDirection: a11y.localeCode == 'en'
                ? TextDirection.ltr
                : TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
