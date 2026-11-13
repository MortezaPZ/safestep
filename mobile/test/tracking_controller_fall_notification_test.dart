import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/push/push_service.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/tracking/presentation/tracking_controller.dart';

class _RecordingPushService extends PushService {
  _RecordingPushService(this.events, this.scheduleCompleter);

  final List<String> events;
  final Completer<void> scheduleCompleter;
  DateTime? startedAt;
  DateTime? deadline;
  String? eventId;
  int scheduleCalls = 0;

  @override
  Future<void> showFallCheckNotification({
    required String eventId,
    required DateTime startedAt,
    required DateTime deadline,
  }) async {
    scheduleCalls += 1;
    this.eventId = eventId;
    this.startedAt = startedAt;
    this.deadline = deadline;
    events.add('notification');
    await scheduleCompleter.future;
  }
}

void main() {
  test('accepted fall completes countdown scheduling before navigation state',
      () async {
    final List<String> events = <String>[];
    final Completer<void> scheduleCompleter = Completer<void>();
    final _RecordingPushService push =
        _RecordingPushService(events, scheduleCompleter);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pushServiceProvider.overrideWithValue(push),
      ],
    );
    addTearDown(container.dispose);

    final TrackingController controller =
        container.read(trackingControllerProvider.notifier);
    controller.addListener((TrackingState state) {
      if (state.pendingFall != null) events.add('navigation-state');
    });

    const FallDetectResult result = FallDetectResult(
      isFall: true,
      fallEventId: 'fall-background-test',
      countdownSec: 300,
    );
    final Future<void> acceptingFall = controller.acceptFallDetection(result);
    expect(events, <String>['notification']);
    expect(controller.state.pendingFall, isNull);

    scheduleCompleter.complete();
    await acceptingFall;

    expect(events, <String>['notification', 'navigation-state']);
    expect(push.scheduleCalls, 1);
    expect(push.eventId, result.fallEventId);
    expect(push.deadline!.difference(push.startedAt!),
        const Duration(seconds: 300));
    expect(controller.state.pendingFall, result);

    await controller.acceptFallDetection(result);
    expect(push.scheduleCalls, 1);
  });
}
