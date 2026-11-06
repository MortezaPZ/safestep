import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/network/error_mapper.dart';
import 'package:safestep/core/storage/token_store.dart';
import 'package:safestep/core/utils/app_exception.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/fall/data/fall_request_limiter.dart';
import 'package:safestep/features/tracking/domain/location_sample.dart';

class _ScriptedApiClient extends ApiClient {
  _ScriptedApiClient(this._responses, {this.now})
      : super(
          tokenStore: TokenStore(const FlutterSecureStorage()),
          onSessionExpired: _ignoreSessionExpiry,
        );

  static void _ignoreSessionExpiry() {}

  final List<Object?> _responses;
  final DateTime Function()? now;
  final List<String> paths = <String>[];
  final List<Object?> bodies = <Object?>[];
  final List<DateTime> requestTimes = <DateTime>[];

  @override
  Future<T> post<T>(
    String path,
    T Function(dynamic data) parse, {
    Object? body,
    Duration? timeout,
  }) async {
    paths.add(path);
    bodies.add(body);
    final DateTime Function()? clock = now;
    if (clock != null) requestTimes.add(clock());
    final Object? response = _responses.removeAt(0);
    if (response is Exception) throw response;
    return parse(response);
  }
}

class _FakeClock {
  DateTime current = DateTime.utc(2026);
  final List<Duration> delays = <Duration>[];

  Future<void> wait(Duration delay) async {
    delays.add(delay);
    current = current.add(delay);
  }
}

