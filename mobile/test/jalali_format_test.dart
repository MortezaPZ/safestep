import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/utils/jalali_format.dart';

void main() {
  test('تاریخ شمسی با ارقام فارسی قالب می‌شود', () {
    final DateTime t = DateTime(2025, 10, 6, 8, 35);
    expect(JalaliFormat.date(t), contains('مهر'));
    expect(JalaliFormat.time(t), '۰۸:۳۵');
  });
}
