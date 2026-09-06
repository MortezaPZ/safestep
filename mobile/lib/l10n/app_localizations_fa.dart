// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get login => 'ورود';

  @override
  String get register => 'ثبت‌نام';

  @override
  String get roleSelect => 'نقش خود را انتخاب کنید';

  @override
  String get home => 'خانه';

  @override
  String get alerts => 'هشدارها';

  @override
  String get welcomeBack => 'خوش برگشتید';

  @override
  String get loginHint => 'با شماره‌ای که با آن ثبت‌نام کرده‌اید وارد شوید.';

  @override
  String get phoneLabel => 'شماره موبایل';

  @override
  String get passwordLabel => 'رمز عبور';

  @override
  String get noAccount => 'حساب ندارم؛ ثبت‌نام می‌کنم';

  @override
  String get language => 'زبان';

  @override
  String get alertSos => 'درخواست کمک';

  @override
  String get alertZoneExit => 'خروج از محدوده';

  @override
  String get alertZoneEnter => 'بازگشت به محدوده';

  @override
  String get alertLongStop => 'توقف طولانی';

  @override
  String get alertGpsLost => 'قطع موقعیت';

  @override
  String get alertLowBattery => 'باتری کم';

  @override
  String get alertFall => 'تشخیص سقوط';

  @override
  String get alertGeneric => 'هشدار';
}
