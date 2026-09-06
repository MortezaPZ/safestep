import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/fall_features.dart';
import 'fall_repository.dart';

/// نمونه‌برداری حسگر + پیش‌غربال؛ رده‌بندی روی سرور است.
class FallDetectorService {
  FallDetectorService(this._repo);

  final FallRepository _repo;
  final List<List<double>> _acc = <List<double>>[];
  final List<List<double>> _gyro = <List<double>>[];
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  int screened = 0;
  int sent = 0;
  bool enabled = true;
  void Function(FallDetectResult result)? onPositive;

  Future<void> start() async {
    await stop();
    const Duration period = Duration(milliseconds: 20);
    _accSub = accelerometerEventStream(samplingPeriod: period).listen((AccelerometerEvent e) {
      _acc.add(<double>[e.x, e.y, e.z]);
      if (_acc.length > FallFeatures.windowSize) {
        _acc.removeAt(0);
      }
      unawaited(_maybeEvaluate());
    });
    _gyroSub = gyroscopeEventStream(samplingPeriod: period).listen((GyroscopeEvent e) {
      _gyro.add(<double>[e.x, e.y, e.z]);
      if (_gyro.length > FallFeatures.windowSize) {
        _gyro.removeAt(0);
      }
    });
  }

  Future<void> stop() async {
    await _accSub?.cancel();
    await _gyroSub?.cancel();
    _accSub = null;
    _gyroSub = null;
  }

  Future<void> _maybeEvaluate() async {
    if (!enabled) return;
    if (_acc.length < FallFeatures.windowSize || _gyro.length < FallFeatures.windowSize) {
      return;
    }
    if (DateTime.now().difference(_lastSent) < const Duration(seconds: 8)) return;
    final List<double> features = FallFeatures.extract(acc: _acc, gyro: _gyro);
    screened += 1;
    if (!FallFeatures.preScreen(features)) return;
    sent += 1;
    _lastSent = DateTime.now();
    try {
      final FallDetectResult result = await _repo.detect(features);
      if (result.isFall) {
        onPositive?.call(result);
      }
    } catch (error) {
      debugPrint('ارسال ویژگی سقوط ناموفق: $error');
    }
  }
}
