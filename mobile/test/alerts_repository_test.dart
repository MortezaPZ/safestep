import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/network/api_endpoints.dart';
import 'package:safestep/core/storage/token_store.dart';
import 'package:safestep/features/alerts/data/alerts_repository.dart';

class _ReceiptApiClient extends ApiClient {
  _ReceiptApiClient()
      : super(
          tokenStore: TokenStore(const FlutterSecureStorage()),
          onSessionExpired: _ignoreSessionExpiry,
        );

  static void _ignoreSessionExpiry() {}

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
    return parse(<String, dynamic>{
      'receivedAt': '2026-11-06T12:00:00.000Z',
    });
  }
}

void main() {
  test('records an authenticated delivery receipt without marking read',
      () async {
    final _ReceiptApiClient api = _ReceiptApiClient();

    await AlertsRepository(api).recordDeliveryReceipt('alert-1');

    expect(api.requestedPath, ApiEndpoints.alertDeliveryReceipt('alert-1'));
    expect(api.requestedBody, isNull);
  });
}
