import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/network/api_endpoints.dart';
import 'package:safestep/core/storage/token_store.dart';
import 'package:safestep/features/evaluation/data/evaluation_repository.dart';

class _EvaluationApiClient extends ApiClient {
  _EvaluationApiClient(this.response)
      : super(
          tokenStore: TokenStore(const FlutterSecureStorage()),
          onSessionExpired: _ignoreSessionExpiry,
        );

  static void _ignoreSessionExpiry() {}

  final Object? response;
  String? requestedPath;
  Object? requestedBody;

  @override
  Future<T> post<T>(
    String path,
    T Function(dynamic data) parse, {
    Object? body,
    Duration? timeout,
  }) async {
    requestedPath = path;
    requestedBody = body;
    return parse(response);
  }
}

void main() {
  test('sends environment and retains a recorded sample marked invalid',
      () async {
    final _EvaluationApiClient api = _EvaluationApiClient(
      <String, dynamic>{
        'errorM': 12.5,
        'accuracyM': 45,
        'valid': false,
        'environment': 'urban',
      },
    );

    final ReferenceSample sample =
        await EvaluationRepository(api).recordReferenceSample(
      lat: 35.7,
      lng: 51.4,
      accuracyM: 45,
      environment: 'urban',
    );

    expect(api.requestedPath, ApiEndpoints.evaluationReferenceSample);
    expect(api.requestedBody, <String, dynamic>{
      'lat': 35.7,
      'lng': 51.4,
      'accuracyM': 45,
      'environment': 'urban',
    });
    expect(sample.valid, isFalse);
    expect(sample.errorM, 12.5);
    expect(sample.accuracyM, 45);
  });
}
