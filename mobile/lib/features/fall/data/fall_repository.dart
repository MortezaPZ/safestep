import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/domain/auth_models.dart';

@immutable
class FallDetectResult {
  const FallDetectResult({
    required this.isFall,
    required this.fallEventId,
    required this.countdownSec,
  });

  final bool isFall;
  final String fallEventId;
  final int countdownSec;

  factory FallDetectResult.fromJson(Map<String, dynamic> json) {
    return FallDetectResult(
      isFall: Json.boolOf(json, 'isFall'),
      fallEventId: Json.str(json, 'fallEventId'),
      countdownSec: Json.intOf(json, 'countdownSec', 30),
    );
  }
}

class FallRepository {
  FallRepository([this._api]);
  final ApiClient? _api;

  Future<FallDetectResult> detect(List<double> features) {
    return _api!.post<FallDetectResult>(
      ApiEndpoints.fallsDetect,
      (dynamic data) => FallDetectResult.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
      body: <String, dynamic>{
        'features': features,
        'detectedAt': DateTime.now().toUtc().toIso8601String(),
        'clientEventId': const Uuid().v4(),
      },
    );
  }

  Future<void> feedback({
    required String id,
    required String feedback,
    int? respondedWithinSec,
  }) {
    return _api!.post<void>(
      ApiEndpoints.fallFeedback(id),
      (_) {},
      body: <String, dynamic>{
        'feedback': feedback,
        if (respondedWithinSec != null) 'respondedWithinSec': respondedWithinSec,
      },
    );
  }

  Future<void> reportMissed() {
    return _api!.post<void>(
      ApiEndpoints.fallsReportMissed,
      (_) {},
      body: <String, dynamic>{},
    );
  }
}

final Provider<FallRepository> fallRepositoryProvider =
    Provider<FallRepository>((Ref ref) {
  return FallRepository(ref.watch(apiClientProvider));
});
