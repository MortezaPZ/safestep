/// سهمیه‌بندی درخواست‌های HTTP تشخیص سقوط در کلاینت.
///
/// محدودکننده‌ی API در هر ۶۰ ثانیه ۱۰ درخواست می‌پذیرد. حداکثر ۹ ارسال
/// واقعی در هر پنجره ثبت می‌شود؛ retry پاسخ ۴۲۹ نیز یک ارسال جداست و همان
/// سهمیه را مصرف می‌کند.
class FallRequestLimiter {
  FallRequestLimiter({
    this.minimumInterval = const Duration(seconds: 7),
    this.window = const Duration(seconds: 60),
    this.maximumRequests = 9,
    DateTime Function()? now,
    Future<void> Function(Duration delay)? wait,
  })  : _now = now ?? DateTime.now,
        _wait = wait ?? Future<void>.delayed;

  final Duration minimumInterval;
  final Duration window;
  final int maximumRequests;
  final DateTime Function() _now;
  final Future<void> Function(Duration delay) _wait;
  final List<DateTime> _sentAt = <DateTime>[];

  bool canSend(DateTime now) {
    _prune(now);
    if (_sentAt.length >= maximumRequests) return false;
    if (_sentAt.isNotEmpty && now.difference(_sentAt.last) < minimumInterval) {
      return false;
    }

    _sentAt.add(now);
    return true;
  }

  /// Wait for and consume one permit for an actual HTTP request.
  ///
  /// [minimumDelay] carries the server's Retry-After value. If the local
  /// window is fuller than that delay, the permit is granted only once both
  /// constraints have cleared.
  Future<void> reserve({Duration minimumDelay = Duration.zero}) async {
    final DateTime earliest = _now().add(minimumDelay);
    while (true) {
      final DateTime now = _now();
      _prune(now);

      DateTime allowedAt = earliest;
      if (_sentAt.isNotEmpty) {
        final DateTime intervalAllowedAt = _sentAt.last.add(minimumInterval);
        if (intervalAllowedAt.isAfter(allowedAt)) {
          allowedAt = intervalAllowedAt;
        }
      }
      if (_sentAt.length >= maximumRequests) {
        final DateTime windowAllowedAt = _sentAt.first.add(window);
        if (windowAllowedAt.isAfter(allowedAt)) {
          allowedAt = windowAllowedAt;
        }
      }

      if (!now.isBefore(allowedAt)) {
        _sentAt.add(now);
        return;
      }
      await _wait(allowedAt.difference(now));
    }
  }

  void _prune(DateTime now) {
    final DateTime cutoff = now.subtract(window);
    _sentAt.removeWhere((DateTime timestamp) => !timestamp.isAfter(cutoff));
  }
}
