import 'package:shamsi_date/shamsi_date.dart';

import 'fa.dart';

/// قالب‌بندی تاریخ و ساعت شمسی.
///
/// همه‌ی زمان‌ها از سرور به‌صورت UTC و با قالب ISO می‌آیند و پیش از نمایش
/// به وقت محلی گوشی تبدیل می‌شوند. اگر این تبدیل جا بیفتد، کاربر ایرانی
/// همه‌چیز را سه‌ونیم ساعت عقب می‌بیند — خطایی که در تست روی شبیه‌ساز با
/// منطقه‌ی زمانی UTC هرگز دیده نمی‌شود.
class JalaliFormat {
  const JalaliFormat._();

  static const List<String> _months = <String>[
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];

  static const List<String> _weekDays = <String>[
    'شنبه', 'یک‌شنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه',
  ];

  /// تجزیه‌ی رشته‌ی ISO سرور به زمان محلی. در برابر ورودی خراب، null.
  static DateTime? parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final DateTime? parsed = DateTime.tryParse(iso);
    return parsed?.toLocal();
  }

  /// «۱۴ مهر ۱۴۰۴»
  static String date(DateTime time) {
    final Jalali j = Jalali.fromDateTime(time.toLocal());
    return '${Fa.digits(j.day.toString())} ${_months[j.month - 1]} ${Fa.digits(j.year.toString())}';
  }

  /// «۱۴ مهر»  — برای وقتی سال از متن اطراف معلوم است
  static String dateShort(DateTime time) {
    final Jalali j = Jalali.fromDateTime(time.toLocal());
    return '${Fa.digits(j.day.toString())} ${_months[j.month - 1]}';
  }

  /// «۰۸:۳۵»
  static String time(DateTime value) {
    final DateTime local = value.toLocal();
    final String h = local.hour.toString().padLeft(2, '0');
    final String m = local.minute.toString().padLeft(2, '0');
    return Fa.digits('$h:$m');
  }

  /// «چهارشنبه، ۱۴ مهر ۱۴۰۴ — ۰۸:۳۵»
  static String full(DateTime value) {
    final DateTime local = value.toLocal();
    final Jalali j = Jalali.fromDateTime(local);
    // در تقویم شمسی، هفته از شنبه شروع می‌شود؛ `weekDay` مقدار ۱ تا ۷
    // برمی‌گرداند که ۱ یعنی شنبه.
    final String weekDay = _weekDays[(j.weekDay - 1).clamp(0, 6)];
    return '$weekDay، ${date(local)} — ${time(local)}';
  }

  /// برچسب هوشمند برای فهرست‌ها: امروز و دیروز نام دارند، بقیه تاریخ.
  ///
  /// کاربر وقتی می‌بیند «امروز، ۰۸:۳۵»، بی‌درنگ می‌فهمد؛ «۱۴ مهر ۱۴۰۴»
  /// یک قدم محاسبه‌ی ذهنی لازم دارد.
  static String smart(DateTime value) {
    final DateTime local = value.toLocal();
    final Jalali target = Jalali.fromDateTime(local);
    final Jalali today = Jalali.fromDateTime(DateTime.now());

    final int diff = target.distanceTo(today);

    if (diff == 0) return 'امروز، ${time(local)}';
    if (diff == 1) return 'دیروز، ${time(local)}';
    if (diff > 1 && diff < 7) return '${_weekDays[(target.weekDay - 1).clamp(0, 6)]}، ${time(local)}';
    return '${dateShort(local)}، ${time(local)}';
  }

  /// برچسب یک روز کامل برای انتخابگر تاریخچه: «امروز» / «دیروز» / «۱۲ مهر»
  static String dayLabel(DateTime value) {
    final DateTime local = value.toLocal();
    final Jalali target = Jalali.fromDateTime(local);
    final Jalali today = Jalali.fromDateTime(DateTime.now());
    final int diff = target.distanceTo(today);

    if (diff == 0) return 'امروز';
    if (diff == 1) return 'دیروز';
    return dateShort(local);
  }
}
