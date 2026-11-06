import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fall_repository.dart';

/// یک پاسخ برای هر رخداد سقوط، حتی اگر صفحه و اعلان هم‌زمان پاسخ دهند.
class FallResponseCoordinator {
  FallResponseCoordinator(this._repository);

  final FallRepository _repository;
  final Set<String> _inFlightEventIds = <String>{};
  final LinkedHashSet<String> _submittedEventIds = LinkedHashSet<String>();

  Future<bool> respond({
    required String eventId,
    required String feedback,
    required int respondedWithinSec,
  }) async {
    if (_submittedEventIds.contains(eventId)) return true;
    if (!_inFlightEventIds.add(eventId)) return false;
    try {
      await _repository.feedback(
        id: eventId,
        feedback: feedback,
        respondedWithinSec: respondedWithinSec.clamp(0, 600),
      );
      _submittedEventIds.add(eventId);
      while (_submittedEventIds.length > 100) {
        _submittedEventIds.remove(_submittedEventIds.first);
      }
      return true;
    } finally {
      // A failed request may be retried by the page or the notification action.
      _inFlightEventIds.remove(eventId);
    }
  }
}

final Provider<FallResponseCoordinator> fallResponseCoordinatorProvider =
    Provider<FallResponseCoordinator>((ref) {
  return FallResponseCoordinator(ref.watch(fallRepositoryProvider));
});
