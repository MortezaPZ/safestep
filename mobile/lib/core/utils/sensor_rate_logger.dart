import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// ابزار اندازه‌گیری و ثبت نرخ واقعی نمونه‌برداری سنسورهای فیزیکی گوشی.
///
/// این کلاس فاصله‌ی زمانی بین رویدادهای دریافتی از سخت‌افزار شتاب‌سنج و
/// ژیروسکوپ را در یک بازه مشخص ثبت کرده و فرکانس واقعی (Hz) را محاسبه می‌کند.
class SensorRateLogger {
  SensorRateLogger({
    this.targetPeriod = const Duration(milliseconds: 20),
    this.measurementDuration = const Duration(seconds: 10),
  });

  final Duration targetPeriod;
  final Duration measurementDuration;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  final List<int> _accTimestamps = <int>[];
  final List<int> _gyroTimestamps = <int>[];

  Future<SensorRateReport> measure() async {
    _accTimestamps.clear();
    _gyroTimestamps.clear();

    final Completer<void> completer = Completer<void>();

    final int startMs = DateTime.now().millisecondsSinceEpoch;

    _accSub = accelerometerEventStream(samplingPeriod: targetPeriod).listen((event) {
      _accTimestamps.add(DateTime.now().millisecondsSinceEpoch);
    });

    _gyroSub = gyroscopeEventStream(samplingPeriod: targetPeriod).listen((event) {
      _gyroTimestamps.add(DateTime.now().millisecondsSinceEpoch);
    });

    Timer(measurementDuration, () async {
      await _accSub?.cancel();
      await _gyroSub?.cancel();
      completer.complete();
    });

    await completer.future;

    final int elapsedMs = DateTime.now().millisecondsSinceEpoch - startMs;
    return SensorRateReport(
      elapsedMs: elapsedMs,
      accSamples: _accTimestamps.length,
      gyroSamples: _gyroTimestamps.length,
      accIntervals: _calculateIntervals(_accTimestamps),
      gyroIntervals: _calculateIntervals(_gyroTimestamps),
    );
  }

  List<int> _calculateIntervals(List<int> timestamps) {
    if (timestamps.length < 2) return <int>[];
    final List<int> intervals = <int>[];
    for (int i = 1; i < timestamps.length; i++) {
      intervals.add(timestamps[i] - timestamps[i - 1]);
    }
    return intervals;
  }
}

class SensorRateReport {
  SensorRateReport({
    required this.elapsedMs,
    required this.accSamples,
    required this.gyroSamples,
    required this.accIntervals,
    required this.gyroIntervals,
  });

  final int elapsedMs;
  final int accSamples;
  final int gyroSamples;
  final List<int> accIntervals;
  final List<int> gyroIntervals;

  double get accHz => elapsedMs > 0 ? (accSamples / (elapsedMs / 1000.0)) : 0.0;
  double get gyroHz => elapsedMs > 0 ? (gyroSamples / (elapsedMs / 1000.0)) : 0.0;

  double get meanAccInterval => accIntervals.isNotEmpty
      ? accIntervals.reduce((a, b) => a + b) / accIntervals.length
      : 0.0;

  double get meanGyroInterval => gyroIntervals.isNotEmpty
      ? gyroIntervals.reduce((a, b) => a + b) / gyroIntervals.length
      : 0.0;

  @override
  String toString() {
    return '''
══════════════════════════════════════════════════
گزارش نرخ نمونه‌برداری سنسورهای گوشی (مدت: ${elapsedMs / 1000} ثانیه)
──────────────────────────────────────────────────
• شتاب‌سنج (Accelerometer):
  - تعداد نمونه: $accSamples
  - فرکانس موثر: ${accHz.toStringAsFixed(2)} Hz
  - میانگین بازه زمانی: ${meanAccInterval.toStringAsFixed(1)} ms
• ژیروسکوپ (Gyroscope):
  - تعداد نمونه: $gyroSamples
  - فرکانس موثر: ${gyroHz.toStringAsFixed(2)} Hz
  - میانگین بازه زمانی: ${meanGyroInterval.toStringAsFixed(1)} ms
══════════════════════════════════════════════════
''';
  }
}
