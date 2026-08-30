import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_config.dart';
import '../domain/location_sample.dart';

/// صف محلی نمونه‌های موقعیت.
///
/// ── چرا SQLite و نه فایل یا SharedPreferences ───────────────────────────
/// این صف باید سه کار را هم‌زمان انجام دهد: نوشتنِ مکرر (هر ۳۰ ثانیه)،
/// خواندنِ دسته‌ای مرتب‌شده، و حذفِ دقیقِ همان ردیف‌هایی که با موفقیت
/// فرستاده شده‌اند. با فایل JSON، هر نوشتن یعنی بازنویسی کل فایل و هر
/// قطع‌شدنِ ناگهانی یعنی فایل خراب.
///
/// مهم‌تر: نوشتن باید در برابر کشته‌شدنِ ناگهانی پردازه (که اندروید مدام
/// انجامش می‌دهد) مقاوم باشد. تراکنش SQLite دقیقاً همین را می‌دهد.
///
/// ── سیاست پر شدن صف ─────────────────────────────────────────────────────
/// اگر کاربر یک روز کامل بدون اینترنت باشد، صف بزرگ می‌شود. سقفی وجود دارد
/// و پس از آن **قدیمی‌ترین** رکوردها حذف می‌شوند، نه جدیدترین‌ها: در یک
/// سامانه‌ی ایمنی، موقعیت نیم‌ساعت پیش از موقعیت دیروز مهم‌تر است.
class LocationQueue {
  LocationQueue();

  static const String _table = 'pending_pings';
  Database? _db;

  Future<Database> _open() async {
    final Database? existing = _db;
    if (existing != null) return existing;

    final String directory = await getDatabasesPath();
    final Database database = await openDatabase(
      p.join(directory, 'safestep_queue.db'),
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            client_uuid   TEXT    NOT NULL UNIQUE,
            lat           REAL    NOT NULL,
            lng           REAL    NOT NULL,
            recorded_at   INTEGER NOT NULL,
            accuracy_m    REAL,
            speed_mps     REAL,
            heading_deg   REAL,
            battery_level INTEGER,
            provider      TEXT
          )
        ''');
        // پرتکرارترین کوئری: «قدیمی‌ترین‌ها را به من بده»
        await db.execute(
          'CREATE INDEX idx_pending_time ON $_table (recorded_at ASC)',
        );
      },
    );

    _db = database;
    return database;
  }

  /// افزودن یک نمونه به صف.
  ///
  /// `ConflictAlgorithm.ignore` یعنی اگر همان `client_uuid` قبلاً در صف
  /// باشد، دوباره اضافه نمی‌شود — محافظت در برابر ثبت دوباره‌ی یک نمونه.
  Future<void> add(LocationSample sample) async {
    final Database db = await _open();
    await db.insert(
      _table,
      sample.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _trim(db);
  }

  /// خواندن قدیمی‌ترین نمونه‌ها برای ارسال دسته‌ای.
  Future<List<LocationSample>> take(int limit) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      _table,
      orderBy: 'recorded_at ASC',
      limit: limit,
    );
    return rows.map(LocationSample.fromRow).toList(growable: false);
  }

  /// حذف نمونه‌هایی که با موفقیت ارسال شده‌اند.
  ///
  /// حذف بر اساس `client_uuid` انجام می‌شود و نه بر اساس «n ردیف اول»:
  /// ممکن است در فاصله‌ی خواندن و حذف، نمونه‌ی تازه‌ای اضافه شده باشد.
  Future<int> remove(List<String> clientUuids) async {
    if (clientUuids.isEmpty) return 0;

    final Database db = await _open();
    final String placeholders = List<String>.filled(clientUuids.length, '?').join(',');

    return db.delete(
      _table,
      where: 'client_uuid IN ($placeholders)',
      whereArgs: clientUuids,
    );
  }

  Future<int> count() async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    final Object? value = rows.isEmpty ? 0 : rows.first['c'];
    return value is int ? value : 0;
  }

  /// پاک کردن کل صف — هنگام خروج از حساب.
  ///
  /// داده‌ی موقعیتِ یک کاربر نباید روی گوشی بماند تا کاربر بعدی واردش کند
  /// و ناخواسته به حساب او ارسال شود.
  Future<void> clear() async {
    final Database db = await _open();
    await db.delete(_table);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// اعمال سقف صف: قدیمی‌ترین‌ها حذف می‌شوند.
  Future<void> _trim(Database db) async {
    final int total = await count();
    if (total <= AppConfig.maxQueuedPings) return;

    final int excess = total - AppConfig.maxQueuedPings;
    await db.rawDelete(
      'DELETE FROM $_table WHERE id IN '
      '(SELECT id FROM $_table ORDER BY recorded_at ASC LIMIT ?)',
      <Object?>[excess],
    );
  }
}

final Provider<LocationQueue> locationQueueProvider = Provider<LocationQueue>((ref) {
  final LocationQueue queue = LocationQueue();
  ref.onDispose(queue.close);
  return queue;
});
