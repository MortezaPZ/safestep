import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_exception.dart';
import '../../realtime/realtime_controller.dart';
import '../data/watching_repository.dart';
import '../domain/watched_person.dart';

@immutable
class WatchingState {
  const WatchingState({
    this.people = const <WatchedPerson>[],
    this.loading = false,
    this.error,
  });

  final List<WatchedPerson> people;
  final bool loading;
  final AppException? error;

  bool get isEmpty => people.isEmpty;

  WatchedPerson? byId(String userId) {
    for (final WatchedPerson person in people) {
      if (person.userId == userId) return person;
    }
    return null;
  }

  WatchingState copyWith({
    List<WatchedPerson>? people,
    bool? loading,
    AppException? error,
    bool clearError = false,
  }) {
    return WatchingState(
      people: people ?? this.people,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// فهرست افراد تحت پایش، با ادغام موقعیت زنده.
///
/// ── چرا دو منبع داده ادغام می‌شوند ──────────────────────────────────────
/// REST یک «عکس لحظه‌ای» می‌دهد و WebSocket یک «جریان تغییرات». هیچ‌کدام
/// به‌تنهایی کافی نیستند:
///
/// • فقط REST → نقشه تا رفرش بعدی ثابت می‌ماند
/// • فقط WebSocket → تا رسیدن اولین رویداد (تا ۳۰ ثانیه)، صفحه خالی است
///
/// پس REST پایه را می‌سازد و رویدادهای زنده رویش سوار می‌شوند.
class WatchingController extends StateNotifier<WatchingState> {
  WatchingController(this._ref) : super(const WatchingState()) {
    _listenToLive();
  }

  final Ref _ref;

  WatchingRepository get _repository => _ref.read(watchingRepositoryProvider);

  void _listenToLive() {
    _ref.listen<Map<String, LiveLocation>>(
      realtimeControllerProvider.select((RealtimeState s) => s.locations),
      (Map<String, LiveLocation>? previous, Map<String, LiveLocation> next) {
        _mergeLive(next);
      },
    );
  }

  /// اعمال موقعیت‌های زنده روی فهرست موجود.
  ///
  /// نکته: کسی که در فهرست REST نیست، اضافه نمی‌شود. اگر رویدادی برای
  /// کاربری برسد که هنوز در فهرست نداریم، یعنی فهرست قدیمی است و باید
  /// دوباره خوانده شود — نه اینکه یک ردیف ناقص بسازیم.
  void _mergeLive(Map<String, LiveLocation> live) {
    if (state.people.isEmpty || live.isEmpty) return;

    bool changed = false;

    final List<WatchedPerson> merged = state.people.map((WatchedPerson person) {
      final LiveLocation? update = live[person.userId];
      if (update == null) return person;

      // رویدادِ قدیمی‌تر از آنچه داریم، نادیده گرفته می‌شود: ترتیب رسیدن
      // بسته‌ها تضمین‌شده نیست و یک بسته‌ی دیررسیده نباید نشانگر را به عقب
      // برگرداند.
      final DateTime? existing = person.location?.recordedAt;
      if (existing != null && !update.recordedAt.isAfter(existing)) {
        return person;
      }

      changed = true;

      return person.copyWith(
        location: TrackPoint(
          lat: update.lat,
          lng: update.lng,
          recordedAt: update.recordedAt,
          accuracyM: update.accuracyM,
          batteryLevel: update.batteryLevel,
          isSimulated: update.isSimulated,
        ),
        isOnline: true,
      );
    }).toList(growable: false);

    if (changed) state = state.copyWith(people: merged);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final List<WatchedPerson> people = await _repository.watchList();
      state = state.copyWith(people: people, loading: false);

      // موقعیت‌های زنده‌ای که پیش از بارگذاری رسیده بودند، بلافاصله اعمال
      // می‌شوند — وگرنه تا رویداد بعدی، داده‌ی تازه‌تری که در حافظه داریم
      // نادیده می‌ماند
      _mergeLive(_ref.read(realtimeControllerProvider).locations);
    } on AppException catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// تازه‌سازی یک نفر — پس از باز کردن صفحه‌ی نقشه‌ی او.
  Future<void> refreshPerson(String userId) async {
    try {
      final WatchedPerson fresh = await _repository.currentLocation(userId);

      final List<WatchedPerson> updated = state.people.map((WatchedPerson p) {
        if (p.userId != userId) return p;
        return WatchedPerson(
          userId: p.userId,
          person: p.person,
          permissions: p.permissions,
          hidden: fresh.hidden,
          hiddenMessage: fresh.hiddenMessage ?? p.hiddenMessage,
          location: fresh.location ?? p.location,
          zoneStatus: fresh.zoneStatus,
          zoneNames: fresh.zoneNames.isEmpty ? p.zoneNames : fresh.zoneNames,
          outsideZoneName: fresh.outsideZoneName ?? p.outsideZoneName,
          outsideSince: fresh.outsideSince ?? p.outsideSince,
          gpsStale: fresh.gpsStale,
          silentSeconds: fresh.silentSeconds,
          isOnline: p.isOnline,
          guardianshipId: p.guardianshipId,
          isMainSupervisor: p.isMainSupervisor,
        );
      }).toList(growable: false);

      state = state.copyWith(people: updated);
    } on AppException {
      // خطای تازه‌سازی یک نفر نباید کل فهرست را خراب کند
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final StateNotifierProvider<WatchingController, WatchingState> watchingControllerProvider =
    StateNotifierProvider<WatchingController, WatchingState>((ref) {
  return WatchingController(ref);
});

/// یک فرد مشخص از فهرست — صفحه‌ی نقشه از این استفاده می‌کند تا با هر
/// تغییر در بقیه‌ی فهرست بازسازی نشود.
final ProviderFamily<WatchedPerson?, String> watchedPersonProvider =
    Provider.family<WatchedPerson?, String>((ref, String userId) {
  return ref.watch(watchingControllerProvider).byId(userId);
});
