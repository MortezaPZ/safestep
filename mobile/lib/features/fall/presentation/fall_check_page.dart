import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../../../core/push/push_service.dart';
import '../data/fall_response_coordinator.dart';
import '../../tracking/presentation/tracking_controller.dart';

/// صفحه‌ی تمام‌صفحه پس از تشخیص مثبت: شمارش معکوس و دو دکمه‌ی درشت.
class FallCheckPage extends ConsumerStatefulWidget {
  const FallCheckPage({
    super.key,
    required this.fallEventId,
    this.countdownSec = 30,
    this.startedAt,
    this.deadline,
    this.retryMode = false,
    this.retryMessage,
  });

  final String fallEventId;
  final int countdownSec;
  final DateTime? startedAt;
  final DateTime? deadline;
  final bool retryMode;
  final String? retryMessage;

  @override
  ConsumerState<FallCheckPage> createState() => FallCheckPageState();
}

class FallCheckPageState extends ConsumerState<FallCheckPage> {
  late int _left;
  Timer? _timer;
  bool _submitted = false;
  bool _sending = false;
  bool _retryMode = false;
  String? _responseError;
  DateTime? _started;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _started = widget.startedAt ?? now;
    _deadline = widget.deadline ??
        _started!.add(Duration(seconds: widget.countdownSec));
    _left = _remainingSeconds(now);
    _retryMode = widget.retryMode;
    _responseError = widget.retryMessage;
    HapticFeedback.heavyImpact();
    unawaited(_showFallNotification());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _submitted) return;
      setState(() => _left = _remainingSeconds(DateTime.now()));
      if (_left <= 0 && !_retryMode) {
        unawaited(_send('no_response'));
      }
    });
  }

  @override
  void didUpdateWidget(covariant FallCheckPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.retryMode && !_retryMode) {
      _retryMode = true;
      _timer?.cancel();
    }
  }

  int _remainingSeconds(DateTime now) {
    final int remaining = _deadline!.difference(now).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _showFallNotification() async {
    try {
      await ref.read(pushServiceProvider).showFallCheckNotification(
            eventId: widget.fallEventId,
            startedAt: _started!,
            deadline: _deadline!,
          );
    } catch (error) {
      debugPrint('اعلان بررسی سقوط نمایش داده نشد: $error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send(String feedback) async {
    if (_submitted || _sending) return;
    _sending = true;
    _timer?.cancel();
    final int elapsed =
        DateTime.now().difference(_started ?? DateTime.now()).inSeconds;
    final FallResponseCoordinator coordinator =
        ref.read(fallResponseCoordinatorProvider);
    final TrackingController tracking =
        ref.read(trackingControllerProvider.notifier);
    final PushService push = ref.read(pushServiceProvider);
    try {
      final bool submitted = await coordinator.respond(
                eventId: widget.fallEventId,
                feedback: feedback,
                respondedWithinSec: elapsed,
              );
      if (!submitted) {
        _responseError = 'پاسخ دیگری در حال ثبت است. کمی صبر کنید.';
        return;
      }
      _submitted = true;
      if (tracking.mounted) tracking.clearPendingFall();
      try {
        await push.cancelFallCheckNotification();
      } catch (error) {
        debugPrint('اعلان سقوط لغو نشد: $error');
      }
      if (mounted) {
        final GoRouter? router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go(AppRoutes.home);
        } else {
          Navigator.of(context).maybePop();
        }
      }
    } catch (error) {
      _retryMode = true;
      _responseError = error is AppException
          ? error.message
          : 'پاسخ ثبت نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.';
    } finally {
      _sending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.danger,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 24),
              Text(
                'آیا حال شما خوب است؟',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 24),
              if (_responseError != null || _retryMode) ...<Widget>[
                Text(
                  _responseError ??
                      'پاسخ هنوز ثبت نشده است. اتصال را بررسی کنید و دوباره یکی از گزینه‌ها را بزنید.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: 'مانده ${Fa.digits(_left.toString())} ثانیه',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Fa.digits(_left.toString()),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 96,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 72,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: _sending ? null : () => _send('false_alarm'),
                  child: _sending
                      ? const CircularProgressIndicator()
                      : Text(
                          'حالم خوب است',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 22,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 72,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 2),
                  ),
                  onPressed: _sending ? null : () => _send('confirmed'),
                  child: _sending
                      ? const CircularProgressIndicator()
                      : const Text(
                          'کمک می‌خواهم',
                          style: TextStyle(fontSize: 22),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
