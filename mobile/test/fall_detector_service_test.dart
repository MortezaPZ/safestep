import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:safestep/features/fall/data/fall_detector_service.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';

class RecordingFallRepository extends FallRepository {
  final List<List<double>> requests = <List<double>>[];

  @override
  Future<FallDetectResult> detect(List<double> features) async {
    requests.add(features);
    return const FallDetectResult(
      isFall: false,
      fallEventId: 'test-event',
      countdownSec: 30,
    );
  }
}

void main() {
  test('waits for post-impact samples and sends a centered fall window', () async {
    final StreamController<AccelerometerEvent> accelerometer =
        StreamController<AccelerometerEvent>.broadcast(sync: true);
    final StreamController<GyroscopeEvent> gyroscope =
        StreamController<GyroscopeEvent>.broadcast(sync: true);
    final RecordingFallRepository repository = RecordingFallRepository();
    final FallDetectorService detector = FallDetectorService(
      repository,
      accelerometer: accelerometer.stream,
      gyroscope: gyroscope.stream,
    );

    await detector.start();
    final DateTime timestamp = DateTime(2026);
    for (int i = 0; i < 200; i += 1) {
      final List<double> sample = i < 100
          ? <double>[0, 0, 9.80665]
          : i < 110
              ? <double>[0, 0, 0]
              : i == 110
                  ? <double>[0, 0, 9.80665 * 30]
                  : <double>[9.80665, 0, 0];
      accelerometer.add(AccelerometerEvent(
        sample[0], sample[1], sample[2], timestamp.add(Duration(milliseconds: i * 20)),
      ));
      gyroscope.add(GyroscopeEvent(
        0, 0, 0, timestamp.add(Duration(milliseconds: i * 20)),
      ));
    }

    expect(repository.requests, isEmpty);

    for (int i = 200; i <= 210; i += 1) {
      accelerometer.add(AccelerometerEvent(
        9.80665, 0, 0, timestamp.add(Duration(milliseconds: i * 20)),
      ));
      gyroscope.add(GyroscopeEvent(
        0, 0, 0, timestamp.add(Duration(milliseconds: i * 20)),
      ));
    }
    await Future<void>.delayed(Duration.zero);

    expect(repository.requests, hasLength(1));
    expect(repository.requests.single, hasLength(14));
    expect(repository.requests.single[5], closeTo(0.5, 0.02));

    await detector.stop();
    await accelerometer.close();
    await gyroscope.close();
  });
}
