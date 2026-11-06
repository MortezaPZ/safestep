import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../../tracking/domain/location_sample.dart';
import 'fall_request_limiter.dart';

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
  FallRepository([this._api, FallRequestLimiter? requestLimiter])
      : _requestLimiter = requestLimiter ?? FallRequestLimiter();

  final ApiClient? _api;
  final FallRequestLimiter _requestLimiter;

  Future<FallDetectResult> detect(
    List<double> features, {
    LocationSample? location,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'features': features,
      'detectedAt': DateTime.now().toUtc().toIso8601String(),
      'clientEventId': const Uuid().v4(),
      ..._locationFields(location),
    };

    try {
      return await _postDetection(body);
    } on AppException catch (error) {
      final Duration? retryAfter = error.retryAfter;
      if (error.code != 'TOO_MANY_REQUESTS' ||
          retryAfter == null ||
          retryAfter > _maxRetryAfter) {
        rethrow;
      }

      // فقط یک بار؛ اگر پاسخ دوم هم ۴۲۹ باشد، خطا به فراخواننده می‌رسد.
      return _postDetection(body, minimumDelay: retryAfter);
    }
  }

  static const Duration _maxRetryAfter = Duration(seconds: 60);

  Future<FallDetectResult> _postDetection(
    Map<String, dynamic> body, {
    Duration minimumDelay = Duration.zero,
  }) async {
    await _requestLimiter.reserve(minimumDelay: minimumDelay);
    return _api!.post<FallDetectResult>(
      ApiEndpoints.fallsDetect,
      (dynamic data) => FallDetectResult.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
      body: body,
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
        if (respondedWithinSec != null)
          'respondedWithinSec': respondedWithinSec,
      },
    );
  }

  Future<void> reportMissed({LocationSample? location}) {
    return _api!.post<void>(
      ApiEndpoints.fallsReportMissed,
      (_) {},
      body: <String, dynamic>{..._locationFields(location)},
    );
  }

  static Map<String, dynamic> _locationFields(LocationSample? location) {
    if (location == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'lat': location.lat,
      'lng': location.lng,
      if (location.accuracyM != null) 'accuracyM': location.accuracyM,
      if (location.batteryLevel != null) 'batteryLevel': location.batteryLevel,
    };
  }
}

final Provider<FallRepository> fallRepositoryProvider =
    Provider<FallRepository>((Ref ref) {
  return FallRepository(ref.watch(apiClientProvider));
});
