/// Keeps FCM token registration bound to the currently authenticated account.
///
/// Server registration is authenticated with the current bearer token. Requests
/// are serialized so an in-flight registration for a previous account cannot
/// finish after, and overwrite, the latest account's registration.
class FcmTokenRegistration {
  FcmTokenRegistration({
    required Future<String?> Function() readToken,
    required Future<bool> Function(String token) registerCurrentDevice,
  })  : _readToken = readToken,
        _registerCurrentDevice = registerCurrentDevice;

  final Future<String?> Function() _readToken;
  final Future<bool> Function(String token) _registerCurrentDevice;

  String? _activeAccountId;
  String? _registeredKey;
  int _accountRevision = 0;
  Future<void> _registrationQueue = Future<void>.value();

  String? get activeAccountId => _activeAccountId;

  Future<void> setCurrentAccount(String? accountId) {
    if (_activeAccountId != accountId) {
      _activeAccountId = accountId;
      _accountRevision++;
      _registeredKey = null;
    }
    if (accountId == null) return _registrationQueue;
    return syncCurrentToken();
  }

  /// Re-registers the latest token after login or Firebase initialization.
  Future<void> syncCurrentToken() {
    final String? accountId = _activeAccountId;
    if (accountId == null) return Future<void>.value();
    final int revision = _accountRevision;
    return _enqueue(accountId, revision, _readToken);
  }

  /// Updates the active account's device row when Firebase rotates its token.
  Future<void> tokenRefreshed(String token) {
    final String? accountId = _activeAccountId;
    if (accountId == null || token.trim().isEmpty) {
      return Future<void>.value();
    }
    final int revision = _accountRevision;
    return _enqueue(accountId, revision, () async => token);
  }

  Future<void> _enqueue(
    String accountId,
    int revision,
    Future<String?> Function() tokenSource,
  ) {
    final Future<void> operation = _registrationQueue.then((_) async {
      if (_activeAccountId != accountId || _accountRevision != revision) return;

      final String? token = await tokenSource();
      if (token == null || token.trim().isEmpty) return;
      if (_activeAccountId != accountId || _accountRevision != revision) return;

      final String key = '$accountId\u001f$token';
      if (_registeredKey == key) return;

      // The API uses the current bearer token as account identity. If that
      // request fails, leave the key unset so a later refresh can retry.
      final bool registered = await _registerCurrentDevice(token);
      if (registered &&
          _activeAccountId == accountId &&
          _accountRevision == revision) {
        _registeredKey = key;
      }
    });

    // Keep the queue usable after a failed network operation while preserving
    // the failure for the caller that requested this particular operation.
    _registrationQueue = operation.catchError((Object _) {});
    return operation;
  }
}
