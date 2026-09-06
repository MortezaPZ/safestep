import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../data/location_queue.dart';
import '../data/location_repository.dart';
import '../data/permission_service.dart';
import '../domain/location_sample.dart';

/// وضعیت ردیابی که روی صفحه نمایش داده می‌شود.
@immutable
class TrackingState {
  const TrackingState({
    this.status = TrackingStatus.off,
    this.permission = LocationPermissionState.denied,
    this.lastSample,
    this.lastSentAt,
    this.queuedCount = 0,
    this.online = true,
    this.batteryLevel,
    this.error,
    this.powerSave = false,
  });

  final TrackingStatus status;
  final LocationPermissionState permission;

  /// آخرین موقعیتی که از حسگر خوانده شده — چه ارسال شده باشد چه نه
  final LocationSample? lastSample;

  /// آخرین باری که ارسال به سرور موفق بود
  final DateTime? lastSentAt;

  /// چند نمونه در صف محلی منتظر ارسال است
  final int queuedCount;

  final bool online;
  final int? batteryLevel;
  final AppException? error;
  final bool powerSave;

  bool get isActive =>
      status == TrackingStatus.live || status == TrackingStatus.offline;

  TrackingState copyWith({
    TrackingStatus? status,
    LocationPermissionState? permission,
    LocationSample? lastSample,
    DateTime? lastSentAt,
    int? queuedCount,
    bool? online,
    int? batteryLevel,
    AppException? error,
    bool? powerSave,
    bool clearError = false,
  }) {
    return TrackingState(
      status: status ?? this.status,
      permission: permission ?? this.permission,
      lastSample: lastSample ?? this.lastSample,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      queuedCount: queuedCount ?? this.queuedCount,
      online: online ?? this.online,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      error: clearError ? null : (error ?? this.error),
      powerSave: powerSave ?? this.powerSave,
    );
  }
}

/// موتور موقعیت‌یابی اپ.
///
/// ── جریان یک نمونه ──────────────────────────────────────────────────────
///
///   حسگر GPS
///     └→ فیلتر دقت (نمونه‌ی خیلی بی‌دقت دور ریخته می‌شود)
///     └→ افزودن سطح باتری
///     └→ تلاش برای ارسال زنده
///          ├─ موفق  → وضعیت «زنده»
///          └─ ناموفق → ذخیره در صف SQLite، وضعیت «آفلاین»
///     └→ با برگشت اینترنت: تخلیه‌ی دسته‌ای صف
///
/// ── چرا صف، در یک اپ ایمنی، اختیاری نیست ────────────────────────────────
/// کاربری که در پارکینگ یا آسانسور است، دقیقاً همان جایی است که ممکن است
/// کمک لازم داشته باشد. بدون صف، آن چند دقیقه از تاریخچه برای همیشه گم
/// می‌شود و مراقب یک شکاف بی‌توضیح می‌بیند.
class TrackingController extends StateNotifier<TrackingState> {
  TrackingController(this._ref) : super(const TrackingState());

  final Ref _ref;

  static const Uuid _uuid = Uuid();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _flushTimer;

  final Battery _battery = Battery();

  /// جلوگیری از اجرای هم‌زمان دو تخلیه‌ی صف
  bool _flushing = false;

  LocationRepository get _repository => _ref.read(locationRepositoryProvider);
  LocationQueue get _queue => _ref.read(locationQueueProvider);
  LocationPermissionService get _permissions =>
      _ref.read(locationPermissionServiceProvider);

  /// فاصله‌ی ارسال، از پیکربندی سرور می‌آید تا تغییرش نیاز به انتشار
  /// نسخه‌ی جدید اپ نداشته باشد.
  int get _intervalSec {
    final UserSettings? s = _ref.read(authControllerProvider).settings;
    if (state.powerSave && (s?.adaptivePingEnabled ?? true)) {
      return s?.pingIntervalStationarySec ?? 120;
    }
    return s?.pingIntervalSec ?? AppConfig.defaultPingIntervalSec;
  }

  DateTime? _stillSince;
  double? _lastLat;
  double? _lastLng;

  /* ═══════════════════════ چرخه‌ی عمر ═══════════════════════ */

  /// بررسی وضعیت مجوز، بدون درخواست چیزی.
  Future<void> refreshPermission() async {
    final LocationPermissionState permission = await _permissions.check();
    state = state.copyWith(permission: permission);
  }

