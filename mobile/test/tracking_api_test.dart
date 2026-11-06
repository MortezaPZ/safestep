import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/network/api_endpoints.dart';
import 'package:safestep/core/storage/token_store.dart';
import 'package:safestep/core/utils/app_exception.dart';
import 'package:safestep/features/tracking/data/location_repository.dart';

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient(this.response)
      : super(
          tokenStore: TokenStore(const FlutterSecureStorage()),
          onSessionExpired: _ignoreSessionExpiry,
        );

  static void _ignoreSessionExpiry() {}

  final Object? response;
  String? requestedPath;
  Object? requestedBody;

  @override
  Future<T> put<T>(
    String path,
    T Function(dynamic data) parse, {
    Object? body,
  }) async {
    requestedPath = path;
    requestedBody = body;
    return parse(response);
  }
}

void main() {
  test('sends the manual tracking state and requires the server confirmation',
      () async {
    final _TrackingApiClient api = _TrackingApiClient(
      <String, dynamic>{'trackingActive': true},
    );

    final bool active = await LocationRepository(api).setTrackingActive(true);

    expect(active, isTrue);
    expect(api.requestedPath, ApiEndpoints.trackingActive);
    expect(api.requestedBody, <String, dynamic>{'active': true});
  });

  test('does not assume success when the tracking response is malformed',
      () async {
    final _TrackingApiClient api = _TrackingApiClient(<String, dynamic>{});

    await expectLater(
      LocationRepository(api).setTrackingActive(false),
      throwsA(
        isA<AppException>()
            .having((AppException error) => error.code, 'code', 'BAD_PAYLOAD'),
      ),
    );
  });
}
