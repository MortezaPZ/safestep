import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/utils/fa.dart';

/// تست ابزار فارسی.
///
/// این توابع در ظاهر ساده‌اند اما هر کدامشان یک باگ واقعی را می‌بندند:
/// شماره‌ای که با ارقام فارسی تایپ شده و سرور ردش می‌کند، یا شماره‌ای که
/// با ‎+98‎ ثبت شده و کاربر با ‎09‎ نمی‌تواند وارد شود. تست‌ها همان
/// حالت‌های مرزی را پوشش می‌دهند، نه حالت خوش‌بینانه را.
void main() {
  group('تبدیل ارقام', () {
    test('لاتین به فارسی', () {
      expect(Fa.digits('1404'), '۱۴۰۴');
      expect(Fa.digits('اتاق 12'), 'اتاق ۱۲');
    });

    test('فارسی و عربی به لاتین', () {
      expect(Fa.toLatinDigits('۰۹۱۲۳۴۵۶۷۸۹'), '09123456789');
      expect(Fa.toLatinDigits('٠٩١٢'), '0912');
    });

    test('کاراکترهای غیرعددی دست‌نخورده می‌مانند', () {
      expect(Fa.toLatinDigits('کد: ۱۲۳'), 'کد: 123');
    });
  });

  group('نرمال‌سازی شماره موبایل', () {
    test('قالب‌های مختلف به یک شکل می‌رسند', () {
      const String expected = '09123456789';
      expect(Fa.normalizePhone('09123456789'), expected);
      expect(Fa.normalizePhone('+989123456789'), expected);
      expect(Fa.normalizePhone('00989123456789'), expected);
      expect(Fa.normalizePhone('9123456789'), expected);
      expect(Fa.normalizePhone('۰۹۱۲۳۴۵۶۷۸۹'), expected);
      // فاصله و خط تیره‌ای که کاربر می‌گذارد
      expect(Fa.normalizePhone('0912 345 6789'), expected);
      expect(Fa.normalizePhone('0912-345-6789'), expected);
    });

    test('شماره‌های نامعتبر رد می‌شوند', () {
      expect(Fa.isValidPhone('0812345678'), isFalse);
      expect(Fa.isValidPhone('091234567'), isFalse);
      expect(Fa.isValidPhone('091234567890'), isFalse);
      expect(Fa.isValidPhone(''), isFalse);
    });

    test('شماره‌ی معتبر پذیرفته می‌شود', () {
      expect(Fa.isValidPhone('۰۹۱۲۳۴۵۶۷۸۹'), isTrue);
      expect(Fa.isValidPhone('+98 912 345 6789'), isTrue);
    });
  });

  group('قالب‌بندی', () {
    test('عدد با جداکننده‌ی هزارگان', () {
      expect(Fa.number(1234567), '۱٬۲۳۴٬۵۶۷');
      expect(Fa.number(12), '۱۲');
    });

    test('فاصله', () {
      expect(Fa.distance(85), '۸۵ متر');
      expect(Fa.distance(1250), '۱٫۳ کیلومتر');
    });

    test('چند وقت پیش', () {
      final DateTime now = DateTime(1404, 7, 14, 12);
      expect(Fa.timeAgo(now.subtract(const Duration(seconds: 5)), now: now), 'همین حالا');
      expect(Fa.timeAgo(now.subtract(const Duration(minutes: 3)), now: now), '۳ دقیقه پیش');
      expect(Fa.timeAgo(now.subtract(const Duration(hours: 5)), now: now), '۵ ساعت پیش');
      expect(Fa.timeAgo(now.subtract(const Duration(days: 1)), now: now), 'دیروز');
    });

    test('زمان آینده به «همین حالا» تبدیل می‌شود', () {
      // ساعت گوشی ممکن است چند ثانیه از سرور جلوتر باشد؛ نمایش
      // «۳- دقیقه پیش» برای کاربر بی‌معناست
      final DateTime now = DateTime(1404, 7, 14, 12);
      expect(Fa.timeAgo(now.add(const Duration(minutes: 2)), now: now), 'همین حالا');
    });

    test('حرف اول نام برای آواتار', () {
      expect(Fa.initials('مریم رضایی'), 'م ر');
      expect(Fa.initials('علی'), 'ع');
      expect(Fa.initials('   '), '؟');
    });
  });
}
