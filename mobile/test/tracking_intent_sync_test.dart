import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safestep/features/tracking/data/tracking_intent_sync.dart';

class _MemoryTrackingIntentStore implements TrackingIntentStore {
  final Map<String, bool> pending = <String, bool>{};

  @override
  Future<bool?> readPending(String userId) async => pending[userId];

  @override
  Future<void> writePending(String userId, bool active) async {
    pending[userId] = active;
  }

  @override
  Future<void> clearPending(String userId) async {
    pending.remove(userId);
  }
}

void main() {
  test('serializes a late start before the newer stop intent', () async {
    final _MemoryTrackingIntentStore store = _MemoryTrackingIntentStore();
    final Completer<void> allowStartResponse = Completer<void>();
    final Completer<void> startRequestEntered = Completer<void>();
    final List<bool> sent = <bool>[];
    final TrackingIntentSynchronizer sync = TrackingIntentSynchronizer(
      store: store,
      currentUserId: () => 'user-1',
      send: (bool active) async {
        sent.add(active);
        if (active) {
          startRequestEntered.complete();
          await allowStartResponse.future;
        }
      },
    );

    final Future<void> start =
        sync.setDesiredState(userId: 'user-1', active: true);
    await startRequestEntered.future;
    final Future<void> stop =
        sync.setDesiredState(userId: 'user-1', active: false);
    allowStartResponse.complete();
    await Future.wait(<Future<void>>[start, stop]);

    expect(sent, <bool>[true, false]);
    expect(store.pending, isEmpty);
  });

  test('persists a failed stop and retries it after connectivity returns',
      () async {
    final _MemoryTrackingIntentStore store = _MemoryTrackingIntentStore();
    final List<String?> messages = <String?>[];
    final List<bool> sent = <bool>[];
    bool fail = true;
    final TrackingIntentSynchronizer sync = TrackingIntentSynchronizer(
      store: store,
      currentUserId: () => 'user-1',
      onStatus: messages.add,
      send: (bool active) async {
        sent.add(active);
        if (fail) throw StateError('offline');
      },
    );

    await sync.setDesiredState(userId: 'user-1', active: false);
    expect(store.pending['user-1'], isFalse);
    expect(messages.last, contains('توقف ردیابی به سرور اعلام نشد'));

    fail = false;
    await sync.retryPending('user-1');

    expect(sent, <bool>[false, false]);
    expect(store.pending, isEmpty);
    expect(messages.last, isNull);
  });

  test('keeps the latest per-user intent until that user can authenticate',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferencesTrackingIntentStore store =
        SharedPreferencesTrackingIntentStore();
    String? currentUserId;
    final List<bool> sent = <bool>[];
    final TrackingIntentSynchronizer sync = TrackingIntentSynchronizer(
      store: store,
      currentUserId: () => currentUserId,
      send: (bool active) async {
        sent.add(active);
      },
    );

    await sync.setDesiredState(userId: 'user-1', active: false);
    expect(await store.readPending('user-1'), isFalse);
    expect(sent, isEmpty);

    currentUserId = 'user-1';
    await sync.retryPending('user-1');
    expect(sent, <bool>[false]);
    expect(await store.readPending('user-1'), isNull);
  });
}
