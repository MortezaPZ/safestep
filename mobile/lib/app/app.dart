import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:safestep/l10n/app_localizations.dart';

import '../core/accessibility/accessibility_settings.dart';
import '../core/constants/app_config.dart';
import '../core/push/fall_notification_payload.dart';
import '../core/push/push_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/realtime/realtime_controller.dart';
import '../features/fall/data/fall_repository.dart';
import '../features/fall/data/fall_response_coordinator.dart';
import '../features/tracking/presentation/tracking_controller.dart';
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
        onOpenFallNotification: (FallNotificationPayload payload) {
          ref.read(routerProvider).go(_fallCheckLocation(payload));
        },
        onFallAction: (FallNotificationPayload payload, String feedback) {
          unawaited(_handleFallNotificationAction(payload, feedback));
        },
      );
      ref.read(pushStatusProvider.notifier).state = PushStatus(
        available: push.available,
        reason: push.reason,
      );
      final String? currentUserId = ref.read(authControllerProvider).user?.id;
      if (currentUserId != null &&
          ref.read(authControllerProvider).isAuthenticated) {
        unawaited(push.syncTokenForCurrentAccount(userId: currentUserId));
      }
      await ref
          .read(trackingControllerProvider.notifier)
          .retryPendingTrackingIntent();
    });
  }

  Future<void> _handleFallNotificationAction(
    FallNotificationPayload payload,
    String feedback,
  ) async {
    final int elapsed =
        DateTime.now().difference(payload.startedAt).inSeconds.clamp(0, 600);
    try {
      final bool submitted =
          await ref.read(fallResponseCoordinatorProvider).respond(
                eventId: payload.eventId,
                feedback: feedback,
                respondedWithinSec: elapsed,
              );
      if (!submitted) return;
    } catch (error) {
      debugPrint('پاسخ اعلان سقوط ثبت نشد: $error');
      if (mounted) {
        ref.read(routerProvider).go(
              _fallCheckLocation(
                payload,
                retryMode: true,
                retryMessage:
                    'پاسخ ثبت نشد. اتصال اینترنت را بررسی کنید و دوباره یکی از گزینه‌ها را بزنید.',
              ),
            );
      }
      return;
    }
    try {
      await ref.read(pushServiceProvider).cancelFallCheckNotification();
    } catch (error) {
      debugPrint('اعلان سقوط لغو نشد: $error');
    }
    ref.read(trackingControllerProvider.notifier).clearPendingFall();
    if (mounted) ref.read(routerProvider).go(AppRoutes.home);
  }

  String _fallCheckLocation(
    FallNotificationPayload payload, {
    bool retryMode = false,
    String? retryMessage,
  }) {
    final int remaining = payload.remainingSeconds(DateTime.now());
    return '${AppRoutes.fallCheck}?id=${Uri.encodeComponent(payload.eventId)}'
        '&sec=$remaining'
        '&startedAtMs=${payload.startedAt.millisecondsSinceEpoch}'
        '&deadlineMs=${payload.deadline.millisecondsSinceEpoch}'
        '${retryMode ? '&retry=1' : ''}'
        '${retryMessage == null ? '' : '&message=${Uri.encodeQueryComponent(retryMessage)}'}';
  }

  @override
  Widget build(BuildContext context) {
    final AccessibilitySettings a11y = ref.watch(accessibilityProvider);
    final GoRouter router = ref.watch(routerProvider);

    // لایه‌ی اتصال زنده باید در تمام عمر اپ زنده بماند، نه فقط وقتی صفحه‌ی
    // نقشه باز است: هشدار اضطراری باید در هر صفحه‌ای دریافت شود.
    ref.watch(realtimeControllerProvider);
    ref.listen<String?>(
      authControllerProvider.select((AuthState state) => state.user?.id),
      (String? previous, String? userId) {
        if (userId != null && userId != previous) {
          unawaited(
            ref
                .read(pushServiceProvider)
                .syncTokenForCurrentAccount(userId: userId)
                .catchError((Object error) {
              debugPrint('ثبت توکن اعلان پس از ورود شکست خورد: $error');
            }),
          );
          unawaited(
            ref
                .read(trackingControllerProvider.notifier)
                .retryPendingTrackingIntent(),
          );
        } else if (userId == null && previous != null) {
          unawaited(
            ref.read(pushServiceProvider).clearCurrentAccount(userId: previous),
          );
        }
      },
    );
    ref.listen<FallDetectResult?>(
      trackingControllerProvider
          .select((TrackingState state) => state.pendingFall),
      (FallDetectResult? previous, FallDetectResult? result) {
        if (result?.isFall == true) {
          router.go(
            '${AppRoutes.fallCheck}?id=${Uri.encodeComponent(result!.fallEventId)}&sec=${result.countdownSec}',
          );
        }
      },
    );
    ref.listen<LiveAlert?>(
      realtimeControllerProvider
          .select((RealtimeState state) => state.latestAlert),
      (LiveAlert? previous, LiveAlert? alert) {
        if (alert == null || alert.id == previous?.id) return;
        unawaited(
          ref
              .read(pushServiceProvider)
              .showAlertNotification(
                alertId: alert.id,
                type: alert.type,
                severity: alert.severity,
                title: alert.title,
                body: alert.body,
              )
              .catchError((Object error) {
            debugPrint('اعلان هشدار نمایش داده نشد: $error');
          }),
        );
      },
    );

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,

      theme: AppTheme.light(highContrast: a11y.highContrast),
      darkTheme: AppTheme.dark(highContrast: a11y.highContrast),
      // «تم سیستم» عمداً با «روشن» یکی است تا تنظیمات دستگاه ظاهر برنامه
      // را تغییر ندهد.
      themeMode:
          a11y.themeMode == ThemeMode.system ? ThemeMode.light : a11y.themeMode,

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
        final double effective = (systemScale * a11y.textScale)
            .clamp(0.8, SafeStepApp._maxEffectiveScale);

        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(effective)),
          child: Directionality(
            textDirection:
                a11y.localeCode == 'en' ? TextDirection.ltr : TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
