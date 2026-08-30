import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/socket_client.dart';
import '../../core/storage/token_store.dart';
import '../auth/presentation/auth_controller.dart';

/// موقعیت زنده‌ی یک فرد تحت پایش، همان‌طور که از WebSocket می‌رسد.
@immutable
class LiveLocation {
  const LiveLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracyM,
    this.batteryLevel,
    this.isSimulated = false,
    this.sharingEnabled = true,
  });

  final String userId;
  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? accuracyM;
  final int? batteryLevel;
  final bool isSimulated;
  final bool sharingEnabled;

  static LiveLocation? tryFrom(Map<String, dynamic> json) {
    final Object? userId = json['userId'];
    final Object? lat = json['lat'];
    final Object? lng = json['lng'];

    if (userId is! String || lat is! num || lng is! num) return null;

    final Object? recordedAt = json['recordedAt'];

    return LiveLocation(
      userId: userId,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      recordedAt: recordedAt is String
          ? (DateTime.tryParse(recordedAt)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      accuracyM: json['accuracyM'] is num
          ? (json['accuracyM'] as num).toDouble()
          : null,
      batteryLevel: json['batteryLevel'] is num
          ? (json['batteryLevel'] as num).toInt()
          : null,
      isSimulated: json['isSimulated'] == true,
      sharingEnabled: json['sharingEnabled'] != false,
    );
  }
}

/// هشدار زنده.
@immutable
class LiveAlert {
  const LiveAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    required this.createdAt,
    this.subjectName,
    this.subjectId,
  });

  final String id;
  final String type;
  final String severity;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? subjectName;
  final String? subjectId;

  bool get isCritical => severity == 'critical';

  static LiveAlert? tryFrom(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String) return null;

    final Object? subject = json['subject'];
    final Map<String, dynamic>? subjectMap =
        subject is Map<String, dynamic> ? subject : null;

    final Object? createdAt = json['createdAt'];

    return LiveAlert(
      id: id,
      type: json['type'] is String ? json['type'] as String : 'unknown',
      severity: json['severity'] is String ? json['severity'] as String : 'info',
      title: json['title'] is String ? json['title'] as String : 'هشدار',
      body: json['body'] is String ? json['body'] as String : '',
      createdAt: createdAt is String
          ? (DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      subjectName: subjectMap?['fullName'] is String
          ? subjectMap!['fullName'] as String
          : null,
      subjectId: subjectMap?['id'] is String ? subjectMap!['id'] as String : null,
    );
  }
}

/// وضعیت لایه‌ی زنده.
@immutable
class RealtimeState {
  const RealtimeState({
    this.status = SocketStatus.disconnected,
    this.locations = const <String, LiveLocation>{},
    this.latestAlert,
  });

  final SocketStatus status;

  /// آخرین موقعیت هر کاربر، کلید = شناسه‌ی کاربر
  final Map<String, LiveLocation> locations;

  /// تازه‌ترین هشدار دریافتی — صفحه‌ها به آن گوش می‌دهند تا نمایشش دهند
  final LiveAlert? latestAlert;

  bool get isConnected => status == SocketStatus.connected;

  RealtimeState copyWith({
    SocketStatus? status,
    Map<String, LiveLocation>? locations,
    LiveAlert? latestAlert,
  }) {
    return RealtimeState(
      status: status ?? this.status,
      locations: locations ?? this.locations,
      latestAlert: latestAlert ?? this.latestAlert,
    );
  }
}

/// مدیریت اتصال زنده.
///
/// ── چرا به وضعیت ورود گره خورده است ─────────────────────────────────────
/// سوکت بدون توکن معتبر بی‌معناست و سوکتِ باز پس از خروج، یک نشت است.
/// این کنترلر به `authControllerProvider` گوش می‌دهد: با ورود وصل می‌شود،
/// با خروج قطع.
///
/// ── و چرا موقعیت‌ها در حافظه نگه داشته می‌شوند ──────────────────────────
/// صفحه‌ی نقشه ممکن است بعد از رسیدن اولین موقعیت باز شود. اگر رویدادها را
/// فقط پخش کنیم و نگه نداریم، نقشه تا رسیدن رویداد بعدی (تا ۳۰ ثانیه)
/// خالی می‌ماند.
class RealtimeController extends StateNotifier<RealtimeState> {
  RealtimeController(this._ref) : super(const RealtimeState()) {
    _bindToAuth();
  }

