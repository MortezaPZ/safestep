import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/fall_features.dart';
import 'fall_repository.dart';

/// نمونه‌برداری حسگر + پیش‌غربال؛ رده‌بندی روی سرور است.
class FallDetectorService {
  FallDetectorService(
    this._repo, {
    Stream<AccelerometerEvent>? accelerometer,
    Stream<GyroscopeEvent>? gyroscope,
  })  : _accelerometer = accelerometer,
        _gyroscope = gyroscope;

  final FallRepository _repo;
  final Stream<AccelerometerEvent>? _accelerometer;
  final Stream<GyroscopeEvent>? _gyroscope;
  final List<List<double>> _acc = <List<double>>[];
  final List<List<double>> _gyro = <List<double>>[];
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  int _accStartIndex = 0;
  int _sampleCount = 0;
  int _lastProcessedPeak = -1;
  int? _candidatePeak;
  DateTime _lastPositive = DateTime.fromMillisecondsSinceEpoch(0);
  bool _evaluating = false;
  int screened = 0;
  int sent = 0;
  bool enabled = true;
  void Function(FallDetectResult result)? onPositive;

  Future<void> start() async {
    await stop();
    _acc.clear();
    _gyro.clear();
    _accStartIndex = 0;
    _sampleCount = 0;
    _lastProcessedPeak = -1;
    _candidatePeak = null;
    const Duration period = Duration(milliseconds: 20);
    _accSub = (_accelerometer ?? accelerometerEventStream(samplingPeriod: period))
        .listen((AccelerometerEvent e) {
      _acc.add(<double>[e.x, e.y, e.z]);
      _sampleCount += 1;
      _trimBuffers();
      unawaited(_maybeEvaluate());
    });
    _gyroSub = (_gyroscope ?? gyroscopeEventStream(samplingPeriod: period))
        .listen((GyroscopeEvent e) {
      _gyro.add(<double>[e.x, e.y, e.z]);
      _trimBuffers();
      unawaited(_maybeEvaluate());
    });
  }

  void _trimBuffers() {
    while (_acc.length > FallFeatures.windowSize * 2) {
      _acc.removeAt(0);
      _accStartIndex += 1;
    }
    while (_gyro.length > _acc.length + 1) {
      _gyro.removeAt(0);
    }
    while (_acc.length > _gyro.length + 1) {
      _acc.removeAt(0);
      _accStartIndex += 1;
    }
    while (_gyro.length > FallFeatures.windowSize * 2) {
      _gyro.removeAt(0);
    }
  }

  Future<void> stop() async {
    await _accSub?.cancel();
    await _gyroSub?.cancel();
    _accSub = null;
    _gyroSub = null;
  }

  Future<void> _maybeEvaluate() async {
    if (!enabled || _evaluating || _acc.length != _gyro.length) return;
    if (_candidatePeak == null && _acc.length >= FallFeatures.windowSize) {
      if (DateTime.now().difference(_lastPositive) < const Duration(seconds: 8)) {
        return;
      }
      final int start = _acc.length - FallFeatures.windowSize;
      final List<List<double>> accWindow = _acc.sublist(start);
      final List<List<double>> gyroWindow = _gyro.sublist(start);
      final int peak = FallFeatures.peakIndex(accWindow);
      final List<double> features = FallFeatures.extract(acc: accWindow, gyro: gyroWindow);
      screened += 1;
      if (!FallFeatures.preScreen(features) ||
          peak < FallFeatures.windowSize * 0.15 ||
          peak > FallFeatures.windowSize * 0.85) {
        return;
      }
      final int globalPeak = _accStartIndex + start + peak;
      if (globalPeak <= _lastProcessedPeak) return;
      _candidatePeak = globalPeak;
    }

    final int? peak = _candidatePeak;
    if (peak == null || _sampleCount <= peak + 2 * FallFeatures.hz) return;

    final int from = peak - FallFeatures.windowSize ~/ 2 - _accStartIndex;
    if (from < 0 || from + FallFeatures.windowSize > _acc.length) return;
    final List<double> features = FallFeatures.extract(
      acc: _acc.sublist(from, from + FallFeatures.windowSize),
      gyro: _gyro.sublist(from, from + FallFeatures.windowSize),
    );
    _candidatePeak = null;
    _lastProcessedPeak = peak;
    _evaluating = true;
    sent += 1;
    try {
      final FallDetectResult result = await _repo.detect(features);
      if (result.isFall) {
        _lastPositive = DateTime.now();
        onPositive?.call(result);
      }
    } catch (error) {
      debugPrint('ارسال ویژگی سقوط ناموفق: $error');
    } finally {
      _evaluating = false;
    }
  }
}
