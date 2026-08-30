import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/pairing/presentation/invite_page.dart';

/// تست استخراج کد از محتوای QR.
///
/// این تابع، مرزِ اپ با دنیای بیرون است: هر رشته‌ای ممکن است از دوربین
/// بیاید — از QR یک محصول در فروشگاه تا لینک یک سایت. باید کد معتبر را
/// بگیرد و به بقیه دست نزند.
void main() {
  group('استخراج کد دعوت از QR', () {
    test('URI اختصاصی اپ خوانده می‌شود', () {
      expect(extractPairingCode('safestep://pair?code=482917'), '482917');
    });

    test('شش رقم خام هم پذیرفته می‌شود', () {
      expect(extractPairingCode('482917'), '482917');
      // کاربر ممکن است کد را با فاصله کپی کند
      expect(extractPairingCode(' 482 917 '), '482917');
    });

    test('ارقام فارسی به لاتین تبدیل می‌شوند', () {
      expect(extractPairingCode('۴۸۲۹۱۷'), '482917');
      expect(extractPairingCode('safestep://pair?code=۴۸۲۹۱۷'), '482917');
    });

    test('محتوای بی‌ربط رد می‌شود', () {
      expect(extractPairingCode('https://example.com'), isNull);
      expect(extractPairingCode('سلام'), isNull);
      expect(extractPairingCode(''), isNull);
      expect(extractPairingCode(null), isNull);
    });

    test('کد با طول نادرست رد می‌شود', () {
      expect(extractPairingCode('12345'), isNull);
      expect(extractPairingCode('1234567'), isNull);
      expect(extractPairingCode('safestep://pair?code=123'), isNull);
    });

    test('QR ساخته‌شده، توسط خودِ اسکنر خوانده می‌شود', () {
      // این تست، رفت‌وبرگشت کامل را می‌بندد: هر تغییری در قالب URI که
      // یکی از دو طرف را بشکند، اینجا دیده می‌شود.
      const String code = '903184';
      expect(extractPairingCode(buildPairingUri(code)), code);
    });
  });
}
