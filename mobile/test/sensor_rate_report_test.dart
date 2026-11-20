import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/utils/sensor_rate_logger.dart';

void main() {
  test('محاسبه صحیح فرکانس و فواصل نمونه‌برداری سنسورها', () {
    final SensorRateReport report = SensorRateReport(
      elapsedMs: 10000,
      accSamples: 500,
      gyroSamples: 495,
      accIntervals: <int>[20, 20, 20],
      gyroIntervals: <int>[20, 21, 19],
    );

    expect(report.accHz, closeTo(50.0, 0.1));
    expect(report.gyroHz, closeTo(49.5, 0.1));
    expect(report.meanAccInterval, equals(20.0));
    expect(report.meanGyroInterval, equals(20.0));
    expect(report.toString().contains('فرکانس موثر: 50.00 Hz'), isTrue);
  });
}