  final Ref _ref;

  final SocketClient _client = SocketClient();

  StreamSubscription<SocketEvent>? _eventSub;
  StreamSubscription<SocketStatus>? _statusSub;

  void _bindToAuth() {
    _statusSub = _client.status.listen((SocketStatus status) {
      state = state.copyWith(status: status);
    });

    _eventSub = _client.events.listen(_onEvent);

    // اتصال اولیه اگر کاربر از قبل وارد است
    if (_ref.read(authControllerProvider).isAuthenticated) {
      unawaited(connect());
    }

    _ref.listen<bool>(
      isAuthenticatedProvider,
      (bool? previous, bool next) {
        if (next) {
          unawaited(connect());
        } else {
          disconnect();
        }
      },
    );
  }

  /// برقراری اتصال با توکن جاری.
  Future<void> connect() async {
    final String? token = await _ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.isEmpty) return;
    _client.connect(token);
  }

  void disconnect() {
    _client.disconnect();
    // موقعیت‌های ذخیره‌شده هم پاک می‌شوند: داده‌ی موقعیت کاربرِ قبلی نباید
    // پس از خروج در حافظه بماند
    state = const RealtimeState();
  }

  /// اتصال مجدد با توکن تازه.
  ///
  /// پس از تازه‌سازی توکن لازم است: سوکت با توکن قدیمی وصل شده و سرور
  /// ممکن است در اولین بررسی مجدد، قطعش کند.
  Future<void> reconnect() async {
    disconnect();
    await connect();
  }

  void _onEvent(SocketEvent event) {
    switch (event.name) {
      case WsEvents.locationUpdate:
        final LiveLocation? location = LiveLocation.tryFrom(event.data);
        if (location == null) return;

        state = state.copyWith(
          locations: <String, LiveLocation>{
            ...state.locations,
            location.userId: location,
          },
        );
        break;

      case WsEvents.alertNew:
        final LiveAlert? alert = LiveAlert.tryFrom(event.data);
        if (alert != null) state = state.copyWith(latestAlert: alert);
        break;

      case WsEvents.sharingChanged:
        // کاربر اصلی اشتراک‌گذاری را خاموش کرده: موقعیت ذخیره‌شده‌اش باید
        // فوراً از حافظه برود، وگرنه نقشه‌ی مراقب همچنان نقطه‌ی قدیمی را
        // نشان می‌دهد — که دقیقاً همان نشتی است که کاربر می‌خواست ببندد.
        final Object? userId = event.data['userId'];
        final bool enabled = event.data['enabled'] != false;

        if (userId is String && !enabled) {
          final Map<String, LiveLocation> next =
              Map<String, LiveLocation>.from(state.locations)..remove(userId);
          state = state.copyWith(locations: next);
        }
        break;

      default:
        // بقیه‌ی رویدادها در گام‌های بعد استفاده می‌شوند
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _statusSub?.cancel();
    _client.dispose();
    super.dispose();
  }
}

final StateNotifierProvider<RealtimeController, RealtimeState> realtimeControllerProvider =
    StateNotifierProvider<RealtimeController, RealtimeState>((ref) {
  return RealtimeController(ref);
});

/// آخرین موقعیت یک کاربر مشخص — صفحه‌ی نقشه از این استفاده می‌کند.
final ProviderFamily<LiveLocation?, String> liveLocationProvider =
    Provider.family<LiveLocation?, String>((ref, String userId) {
  return ref.watch(realtimeControllerProvider).locations[userId];
});
