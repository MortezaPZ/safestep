import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:safestep/features/fall/data/fall_detector_service.dart';
import 'package:safestep/features/fall/data/fall_request_limiter.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/tracking/domain/location_sample.dart';

class RecordingFallRepository extends FallRepository {
  RecordingFallRepository();

  final List<List<double>> requests = <List<double>>[];
  final List<LocationSample?> locations = <LocationSample?>[];

  @override
  Future<FallDetectResult> detect(
    List<double> features, {
    LocationSample? location,
  }) async {
    requests.add(features);
    locations.add(location);
    return const FallDetectResult(
      isFall: false,
      fallEventId: 'test-event',
      countdownSec: 30,
    );
  }
}

class PositiveFallRepository extends RecordingFallRepository {
  PositiveFallRepository();

  @override
  Future<FallDetectResult> detect(
    List<double> features, {
    LocationSample? location,
  }) async {
    requests.add(features);
    locations.add(location);
    return const FallDetectResult(
      isFall: true,
      fallEventId: 'test-event',
      countdownSec: 30,
    );
  }
}

void _emitSamplePair(
  StreamController<AccelerometerEvent> accelerometer,
  StreamController<GyroscopeEvent> gyroscope,
  int index,
  List<double> acceleration,
) {
  final DateTime timestamp =
      DateTime(2026).add(Duration(milliseconds: index * 20));
  accelerometer.add(AccelerometerEvent(
    acceleration[0],
    acceleration[1],
    acceleration[2],
    timestamp,
  ));
  gyroscope.add(GyroscopeEvent(0, 0, 0, timestamp));
}