  /// شروع ردیابی.
  ///
  /// اگر مجوز نباشد، **خودش درخواست نمی‌کند**: لایه‌ی رابط کاربری باید اول
  /// توضیح دهد چرا. این تابع فقط وضعیت را برمی‌گرداند تا صفحه تصمیم بگیرد.
  Future<bool> start() async {
    state = state.copyWith(status: TrackingStatus.starting, clearError: true);

    final LocationPermissionState permission = await _permissions.check();
    state = state.copyWith(permission: permission);

    if (permission == LocationPermissionState.serviceDisabled) {
      state = state.copyWith(
        status: TrackingStatus.blocked,
        error: AppException.locationDisabled,
      );
      return false;
    }

    if (permission == LocationPermissionState.denied ||
        permission == LocationPermissionState.permanentlyDenied) {
      state = state.copyWith(
        status: TrackingStatus.blocked,
        error: AppException.locationPermission,
      );
      return false;
    }

    await _startForegroundService();
    await _listenConnectivity();
    await _startPositionStream();

    _flushTimer?.cancel();
    // تخلیه‌ی دوره‌ای صف، مستقل از رویداد اتصال: بعضی گوشی‌ها تغییر شبکه را
    // دیر یا اصلاً گزارش نمی‌کنند و بدون این تایمر، صف می‌ماند
    _flushTimer = Timer.periodic(
      Duration(seconds: _intervalSec * 2),
      (_) => unawaited(_flushQueue()),
    );

    state = state.copyWith(status: TrackingStatus.live);
    await _updateQueueCount();
    return true;
  }

  /// توقف ردیابی.
  ///
  /// صف پاک **نمی‌شود**: نمونه‌های ارسال‌نشده متعلق به تاریخچه‌ی کاربرند و
  /// با روشن شدن دوباره فرستاده می‌شوند.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;

    await _connectivitySub?.cancel();
    _connectivitySub = null;

    _flushTimer?.cancel();
    _flushTimer = null;

    await _stopForegroundService();

