import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/device/device_registrar.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/network/api_endpoints.dart';
import 'package:safestep/core/storage/token_store.dart';

class _InstallTokenStore extends TokenStore {
  _InstallTokenStore(this.installationId) : super(const FlutterSecureStorage());

  final String? installationId;

  @override
  Future<String?> readInstallId() async => installationId;
}

class _DevicesApiClient extends ApiClient {
  _DevicesApiClient({
    required TokenStore tokenStore,
    required this.response,
    this.failList = false,
    this.failDelete = false,
  }) : super(tokenStore: tokenStore, onSessionExpired: () {});

  final Map<String, dynamic> response;
  final bool failList;
  final bool failDelete;
  final List<String> requestedPaths = <String>[];

  @override
  Future<T> get<T>(
    String path,
    T Function(dynamic data) parse, {
    Map<String, dynamic>? query,
  }) async {
    requestedPaths.add(path);
    if (failList) throw StateError('offline');
    return parse(response);
  }

  @override
  Future<T> delete<T>(
    String path,
    T Function(dynamic data) parse, {
    Map<String, dynamic>? query,
  }) async {
    requestedPaths.add(path);
    if (failDelete) throw StateError('delete failed');
    return parse(<String, dynamic>{'ok': true});
  }
}

void main() {
  test('logout removes only the current account device for this installation',
      () async {
    final _InstallTokenStore tokens = _InstallTokenStore('install-1');
    final _DevicesApiClient api = _DevicesApiClient(
      tokenStore: tokens,
      response: <String, dynamic>{
        'devices': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'device-1', 'installId': 'install-1'},
          <String, dynamic>{'id': 'device-2', 'installId': 'another-install'},
        ],
      },
    );

    expect(
        await DeviceRegistrar(api, tokens).unregisterCurrentDevice(), isTrue);
    expect(api.requestedPaths, <String>[
      ApiEndpoints.devices,
      ApiEndpoints.device('device-1'),
    ]);
  });

  test('logout does not delete a device that belongs to another installation',
      () async {
    final _InstallTokenStore tokens = _InstallTokenStore('install-1');
    final _DevicesApiClient api = _DevicesApiClient(
      tokenStore: tokens,
      response: <String, dynamic>{
        'devices': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'device-2', 'installId': 'another-install'},
        ],
      },
    );

    expect(
        await DeviceRegistrar(api, tokens).unregisterCurrentDevice(), isTrue);
    expect(api.requestedPaths, <String>[ApiEndpoints.devices]);
  });

  test('network failure is reported so logout does not claim remote revocation',
      () async {
    final _InstallTokenStore tokens = _InstallTokenStore('install-1');
    final _DevicesApiClient api = _DevicesApiClient(
      tokenStore: tokens,
      response: <String, dynamic>{},
      failList: true,
    );

    expect(
        await DeviceRegistrar(api, tokens).unregisterCurrentDevice(), isFalse);
  });

  test(
      'device deletion failure is reported instead of escaping the logout flow',
      () async {
    final _InstallTokenStore tokens = _InstallTokenStore('install-1');
    final _DevicesApiClient api = _DevicesApiClient(
      tokenStore: tokens,
      response: <String, dynamic>{
        'devices': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'device-1', 'installId': 'install-1'},
        ]
      },
      failDelete: true,
    );
    expect(
        await DeviceRegistrar(api, tokens).unregisterCurrentDevice(), isFalse);
  });
}
