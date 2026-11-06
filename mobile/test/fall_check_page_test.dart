import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/push/push_service.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/fall/data/fall_response_coordinator.dart';
import 'package:safestep/features/fall/presentation/fall_check_page.dart';
import 'package:safestep/features/tracking/data/tracking_intent_sync.dart';
import 'package:safestep/features/tracking/presentation/tracking_controller.dart';

class _ControlledFallRepository extends FallRepository {
  final Completer<void> response = Completer<void>();
  int feedbackCalls = 0;

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

class _NoopPushService extends PushService {
  @override
  Future<void> showFallCheckNotification({
    required String eventId,
    required DateTime startedAt,
    required DateTime deadline,
  }) async {}

  @override
  Future<void> cancelFallCheckNotification() async {}
}

class _NoopTrackingIntentStore implements TrackingIntentStore {
  @override
  Future<void> clearPending(String userId) async {}

  @override
  Future<bool?> readPending(String userId) async => null;

  @override
  Future<void> writePending(String userId, bool active) async {}
}

class _TestTrackingController extends TrackingController {
  _TestTrackingController(Ref ref)
      : super(ref, trackingIntentStore: _NoopTrackingIntentStore()) {
    state = state.copyWith(
      pendingFall: const FallDetectResult(
        isFall: true,
        fallEventId: 'fall-test-1',
        countdownSec: 300,
      ),
    );
  }
}

Future<void> _openFallPage(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const FallCheckPage(
                    fallEventId: 'fall-test-1',
                    countdownSec: 300,
                  ),
                ),
              ),
              child: const Text('Open fall check'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open fall check'));
  await tester.pumpAndSettle();
}

ProviderContainer _makeContainer(_ControlledFallRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      fallResponseCoordinatorProvider.overrideWithValue(
        FallResponseCoordinator(repository),
      ),
      pushServiceProvider.overrideWithValue(_NoopPushService()),
      trackingControllerProvider.overrideWith(
        (Ref ref) => _TestTrackingController(ref),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'leaving before feedback succeeds keeps pendingFall; success clears it',
    (WidgetTester tester) async {
      final _ControlledFallRepository repository = _ControlledFallRepository();
      final ProviderContainer container = _makeContainer(repository);
      addTearDown(container.dispose);

      await _openFallPage(tester, container);
      expect(
        container.read(trackingControllerProvider).pendingFall?.fallEventId,
        'fall-test-1',
      );

      await tester.tap(find.text('حالم خوب است'));
      await tester.pump();
      expect(repository.feedbackCalls, 1);

      // The server response is still pending; leaving the page must not
      // acknowledge the fall locally.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(
        container.read(trackingControllerProvider).pendingFall?.fallEventId,
        'fall-test-1',
      );

      repository.response.complete();
      await tester.pump();
      expect(container.read(trackingControllerProvider).pendingFall, isNull);
    },
  );

  testWidgets('failed feedback leaves pendingFall available for retry', (
    WidgetTester tester,
  ) async {
    final _ControlledFallRepository repository = _ControlledFallRepository();
    final ProviderContainer container = _makeContainer(repository);
    addTearDown(container.dispose);

    await _openFallPage(tester, container);
    await tester.tap(find.text('حالم خوب است'));
    await tester.pump();
    repository.response.completeError(Exception('network unavailable'));
    await tester.pump();

    expect(
      container.read(trackingControllerProvider).pendingFall?.fallEventId,
      'fall-test-1',
    );
  });
}
