import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_config.dart';

/// نام رویدادهای WebSocket.
///
/// این رشته‌ها باید **دقیقاً** با `config/constants.js` سرور یکی باشند.
/// یک غلط تایپی اینجا یعنی رویدادی که هرگز نمی‌رسد و هیچ خطایی هم نمی‌دهد —
/// بدترین نوع باگ. برای همین سرور همین فهرست را در `/config/client` هم
/// برمی‌گرداند و می‌توان در زمان اجرا تطبیقشان را بررسی کرد.
class WsEvents {
  const WsEvents._();

  static const String locationUpdate = 'location:update';
  static const String alertNew = 'alert:new';
  static const String alertRead = 'alert:read';
  static const String sharingChanged = 'sharing:changed';
  static const String zoneState = 'zone:state';
  static const String presence = 'presence';
  static const String notification = 'notification:push';
}

/// وضعیت اتصال زنده.
enum SocketStatus { disconnected, connecting, connected }

/// یک رویداد دریافتی از سرور.
@immutable
class SocketEvent {
  const SocketEvent(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;
}

/// کلاینت WebSocket.
///
/// ── چرا socket.io و نه WebSocket خام ────────────────────────────────────
/// سرور از socket.io استفاده می‌کند و پروتکلش با WebSocket خام سازگار
/// نیست. اما فارغ از آن، دو چیزی که در شبکه‌ی موبایل واقعاً لازم است را
/// آماده می‌دهد: اتصال مجدد خودکار با عقب‌نشینی نمایی، و تشخیص قطعِ
/// خاموش (وقتی اتصال از نظر TCP باز است ولی داده رد و بدل نمی‌شود —
/// اتفاق روزمره در شبکه‌ی موبایل).
///
/// ── توکن در handshake، نه در query ──────────────────────────────────────
/// توکن در `auth` فرستاده می‌شود و نه در آدرس. آدرس در لاگ پراکسی‌ها و
/// سرورهای واسط ثبت می‌شود؛ توکن دسترسی نباید آنجا بنشیند. سرور هم دقیقاً
/// از همان `handshake.auth.token` می‌خواند.
class SocketClient {
  SocketClient();

  io.Socket? _socket;

  final StreamController<SocketEvent> _events =
      StreamController<SocketEvent>.broadcast();
  final StreamController<SocketStatus> _status =
      StreamController<SocketStatus>.broadcast();

  Stream<SocketEvent> get events => _events.stream;
  Stream<SocketStatus> get status => _status.stream;

  SocketStatus _current = SocketStatus.disconnected;
  SocketStatus get currentStatus => _current;

  bool get isConnected => _socket?.connected ?? false;

  /// همه‌ی رویدادهایی که گوش داده می‌شوند.
  static const List<String> _subscribed = <String>[
    WsEvents.locationUpdate,
    WsEvents.alertNew,
    WsEvents.alertRead,
    WsEvents.sharingChanged,
    WsEvents.zoneState,
    WsEvents.presence,
    WsEvents.notification,
  ];

  /// اتصال با توکن دسترسی.
  ///
  /// اگر اتصالی برقرار باشد، اول بسته می‌شود: توکن تازه یعنی نشست تازه، و
  /// نگه داشتن سوکت قدیمی یعنی سروری که با هویت منقضی حرف می‌زند.
  void connect(String accessToken) {
    disconnect();

    _emitStatus(SocketStatus.connecting);

    final io.Socket socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          // فقط WebSocket: بدون این، کتابخانه اول polling را امتحان می‌کند
          // که هم کندتر است و هم روی شبکه‌های موبایل بیشتر قطع می‌شود
          .setTransports(<String>['websocket'])
          .setAuth(<String, dynamic>{'token': accessToken})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(1 << 30)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) => _emitStatus(SocketStatus.connected));
    socket.onDisconnect((_) => _emitStatus(SocketStatus.disconnected));
    socket.onConnectError((Object? error) {
      _emitStatus(SocketStatus.disconnected);
      debugPrint('اتصال زنده برقرار نشد: $error');
    });

    for (final String event in _subscribed) {
      socket.on(event, (dynamic payload) {
        if (payload is Map) {
          _events.add(SocketEvent(event, Map<String, dynamic>.from(payload)));
        }
      });
    }

    _socket = socket;
    socket.connect();
  }

  void disconnect() {
    final io.Socket? socket = _socket;
    if (socket == null) return;

    socket.clearListeners();
    socket.dispose();
    _socket = null;

    _emitStatus(SocketStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _events.close();
    _status.close();
  }

  void _emitStatus(SocketStatus value) {
    if (_current == value) return;
    _current = value;
    if (!_status.isClosed) _status.add(value);
  }
}
