import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/fa.dart';
import '../data/fall_repository.dart';

/// صفحه‌ی تمام‌صفحه پس از تشخیص مثبت: شمارش معکوس و دو دکمه‌ی درشت.
class FallCheckPage extends ConsumerStatefulWidget {
  const FallCheckPage({
    super.key,
    required this.fallEventId,
    this.countdownSec = 30,
  });

  final String fallEventId;
  final int countdownSec;

  @override
  ConsumerState<FallCheckPage> createState() => FallCheckPageState();
}

class FallCheckPageState extends ConsumerState<FallCheckPage> {
  late int _left;
  Timer? _timer;
  bool _submitted = false;
  DateTime? _started;

  @override
  void initState() {
    super.initState();
    _left = widget.countdownSec;
    _started = DateTime.now();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _submitted) return;
      setState(() => _left -= 1);
      if (_left <= 0) {
        unawaited(_send('no_response'));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send(String feedback) async {
    if (_submitted) return;
    _submitted = true;
    _timer?.cancel();
    final int elapsed = DateTime.now().difference(_started ?? DateTime.now()).inSeconds;
    try {
      await ref.read(fallRepositoryProvider).feedback(
            id: widget.fallEventId,
            feedback: feedback,
            respondedWithinSec: elapsed.clamp(0, 600),
          );
    } catch (_) {
      // حتی اگر شبکه قطع باشد صفحه بسته می‌شود؛ watchdog سرور پشتیبان است
    }
    if (mounted) {
      final GoRouter? router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go(AppRoutes.home);
      } else {
        Navigator.of(context).maybePop();
      }
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
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                label: 'مانده ${Fa.digits(_left.toString())} ثانیه',
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
              const Spacer(),
              SizedBox(
                height: 72,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: () => _send('false_alarm'),
                  child: Text(
                    'حالم خوب است',
                    style: TextStyle(color: AppColors.danger, fontSize: 22),
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
                  onPressed: () => _send('confirmed'),
                  child: const Text('کمک می‌خواهم', style: TextStyle(fontSize: 22)),
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
