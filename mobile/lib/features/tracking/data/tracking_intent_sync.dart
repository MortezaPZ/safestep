import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TrackingIntentStore {
  Future<bool?> readPending(String userId);
  Future<void> writePending(String userId, bool active);
  Future<void> clearPending(String userId);
}

class SharedPreferencesTrackingIntentStore implements TrackingIntentStore {
  static const String _prefix = 'tracking.serverIntent.';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  String _key(String userId) => '$_prefix$userId';

  @override
  Future<bool?> readPending(String userId) async {
    final String? value = (await _preferences).getString(_key(userId));
    if (value == '1') return true;
    if (value == '0') return false;
    return null;
  }

  @override
  Future<void> writePending(String userId, bool active) async {
    await (await _preferences).setString(_key(userId), active ? '1' : '0');
  }

  @override
  Future<void> clearPending(String userId) async {
    await (await _preferences).remove(_key(userId));
  }
}

/// ترتیب‌دادن intentها تا پاسخ دیررسِ start نتواند stop جدیدتر را بازنویسی کند.
class TrackingIntentSynchronizer {
  TrackingIntentSynchronizer({
    required TrackingIntentStore store,
    required Future<void> Function(bool active) send,
    required String? Function() currentUserId,
    void Function(String? message)? onStatus,
  })  : _store = store,
        _send = send,
        _currentUserId = currentUserId,
        _onStatus = onStatus;

  final TrackingIntentStore _store;
  final Future<void> Function(bool active) _send;
  final String? Function() _currentUserId;
  final void Function(String? message)? _onStatus;

  Future<void> _queue = Future<void>.value();
  int _revision = 0;
  String? _userId;
  bool? _pending;

  Future<void> setDesiredState({required String userId, required bool active}) {
    _revision += 1;
    _userId = userId;
    _pending = active;
    _onStatus?.call(null);
    return _enqueue();
  }

  Future<void> retryPending(String userId) async {
    if (_userId != userId || _pending == null) {
      final int revision = ++_revision;
      _userId = userId;
      _pending = null;
      final bool? saved = await _store.readPending(userId);
      if (revision != _revision || _userId != userId) return;
      _pending = saved;
    }

    if (_pending == null) {
      _onStatus?.call(null);
      return;
    }
    await _enqueue();
  }

  Future<void> _enqueue() {
    final Future<void> next =
        _queue.catchError((Object _) {}).then((_) => _drain());
    _queue = next;
    return next;
  }

  Future<void> _drain() async {
    while (_pending != null && _userId != null) {
      final int revision = _revision;
      final String userId = _userId!;
      final bool active = _pending!;

      try {
        await _store.writePending(userId, active);
        if (revision != _revision) continue;

        // ذخیره‌سازی پیش از بررسی نشست، تا قصد آخرین کاربر هم هنگام خروج
        // یا تعویض حساب باقی بماند و پس از ورود همان کاربر دوباره فرستاده شود.
        if (_currentUserId() != userId) return;
        await _send(active);
        if (revision != _revision) continue;

        await _store.clearPending(userId);
        if (revision != _revision) {
          final String? latestUserId = _userId;
          final bool? latestActive = _pending;
          if (latestUserId != null && latestActive != null) {
            await _store.writePending(latestUserId, latestActive);
          }
          continue;
        }

        _pending = null;
        _onStatus?.call(null);
      } catch (_) {
        if (revision != _revision) continue;
        _onStatus?.call(active
            ? 'شروع ردیابی به سرور اعلام نشد؛ با وصل شدن اینترنت دوباره می‌فرستیم.'
            : 'توقف ردیابی به سرور اعلام نشد؛ با وصل شدن اینترنت دوباره می‌فرستیم.');
        return;
      }
    }
  }
}
