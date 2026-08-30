import 'package:flutter/foundation.dart';

/// مدل‌های احراز هویت.
///
/// ── چرا تجزیه‌ی دستی و نه تولید خودکار کد ───────────────────────────────
/// با `json_serializable`، هر تغییر در مدل نیازمند اجرای `build_runner`
/// است و فایل‌های تولیدشده در مخزن می‌نشینند. برای این تعداد مدل، هزینه‌اش
/// از فایده‌اش بیشتر است.
///
/// اما یک قاعده رعایت می‌شود: **هیچ `as` بی‌محافظ روی داده‌ی سرور**. هر
/// فیلد با بررسی نوع خوانده می‌شود. اگر سرور روزی `null` بفرستد یا نوع
/// فیلدی عوض شود، اپ به‌جای کرش، مقدار پیش‌فرض می‌گیرد.

/// خواندن امن مقادیر از نگاشت JSON.
class Json {
  const Json._();

  static String str(Map<String, dynamic> map, String key, [String fallback = '']) {
    final Object? value = map[key];
    return value is String ? value : fallback;
  }

  static String? strOrNull(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static int intOf(Map<String, dynamic> map, String key, [int fallback = 0]) {
    final Object? value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? intOrNull(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double dbl(Map<String, dynamic> map, String key, [double fallback = 0]) {
    final Object? value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static double? dblOrNull(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool boolOf(Map<String, dynamic> map, String key, [bool fallback = false]) {
    final Object? value = map[key];
    if (value is bool) return value;
    if (value is String) return value == 'true';
    return fallback;
  }

  static DateTime? date(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static List<String> strList(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }

  /// تبدیل امن یک مقدار به نگاشت JSON.
  static Map<String, dynamic>? mapOrNull(Object? value) {
    return value is Map<String, dynamic> ? value : null;
  }

  static List<Map<String, dynamic>> mapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}

/* ═══════════════════════════ کاربر ═══════════════════════════ */

enum UserRole {
  primary,
  guardian,
  admin;

  static UserRole parse(String? raw) {
    switch (raw) {
      case 'guardian':
        return UserRole.guardian;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.primary;
    }
  }

  String get wire => name;

  String get label {
    switch (this) {
      case UserRole.primary:
        return 'کاربر اصلی';
      case UserRole.guardian:
        return 'مراقب';
      case UserRole.admin:
        return 'مدیر سامانه';
    }
  }
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.role,
    this.avatarColor = '#2F6FED',
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String phone;
  final String fullName;
  final UserRole role;
  final String avatarColor;
  final String status;
  final DateTime? createdAt;

  bool get isSuspended => status == 'suspended';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: Json.str(json, 'id'),
      phone: Json.str(json, 'phone'),
      fullName: Json.str(json, 'fullName'),
      role: UserRole.parse(Json.strOrNull(json, 'role')),
      avatarColor: Json.str(json, 'avatarColor', '#2F6FED'),
      status: Json.str(json, 'status', 'active'),
      createdAt: Json.date(json, 'createdAt'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'phone': phone,
        'fullName': fullName,
        'role': role.wire,
        'avatarColor': avatarColor,
        'status': status,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.fullName == fullName &&
      other.role == role &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, fullName, role, status);
}

/* ═══════════════════════════ تنظیمات ═══════════════════════════ */

@immutable
class UserSettings {
  const UserSettings({
    this.locationSharingEnabled = true,
    this.longStopMinutes = 20,
    this.longStopRadiusM = 40,
    this.alertTypes = const <String>[],
    this.pingIntervalSec = 30,
    this.backgroundTrackingEnabled = true,
    this.textScale = 1.0,
    this.highContrastEnabled = false,
    this.hapticFeedbackEnabled = true,
    this.locationRetentionDays = 90,
    this.theme = 'system',
  });

  final bool locationSharingEnabled;
  final int longStopMinutes;
  final int longStopRadiusM;
  final List<String> alertTypes;
  final int pingIntervalSec;
  final bool backgroundTrackingEnabled;
  final double textScale;
  final bool highContrastEnabled;
  final bool hapticFeedbackEnabled;
  final int locationRetentionDays;
  final String theme;

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      locationSharingEnabled: Json.boolOf(json, 'locationSharingEnabled', true),
      longStopMinutes: Json.intOf(json, 'longStopMinutes', 20),
      longStopRadiusM: Json.intOf(json, 'longStopRadiusM', 40),
      alertTypes: Json.strList(json, 'alertTypes'),
      pingIntervalSec: Json.intOf(json, 'pingIntervalSec', 30),
      backgroundTrackingEnabled: Json.boolOf(json, 'backgroundTrackingEnabled', true),
      textScale: Json.dbl(json, 'textScale', 1),
      highContrastEnabled: Json.boolOf(json, 'highContrastEnabled'),
      hapticFeedbackEnabled: Json.boolOf(json, 'hapticFeedbackEnabled', true),
      locationRetentionDays: Json.intOf(json, 'locationRetentionDays', 90),
      theme: Json.str(json, 'theme', 'system'),
    );
  }
}

/* ═══════════════════════════ نشست ═══════════════════════════ */

@immutable
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.settings,
  });

  final AppUser user;
  final String accessToken;
  final String refreshToken;
  final UserSettings? settings;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? userJson = Json.mapOrNull(json['user']);
    final Map<String, dynamic>? settingsJson = Json.mapOrNull(json['settings']);

    if (userJson == null) {
      throw const FormatException('پاسخ سرور شامل اطلاعات کاربر نیست.');
    }

    return AuthSession(
      user: AppUser.fromJson(userJson),
      accessToken: Json.str(json, 'accessToken'),
      refreshToken: Json.str(json, 'refreshToken'),
      settings: settingsJson == null ? null : UserSettings.fromJson(settingsJson),
    );
  }
}
