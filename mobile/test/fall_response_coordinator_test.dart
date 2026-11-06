import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/utils/app_exception.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/fall/data/fall_response_coordinator.dart';

class _RecordingFallRepository extends FallRepository {
  int feedbackCalls = 0;
  final Completer<void> response = Completer<void>();

  @override
  Future<void> feedback({
    required String id,
    required String feedback,
    int? respondedWithinSec,
  }) {
    feedbackCalls += 1;
    return response.future;
  }
}

class _RetryingFallRepository extends FallRepository {
  int feedbackCalls = 0;

  @override
  Future<void> feedback({
    required String id,
    required String feedback,
    int? respondedWithinSec,
  }) async {
    feedbackCalls += 1;
    if (feedbackCalls == 1) throw AppException.network;
  }
}

void main() {
  test('submits only one response when page and notification race', () async {
    final _RecordingFallRepository repository = _RecordingFallRepository();
    final FallResponseCoordinator coordinator =
        FallResponseCoordinator(repository);

    final Future<bool> pageResponse = coordinator.respond(
      eventId: 'fall-event-1',
      feedback: 'false_alarm',
      respondedWithinSec: 4,
    );
    final bool notificationResponse = await coordinator.respond(
      eventId: 'fall-event-1',
      feedback: 'confirmed',
      respondedWithinSec: 5,
    );

    expect(notificationResponse, isFalse);
    expect(repository.feedbackCalls, 1);
    repository.response.complete();
    expect(await pageResponse, isTrue);
    expect(repository.feedbackCalls, 1);
  });

  test('keeps an unsuccessful response retryable and records the retry',
      () async {
    final _RetryingFallRepository repository = _RetryingFallRepository();
    final FallResponseCoordinator coordinator =
        FallResponseCoordinator(repository);

    await expectLater(
      coordinator.respond(
        eventId: 'fall-event-2',
        feedback: 'confirmed',
        respondedWithinSec: 9,
      ),
      throwsA(isA<AppException>()),
    );

    expect(
      await coordinator.respond(
        eventId: 'fall-event-2',
        feedback: 'confirmed',
        respondedWithinSec: 10,
      ),
      isTrue,
    );
    expect(repository.feedbackCalls, 2);
  });
}