    state = state.copyWith(status: TrackingStatus.off);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _connectivitySub?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }

  /* ═══════════════════════ سرویس Foreground ═══════════════════════ */

  /// راه‌اندازی سرویس پیش‌زمینه (فقط اندروید).
  ///
  /// ── این سرویس چه کار می‌کند و چه کار نمی‌کند ──────────────────────────
  /// **می‌کند:** یک اعلان دائمی نشان می‌دهد و پردازه‌ی اپ را زنده نگه
  /// می‌دارد تا اندروید آن را در پس‌زمینه نکشد. با زنده ماندن پردازه،
  /// همین جریان موقعیت که در ایزوله‌ی اصلی اجرا می‌شود به کارش ادامه
  /// می‌دهد.
  ///
  /// **نمی‌کند:** منطق را به ایزوله‌ی جداگانه نمی‌برد. آن الگو (اجرای
  /// کامل ردیابی در ایزوله‌ی سرویس) نیازمند تکرار کل لایه‌ی توکن، صف و
  /// شبکه در ایزوله‌ی دوم است، چون ایزوله‌ها حافظه‌ی مشترک ندارند. برای
  /// این فاز، پیچیدگی‌اش توجیه ندارد؛ اگر بعداً کشته شدن پردازه در
  /// گوشی‌های خاص (شیائومی، هواوی) مشکل‌ساز شد، همین‌جا نقطه‌ی ارتقاست.
  ///
  /// **اعلان دائمی، ویژگی است نه دردسر:** کاربر باید همیشه ببیند که
  /// موقعیتش در حال ارسال است. ردیابی نامرئی، دقیقاً همان چیزی است که این
  /// محصول نباید باشد.
  Future<void> _startForegroundService() async {
    if (!defaultTargetPlatform.isAndroidLike) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'safestep_tracking',
          channelName: 'اشتراک موقعیت',
          channelDescription: 'وقتی موقعیت شما در حال ارسال است نمایش داده می‌شود',
          // اهمیت پایین: اعلان دیده می‌شود ولی صدا و لرزش ندارد.
          // این اعلان قرار است دائمی باشد؛ اگر هر بار تذکر بدهد، کاربر
          // خاموشش می‌کند و ردیابی پس‌زمینه از کار می‌افتد.
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          interval: _intervalSec * 1000,
          isOnceEvent: false,
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );

      if (await FlutterForegroundTask.isRunningService) return;

      await FlutterForegroundTask.startService(
        notificationTitle: 'هم‌قدم فعال است',
        notificationText: 'موقعیت شما با مراقبانتان به اشتراک گذاشته می‌شود',
      );
    } catch (error) {
      // نبود سرویس پیش‌زمینه، ردیابی هنگام باز بودن اپ را از کار
      // نمی‌اندازد؛ فقط پس‌زمینه را نامطمئن می‌کند
      debugPrint('سرویس پیش‌زمینه راه‌اندازی نشد: $error');
    }
  }

  Future<void> _stopForegroundService() async {
    if (!defaultTargetPlatform.isAndroidLike) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // بی‌اهمیت
    }
  }

  /* ═══════════════════════ جریان موقعیت ═══════════════════════ */

  Future<void> _startPositionStream() async {
    await _positionSub?.cancel();

    final LocationSettings settings = _buildLocationSettings();

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object error) {
        state = state.copyWith(
          status: TrackingStatus.blocked,
          error: AppException(
            message: 'دریافت موقعیت با مشکل مواجه شد. مکان‌یاب گوشی را بررسی کنید.',
            code: 'POSITION_STREAM',
            kind: AppErrorKind.permission,
          ),
        );
      },
    );
  }

  /// تنظیمات جریان موقعیت.
  ///
  /// `distanceFilter` روی ۱۰ متر است: در حالت سکون، نمونه‌ی تازه تولید
  /// نمی‌شود و باتری مصرف نمی‌کند. تشخیصِ «توقف طولانی» به نمونه‌ی مکرر
  /// نیاز ندارد — سرور از فاصله‌ی زمانی بین نمونه‌ها همان را می‌فهمد.
  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform.isAndroidLike) {
      return AndroidSettings(
        accuracy: state.powerSave ? LocationAccuracy.medium : LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: Duration(seconds: _intervalSec),
        // اعلان جداگانه‌ی geolocator خاموش است تا با اعلان سرویس
        // پیش‌زمینه دوتا نشود و کاربر دو نوتیفیکیشن هم‌زمان نبیند
        foregroundNotificationConfig: null,
      );
    }

    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      // بدون این، iOS در پس‌زمینه جریان را قطع می‌کند
      allowBackgroundLocationUpdates: true,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }

  /// دقتِ بدتر از این، عملاً بی‌فایده است.
  ///
  /// نمونه‌ای با دقت ۲۰۰ متر یعنی «جایی در این محله» — روی نقشه نشانگر را
  /// می‌پراند و موتور Geofence سرور را به اشتباه می‌اندازد. بهتر است
  /// چیزی نفرستیم تا اینکه داده‌ی گمراه‌کننده بفرستیم.
  static const double _maxAcceptableAccuracyM = 150;

  Future<void> _onPosition(Position position) async {
    if (position.accuracy > _maxAcceptableAccuracyM) return;

    final int? battery = await _readBattery();

    final LocationSample sample = LocationSample(
      clientUuid: _uuid.v4(),
      lat: position.latitude,
      lng: position.longitude,
      recordedAt: position.timestamp,
      accuracyM: position.accuracy,
      speedMps: position.speed >= 0 ? position.speed : null,
      headingDeg: position.heading >= 0 ? position.heading : null,
      batteryLevel: battery,
      provider: defaultTargetPlatform.isAndroidLike ? 'fused' : 'gps',
    );

    final UserSettings? settings = _ref.read(authControllerProvider).settings;
    bool powerSave = state.powerSave;
    if (settings?.adaptivePingEnabled ?? true) {
      final double speed = position.speed >= 0 ? position.speed : 0;
      double moved = 0;
      if (_lastLat != null && _lastLng != null) {
        moved = Geolocator.distanceBetween(
          _lastLat!,
          _lastLng!,
          position.latitude,
          position.longitude,
        );
      }
      _lastLat = position.latitude;
      _lastLng = position.longitude;
      final bool still = speed < 0.5 && moved < 30;
      if (still) {
        _stillSince ??= DateTime.now();
      } else {
        _stillSince = null;
      }
      final bool shouldSave = still &&
          _stillSince != null &&
          DateTime.now().difference(_stillSince!).inSeconds >= 300;
      if (shouldSave != powerSave) {
        powerSave = shouldSave;
        unawaited(_startPositionStream());
      }
    }

    state = state.copyWith(
      lastSample: sample,
      batteryLevel: battery,
      powerSave: powerSave,
    );

    await _deliver(sample);
  }

  /// تلاش برای ارسال؛ در صورت شکست، صف.
  Future<void> _deliver(LocationSample sample) async {
    try {
      await _repository.sendPing(sample);

      state = state.copyWith(
        status: TrackingStatus.live,
        lastSentAt: DateTime.now(),
        online: true,
        clearError: true,
      );

      // اتصال برقرار است؛ فرصت خوبی برای تخلیه‌ی صف
      unawaited(_flushQueue());
    } on AppException catch (error) {
      // خطای احراز هویت را صف نمی‌کنیم: نشست تمام شده و تلاش دوباره
      // فایده‌ای ندارد؛ کنترلر احراز هویت خودش کاربر را بیرون می‌برد.
      if (error.kind == AppErrorKind.auth) {
        await stop();
        return;
      }

      await _queue.add(sample);
      await _updateQueueCount();

      state = state.copyWith(status: TrackingStatus.offline, online: false);
    }
  }

  /* ═══════════════════════ صف و اتصال ═══════════════════════ */

  Future<void> _listenConnectivity() async {
    await _connectivitySub?.cancel();

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool online = results.any(
          (ConnectivityResult r) => r != ConnectivityResult.none,
        );

        state = state.copyWith(online: online);

        // با برگشت اینترنت، بلافاصله صف تخلیه می‌شود
        if (online) unawaited(_flushQueue());
      },
    );
  }

  /// تخلیه‌ی صف به‌صورت دسته‌ای.
  ///
  /// ── چرا حلقه دارد ───────────────────────────────────────────────────
  /// اگر کاربر یک ساعت آفلاین بوده، صف ممکن است صدها نمونه داشته باشد.
  /// سقف هر درخواست ۲۰۰ تاست، پس تا خالی شدن صف ادامه می‌دهیم — اما با
  /// سقف تکرار، تا یک خطای پایدار حلقه‌ی بی‌پایان نسازد.
  Future<void> _flushQueue() async {
    if (_flushing) return;
    _flushing = true;

    try {
      for (int round = 0; round < 20; round++) {
        final List<LocationSample> batch =
            await _queue.take(AppConfig.maxBatchSize);

        if (batch.isEmpty) break;

        try {
          await _repository.sendBatch(batch);
          await _queue.remove(
            batch.map((LocationSample s) => s.clientUuid).toList(),
          );
        } on AppException catch (error) {
          if (error.kind == AppErrorKind.validation) {
            // داده‌ی خراب در صف: اگر حذفش نکنیم، برای همیشه صف را می‌بندد
            await _queue.remove(
              batch.map((LocationSample s) => s.clientUuid).toList(),
            );
            continue;
          }
          // شبکه هنوز مشکل دارد؛ دفعه‌ی بعد
          break;
        }
      }

      await _updateQueueCount();

      if (state.queuedCount == 0 && state.status == TrackingStatus.offline) {
        state = state.copyWith(status: TrackingStatus.live, online: true);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _updateQueueCount() async {
    final int count = await _queue.count();
    state = state.copyWith(queuedCount: count);
  }

  Future<int?> _readBattery() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  /// گرفتن موقعیت لحظه‌ای — برای SOS.
  ///
  /// جریان معمول ممکن است چند ثانیه پیش نمونه داده باشد؛ در وضعیت اضطراری
  /// موقعیتِ همین لحظه مهم است. مهلت کوتاه است چون منتظر ماندن برای قفل
  /// دقیق GPS در وضعیت اضطراری، بدترین کار ممکن است — موقعیت تقریبی الان
  /// از موقعیت دقیقِ سی ثانیه بعد بهتر است.
  Future<Position?> currentPositionForEmergency() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
    } catch (_) {
      // آخرین موقعیت شناخته‌شده، بهتر از هیچ است
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// پاک کردن صف — هنگام خروج از حساب.
  Future<void> clearQueue() async {
    await _queue.clear();
    await _updateQueueCount();
  }
}

/// کمکی کوچک برای خوانایی شرط‌های مربوط به اندروید.
extension on TargetPlatform {
  bool get isAndroidLike => this == TargetPlatform.android;
}

final StateNotifierProvider<TrackingController, TrackingState> trackingControllerProvider =
    StateNotifierProvider<TrackingController, TrackingState>((ref) {
  return TrackingController(ref);
});