void main() {
  final LocationSample location = LocationSample(
    clientUuid: 'sample-1',
    lat: 35.7,
    lng: 51.4,
    recordedAt: DateTime.utc(2026),
    accuracyM: 8,
    batteryLevel: 74,
  );

  test('includes the latest location in fall detection and missed-fall reports',
      () async {
    final _ScriptedApiClient api = _ScriptedApiClient(<Object?>[
      <String, dynamic>{'isFall': false, 'fallEventId': '', 'countdownSec': 30},
      <String, dynamic>{},
    ]);
    final FallRepository repository = FallRepository(api);

    await repository.detect(List<double>.filled(14, 1), location: location);
    await repository.reportMissed(location: location);

    final Map<String, dynamic> detectBody =
        api.bodies[0]! as Map<String, dynamic>;
    final Map<String, dynamic> missedBody =
        api.bodies[1]! as Map<String, dynamic>;
    for (final Map<String, dynamic> body in <Map<String, dynamic>>[
      detectBody,
      missedBody,
    ]) {
      expect(body['lat'], 35.7);
      expect(body['lng'], 51.4);
      expect(body['accuracyM'], 8);
      expect(body['batteryLevel'], 74);
    }
    expect(detectBody['features'], hasLength(14));
  });

  test('retries one 429 only after the advertised delay', () async {
    final _FakeClock clock = _FakeClock();
    final _ScriptedApiClient api = _ScriptedApiClient(<Object?>[
      const AppException(
        message: 'slow down',
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration.zero,
      ),
      <String, dynamic>{
        'isFall': true,
        'fallEventId': 'event-1',
        'countdownSec': 30
      },
    ], now: () => clock.current);

    final FallDetectResult result = await FallRepository(
      api,
      FallRequestLimiter(
        minimumInterval: Duration.zero,
        now: () => clock.current,
        wait: clock.wait,
      ),
    ).detect(
      List<double>.filled(14, 1),
      location: location,
    );

    expect(result.fallEventId, 'event-1');
    expect(api.paths, hasLength(2));
    expect(api.bodies[0], api.bodies[1]);
    expect((api.bodies.first as Map<String, dynamic>)['clientEventId'],
        isA<String>());
  });

  test('does not retry a 429 with no Retry-After or after the one retry',
      () async {
    final _ScriptedApiClient missingHeaderApi = _ScriptedApiClient(<Object?>[
      const AppException(message: 'slow down', code: 'TOO_MANY_REQUESTS'),
    ]);
    await expectLater(
      FallRepository(missingHeaderApi).detect(List<double>.filled(14, 1)),
      throwsA(isA<AppException>()),
    );
    expect(missingHeaderApi.paths, hasLength(1));

    final _FakeClock clock = _FakeClock();
    final _ScriptedApiClient repeated429Api = _ScriptedApiClient(<Object?>[
      const AppException(
        message: 'slow down',
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration.zero,
      ),
      const AppException(
        message: 'still slow down',
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration.zero,
      ),
    ], now: () => clock.current);
    await expectLater(
      FallRepository(
        repeated429Api,
        FallRequestLimiter(
          minimumInterval: Duration.zero,
          now: () => clock.current,
          wait: clock.wait,
        ),
      ).detect(List<double>.filled(14, 1)),
      throwsA(isA<AppException>()),
    );
    expect(repeated429Api.paths, hasLength(2));
  });

  test('nine detections and their retries share the HTTP request quota',
      () async {
    final _FakeClock clock = _FakeClock();
    final List<Object?> responses = <Object?>[];
    for (int i = 0; i < 9; i += 1) {
      responses
        ..add(const AppException(
          message: 'slow down',
          code: 'TOO_MANY_REQUESTS',
          retryAfter: Duration(seconds: 1),
        ))
        ..add(<String, dynamic>{
          'isFall': false,
          'fallEventId': 'event-$i',
          'countdownSec': 30,
        });
    }
    final _ScriptedApiClient api = _ScriptedApiClient(
      responses,
      now: () => clock.current,
    );
    final FallRepository repository = FallRepository(
      api,
      FallRequestLimiter(
        minimumInterval: Duration.zero,
        now: () => clock.current,
        wait: clock.wait,
      ),
    );

    for (int i = 0; i < 9; i += 1) {
      await repository.detect(List<double>.filled(14, i.toDouble()));
    }

    expect(api.paths, hasLength(18));
    expect(api.requestTimes, hasLength(18));
    for (int detection = 0; detection < 9; detection += 1) {
      final Map<String, dynamic> original =
          api.bodies[detection * 2]! as Map<String, dynamic>;
      final Map<String, dynamic> retry =
          api.bodies[detection * 2 + 1]! as Map<String, dynamic>;
      expect(retry['clientEventId'], original['clientEventId']);
      expect(retry['features'], original['features']);
      expect(
        api.requestTimes[detection * 2 + 1]
            .difference(api.requestTimes[detection * 2]),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
    }

    for (final DateTime requestAt in api.requestTimes) {
      final int requestsInWindow = api.requestTimes.where((DateTime other) {
        return other.isAfter(requestAt.subtract(const Duration(seconds: 60))) &&
            !other.isAfter(requestAt);
      }).length;
      expect(requestsInWindow, lessThanOrEqualTo(9));
    }
    expect(
      clock.delays
          .any((Duration delay) => delay >= const Duration(seconds: 50)),
      isTrue,
      reason: 'the retry must wait if the nine-request rolling window is full',
    );
  });

  test('Retry-After longer than the local interval is preserved', () async {
    final _FakeClock clock = _FakeClock();
    final _ScriptedApiClient api = _ScriptedApiClient(<Object?>[
      const AppException(
        message: 'slow down',
        code: 'TOO_MANY_REQUESTS',
        retryAfter: Duration(seconds: 12),
      ),
      <String, dynamic>{
        'isFall': false,
        'fallEventId': 'event-1',
        'countdownSec': 30,
      },
    ], now: () => clock.current);
    final FallRepository repository = FallRepository(
      api,
      FallRequestLimiter(
        now: () => clock.current,
        wait: clock.wait,
      ),
    );

    await repository.detect(List<double>.filled(14, 1));

    expect(
      api.requestTimes[1].difference(api.requestTimes[0]),
      const Duration(seconds: 12),
    );
    expect(clock.delays, contains(const Duration(seconds: 12)));
  });

  test('keeps the Retry-After header on mapped 429 errors', () {
    final RequestOptions request = RequestOptions(path: '/falls/detect');
    final Response<dynamic> response = Response<dynamic>(
      requestOptions: request,
      statusCode: 429,
      headers: Headers.fromMap(<String, List<String>>{
        'retry-after': <String>['5'],
      }),
      data: <String, dynamic>{
        'error': <String, dynamic>{'code': 'TOO_MANY_REQUESTS'},
      },
    );

    final AppException mapped = ErrorMapper.map(
      DioException.badResponse(
        statusCode: 429,
        requestOptions: request,
        response: response,
      ),
    );

    expect(mapped.code, 'TOO_MANY_REQUESTS');
    expect(mapped.retryAfter, const Duration(seconds: 5));
  });
}