void main() {
  test('waits for post-impact samples and sends a centered fall window',
      () async {
    final StreamController<AccelerometerEvent> accelerometer =
        StreamController<AccelerometerEvent>.broadcast(sync: true);
    final StreamController<GyroscopeEvent> gyroscope =
        StreamController<GyroscopeEvent>.broadcast(sync: true);
    final RecordingFallRepository repository = RecordingFallRepository();
    final DateTime timestamp = DateTime(2026);
    final LocationSample location = LocationSample(
      clientUuid: 'sample-1',
      lat: 35.7,
      lng: 51.4,
      recordedAt: timestamp,
      accuracyM: 7,
    );
    final FallDetectorService detector = FallDetectorService(
      repository,
      accelerometer: accelerometer.stream,
      gyroscope: gyroscope.stream,
      currentLocation: () => location,
    );

    await detector.start();
    for (int i = 0; i < 200; i += 1) {
      final List<double> sample = i < 100
          ? <double>[0, 0, 9.80665]
          : i < 110
              ? <double>[0, 0, 0]
              : i == 110
                  ? <double>[0, 0, 9.80665 * 30]
                  : <double>[9.80665, 0, 0];
      accelerometer.add(AccelerometerEvent(
        sample[0],
        sample[1],
        sample[2],
        timestamp.add(Duration(milliseconds: i * 20)),
      ));
      gyroscope.add(GyroscopeEvent(
        0,
        0,
        0,
        timestamp.add(Duration(milliseconds: i * 20)),
      ));
    }

    expect(repository.requests, isEmpty);

    for (int i = 200; i <= 210; i += 1) {
      accelerometer.add(AccelerometerEvent(
        9.80665,
        0,
        0,
        timestamp.add(Duration(milliseconds: i * 20)),
      ));
      gyroscope.add(GyroscopeEvent(
        0,
        0,
        0,
        timestamp.add(Duration(milliseconds: i * 20)),
      ));
    }
    await Future<void>.delayed(Duration.zero);

    expect(repository.requests, hasLength(1));
    expect(repository.requests.single, hasLength(14));
    expect(repository.requests.single[5], closeTo(0.5, 0.02));
    expect(repository.locations.single?.lat, 35.7);
    expect(repository.locations.single?.lng, 51.4);

    await detector.stop();
    await accelerometer.close();
    await gyroscope.close();
  });

  test('clears a candidate whose centered window has fallen before the buffer',
      () async {
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
    for (int i = 0; i < 400; i += 1) {
      final bool inFreeFall = (i >= 20 && i < 30) || (i >= 240 && i < 250);
      final bool impact = i == 30 || i == 250;
      final List<double> acceleration = inFreeFall
          ? <double>[0, 0, 0]
          : impact
              ? <double>[0, 0, 9.80665 * 30]
              : <double>[9.80665, 0, 0];
      _emitSamplePair(accelerometer, gyroscope, i, acceleration);
    }
    await Future<void>.delayed(Duration.zero);

    expect(repository.requests, hasLength(1));

    await detector.stop();
    await accelerometer.close();
    await gyroscope.close();
  });

  test('does not send another fall while the response countdown is active',
      () async {
    final StreamController<AccelerometerEvent> accelerometer =
        StreamController<AccelerometerEvent>.broadcast(sync: true);
    final StreamController<GyroscopeEvent> gyroscope =
        StreamController<GyroscopeEvent>.broadcast(sync: true);
    final PositiveFallRepository repository = PositiveFallRepository();
    DateTime now = DateTime(2026);
    bool countdownActive = false;
    final FallDetectorService detector = FallDetectorService(
      repository,
      accelerometer: accelerometer.stream,
      gyroscope: gyroscope.stream,
      now: () => now,
      isFallCheckActive: () => countdownActive,
    )..onPositive = (_) => countdownActive = true;

    await detector.start();
    for (int i = 0; i <= 211; i += 1) {
      final List<double> acceleration = i >= 100 && i < 110
          ? <double>[0, 0, 0]
          : i == 110
              ? <double>[0, 0, 9.80665 * 30]
              : <double>[9.80665, 0, 0];
      _emitSamplePair(accelerometer, gyroscope, i, acceleration);
    }
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(1));
    expect(countdownActive, isTrue);

    now = now.add(const Duration(seconds: 10));
    for (int i = 212; i <= 430; i += 1) {
      final List<double> acceleration = i >= 310 && i < 320
          ? <double>[0, 0, 0]
          : i == 320
              ? <double>[0, 0, 9.80665 * 30]
              : <double>[9.80665, 0, 0];
      _emitSamplePair(accelerometer, gyroscope, i, acceleration);
    }
    await Future<void>.delayed(Duration.zero);

    expect(repository.requests, hasLength(1));
    await detector.stop();
    await accelerometer.close();
    await gyroscope.close();
  });

  test('reports sensor stream failures so the app can show a warning',
      () async {
    final StreamController<AccelerometerEvent> accelerometer =
        StreamController<AccelerometerEvent>.broadcast(sync: true);
    final StreamController<GyroscopeEvent> gyroscope =
        StreamController<GyroscopeEvent>.broadcast(sync: true);
    final FallDetectorService detector = FallDetectorService(
      RecordingFallRepository(),
      accelerometer: accelerometer.stream,
      gyroscope: gyroscope.stream,
    );
    String? unavailableSensor;
    detector.onSensorError = (String sensor) => unavailableSensor = sensor;

    await detector.start();
    gyroscope.addError(StateError('sensor unavailable'));
    await Future<void>.delayed(Duration.zero);

    expect(unavailableSensor, 'ژیروسکوپ');
    expect(detector.enabled, isFalse);
    await detector.stop();
    await accelerometer.close();
    await gyroscope.close();
  });

  test('keeps ordinary sends below the server rate limit', () {
    final FallRequestLimiter limiter = FallRequestLimiter();
    final DateTime start = DateTime(2026);

    expect(limiter.canSend(start), isTrue);
    expect(limiter.canSend(start.add(const Duration(seconds: 6))), isFalse);
    for (int second = 7; second <= 56; second += 7) {
      expect(limiter.canSend(start.add(Duration(seconds: second))), isTrue);
    }
    expect(limiter.canSend(start.add(const Duration(seconds: 57))), isFalse);
    expect(limiter.canSend(start.add(const Duration(seconds: 63))), isTrue);
  });
}
