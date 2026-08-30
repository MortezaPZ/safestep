import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/accessibility/accessibility_settings.dart';
import '../core/constants/app_config.dart';
import '../core/theme/app_theme.dart';
import '../features/realtime/realtime_controller.dart';
import 'router.dart';

/// ریشه‌ی اپلیکیشن.
///
/// چهار تصمیم سراسری اینجا اعمال می‌شوند و هیچ صفحه‌ای نباید آن‌ها را
/// دوباره تکرار کند:
///
/// ۱) **راست‌به‌چپ.** با `Locale('fa')` و `flutter_localizations`، جهت
///    خودکار RTL می‌شود. اما `Directionality` صریح هم گذاشته شده تا اگر
///    روزی زبان دوم اضافه شد، هیچ صفحه‌ای به جهتِ ضمنی تکیه نکرده باشد.
///
/// ۲) **بزرگ‌نمایی متن.** ضریب کاربر روی `MediaQuery` اعمال می‌شود، نه با
///    تغییر `fontSize` در تم. دلیلش این است که ضریب باید **روی** تنظیم
///    اندازه‌ی متنِ سیستم‌عامل سوار شود، نه جایگزینش: کاربری که در تنظیمات
///    اندروید فونت را بزرگ کرده، انتظار دارد آن بزرگی حفظ شود.
///
/// ۳) **سقف بزرگ‌نمایی.** ضریب سیستم‌عامل می‌تواند تا ۳ برابر برود که
///    چیدمان را می‌شکند. حاصل‌ضرب نهایی به ۲٫۲ محدود می‌شود: نقطه‌ای که
///    صفحه‌ها هنوز سالم‌اند.
///
/// ۴) **تم.** چهار حالت (روشن/تیره × عادی/کنتراست بالا) از یک منبع.
class SafeStepApp extends ConsumerWidget {
  const SafeStepApp({super.key});

  /// سقف ضریب نهایی متن. بالاتر از این، چیدمان صفحه‌ها می‌شکند و صفحه‌ی
  /// شکسته از متن کوچک هم بدتر است.
  static const double _maxEffectiveScale = 2.2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

      locale: const Locale('fa', 'IR'),
      supportedLocales: const <Locale>[Locale('fa', 'IR')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);

        // ضریب سیستم × ضریب کاربر، با سقف امن
        final double systemScale = media.textScaler.scale(1);
        final double effective =
            (systemScale * a11y.textScale).clamp(0.8, _maxEffectiveScale);

        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(effective)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
