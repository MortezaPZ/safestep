import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_models.dart';

/// سطوح دسترسی که کاربر اصلی به مراقب می‌دهد.
///
/// این‌ها دقیقاً همان مقادیری‌اند که در جدول `guardianships` سرور ذخیره
/// می‌شوند. برچسب و توضیح فارسی‌شان اینجاست چون تنها جایی که به کاربر نشان
/// داده می‌شوند همین اپ است — و توضیح باید به زبان اثر باشد، نه به زبان
/// فنی: «می‌تواند ببیند کجایید»، نه «view_location».
enum SharePermission {
  viewLocation('view_location'),
  receiveAlerts('receive_alerts'),
  emergency('emergency');

  const SharePermission(this.wire);

  final String wire;

  static SharePermission? tryParse(String? raw) {
    for (final SharePermission value in SharePermission.values) {
      if (value.wire == raw) return value;
    }
    return null;
  }

  static List<SharePermission> parseList(List<String> raw) {
    return raw
        .map(SharePermission.tryParse)
        .whereType<SharePermission>()
        .toList(growable: false);
  }

  String get label {
    switch (this) {
      case SharePermission.viewLocation:
        return 'دیدن موقعیت';
      case SharePermission.receiveAlerts:
        return 'دریافت هشدار';
      case SharePermission.emergency:
        return 'دسترسی اضطراری';
    }
  }

  String get description {
    switch (this) {
      case SharePermission.viewLocation:
        return 'می‌تواند ببیند الان کجا هستید و مسیر امروزتان را مرور کند.';
      case SharePermission.receiveAlerts:
        return 'اگر از محدوده‌ی امن خارج شوید یا مدت طولانی بی‌حرکت بمانید، خبردار می‌شود.';
      case SharePermission.emergency:
        return 'وقتی دکمه‌ی کمک را بزنید، فوراً به او اطلاع داده می‌شود.';
    }
  }
}

/* ═══════════════════════════ کد دعوت ═══════════════════════════ */

@immutable
class InviteCode {
  const InviteCode({
    required this.id,
    required this.permissions,
    required this.expiresAt,
    this.code,
    this.isUsed = false,
    this.createdAt,
  });

  final String id;

  /// خودِ کد شش‌رقمی.
  ///
  /// **فقط یک بار** و در پاسخِ ساختِ کد برمی‌گردد. سرور آن را هش‌شده ذخیره
  /// می‌کند و در فهرست کدها هرگز برنمی‌گرداند — یعنی اگر کاربر صفحه را
  /// ببندد، باید کد تازه بسازد. این محدودیت عمدی است و در رابط کاربری هم
  /// صریح گفته می‌شود.
  final String? code;

  final List<SharePermission> permissions;
  final DateTime expiresAt;
  final bool isUsed;
  final DateTime? createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isUsed && !isExpired;

  Duration get remaining {
    final Duration diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  factory InviteCode.fromJson(Map<String, dynamic> json) {
    return InviteCode(
      id: Json.str(json, 'id'),
      code: Json.strOrNull(json, 'code'),
      permissions: SharePermission.parseList(Json.strList(json, 'permissions')),
      expiresAt: Json.date(json, 'expiresAt') ??
          DateTime.now().add(const Duration(minutes: 15)),
      isUsed: Json.boolOf(json, 'isUsed'),
      createdAt: Json.date(json, 'createdAt'),
    );
  }
}

/* ═══════════════════════════ رابطه‌ی سرپرستی ═══════════════════════════ */

@immutable
class Guardianship {
  const Guardianship({
    required this.id,
    required this.permissions,
    required this.status,
    this.primaryUser,
    this.guardianUser,
    this.nickname,
    this.createdAt,
  });

  final String id;
  final List<SharePermission> permissions;
  final String status;

  /// یکی از این دو پر است، بسته به اینکه از کدام سمت نگاه می‌کنیم.
  final RelatedPerson? primaryUser;
  final RelatedPerson? guardianUser;

  final String? nickname;
  final DateTime? createdAt;

  bool get isActive => status == 'active';

  bool has(SharePermission permission) => permissions.contains(permission);

  factory Guardianship.fromJson(Map<String, dynamic> json) {
    return Guardianship(
      id: Json.str(json, 'id'),
      permissions: SharePermission.parseList(Json.strList(json, 'permissions')),
      status: Json.str(json, 'status', 'active'),
      primaryUser: RelatedPerson.tryFrom(Json.mapOrNull(json['primaryUser'])),
      guardianUser: RelatedPerson.tryFrom(Json.mapOrNull(json['guardianUser'])),
      nickname: Json.strOrNull(json, 'nickname'),
      createdAt: Json.date(json, 'createdAt'),
    );
  }
}

/// خلاصه‌ی طرف مقابل رابطه — همان چیزی که سرور در JOIN برمی‌گرداند.
@immutable
class RelatedPerson {
  const RelatedPerson({
    required this.id,
    required this.fullName,
    this.phone,
    this.avatarColor = '#2F6FED',
  });

  final String id;
  final String fullName;
  final String? phone;
  final String avatarColor;

  static RelatedPerson? tryFrom(Map<String, dynamic>? json) {
    if (json == null) return null;
    final String id = Json.str(json, 'id');
    if (id.isEmpty) return null;

    return RelatedPerson(
      id: id,
      fullName: Json.str(json, 'fullName', 'بدون نام'),
      phone: Json.strOrNull(json, 'phone'),
      avatarColor: Json.str(json, 'avatarColor', '#2F6FED'),
    );
  }
}

/// پاسخ `GET /guardianships` — دو فهرست جدا.
///
/// یک نفر می‌تواند هم‌زمان هر دو را داشته باشد: مادری که موقعیتش را با
/// فرزندش به اشتراک می‌گذارد و خودش هم مراقب مادرِ خودش است.
@immutable
class GuardianshipLists {
  const GuardianshipLists({
    this.guardians = const <Guardianship>[],
    this.watching = const <Guardianship>[],
  });

  /// کسانی که موقعیت **من** را می‌بینند
  final List<Guardianship> guardians;

  /// کسانی که **من** موقعیتشان را می‌بینم
  final List<Guardianship> watching;

  bool get isEmpty => guardians.isEmpty && watching.isEmpty;

  factory GuardianshipLists.fromJson(Map<String, dynamic> json) {
    return GuardianshipLists(
      guardians: Json.mapList(json['guardians'])
          .map(Guardianship.fromJson)
          .toList(growable: false),
      // سرور این فهرست را `primaries` می‌نامد (کاربران اصلی‌ای که من
      // مراقبشانم). نام محلی‌اش `watching` است چون از دید اپ، معنایش
      // «کسانی که پایششان می‌کنم» است.
      watching: Json.mapList(json['primaries'])
          .map(Guardianship.fromJson)
          .toList(growable: false),
    );
  }
}
