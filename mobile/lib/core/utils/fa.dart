/// ابزار متن و عدد فارسی.
///
/// ── چرا این مهم است ─────────────────────────────────────────────────────
/// نمایش «12 دقیقه پیش» در یک رابط فارسی، همان‌قدر بد است که نمایش
/// «۱۲ minutes ago» در یک رابط انگلیسی. کاربر سالمندِ فارسی‌زبان، ارقام
/// لاتین را کندتر می‌خواند و گاهی اصلاً نمی‌خواند.
///
/// اما یک استثنا هست و عمدی است: **کد دعوت** و **شماره موبایل** با ارقام
/// لاتین نمایش داده می‌شوند، چون کاربر باید آن‌ها را روی صفحه‌کلید تایپ
/// کند و صفحه‌کلید ارقام لاتین می‌فرستد.
class Fa {
  const Fa._();

  static const List<String> _persianDigits = <String>[
    '۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹',
  ];

  /// تبدیل ارقام لاتین یک رشته به فارسی.
  static String digits(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int code in input.runes) {
      if (code >= 0x30 && code <= 0x39) {
        buffer.write(_persianDigits[code - 0x30]);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// تبدیل ارقام فارسی و عربی به لاتین.
  ///
  /// روی هر ورودی کاربر اجرا می‌شود: صفحه‌کلید فارسی گوشی ارقام فارسی
  /// می‌فرستد و اگر تبدیل نکنیم، `int.parse` روی شماره موبایل می‌شکند.
  static String toLatinDigits(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int code in input.runes) {
      if (code >= 0x06F0 && code <= 0x06F9) {
        // ارقام فارسی
        buffer.writeCharCode(0x30 + (code - 0x06F0));
      } else if (code >= 0x0660 && code <= 0x0669) {
        // ارقام عربی
        buffer.writeCharCode(0x30 + (code - 0x0660));
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// عدد با جداکننده‌ی هزارگان و ارقام فارسی: ۱۲٬۳۴۵
  static String number(num value) {
    final String raw = value.toStringAsFixed(0);
    final bool negative = raw.startsWith('-');
    final String body = negative ? raw.substring(1) : raw;

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < body.length; i++) {
      if (i > 0 && (body.length - i) % 3 == 0) buffer.write('٬');
      buffer.write(body[i]);
    }
    return digits('${negative ? '-' : ''}$buffer');
  }

  /// فاصله‌ی متری به شکل خوانا: «۸۵ متر» یا «۱٫۲ کیلومتر»
  static String distance(double meters) {
    if (meters < 1000) return '${digits(meters.round().toString())} متر';
    final double km = meters / 1000;
    return '${digits(km.toStringAsFixed(1).replaceAll('.', '٫'))} کیلومتر';
  }

  /// درصد: «۷۸٪»
  static String percent(num value) => '${digits(value.round().toString())}٪';

  /// مدت زمان به شکل محاوره‌ای.
  static String duration(Duration d) {
    if (d.inSeconds < 60) return 'کمتر از یک دقیقه';
    if (d.inMinutes < 60) return '${digits(d.inMinutes.toString())} دقیقه';
    if (d.inHours < 24) {
      final int minutes = d.inMinutes % 60;
      if (minutes == 0) return '${digits(d.inHours.toString())} ساعت';
      return '${digits(d.inHours.toString())} ساعت و ${digits(minutes.toString())} دقیقه';
    }
    return '${digits(d.inDays.toString())} روز';
  }

  /// «چند وقت پیش» — نسبت به الان.
  ///
  /// عمداً محاوره‌ای است، نه دقیق: «۳ دقیقه پیش» برای کاربر معنا دارد،
  /// «۱۸۷ ثانیه پیش» ندارد.
  static String timeAgo(DateTime time, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final Duration diff = reference.difference(time);

    if (diff.isNegative) return 'همین حالا';
    if (diff.inSeconds < 10) return 'همین حالا';
    if (diff.inSeconds < 60) return '${digits(diff.inSeconds.toString())} ثانیه پیش';
    if (diff.inMinutes < 60) return '${digits(diff.inMinutes.toString())} دقیقه پیش';
    if (diff.inHours < 24) return '${digits(diff.inHours.toString())} ساعت پیش';
    if (diff.inDays == 1) return 'دیروز';
    if (diff.inDays < 7) return '${digits(diff.inDays.toString())} روز پیش';
    if (diff.inDays < 30) return '${digits((diff.inDays ~/ 7).toString())} هفته پیش';
    if (diff.inDays < 365) return '${digits((diff.inDays ~/ 30).toString())} ماه پیش';
    return '${digits((diff.inDays ~/ 365).toString())} سال پیش';
  }

  /// نرمال‌سازی شماره موبایل به قالب ۱۱ رقمی — هم‌راستا با همان منطقی که
  /// بک‌اند در `normalizePhone` دارد. اگر این دو از هم جدا بیفتند، کاربری
  /// که با ‎+98‎ ثبت‌نام کرده با ‎09‎ نمی‌تواند وارد شود.
  static String normalizePhone(String input) {
    final String latin = toLatinDigits(input);
    final String onlyDigits = latin.replaceAll(RegExp(r'\D'), '');

    if (onlyDigits.startsWith('0098')) return '0${onlyDigits.substring(4)}';
    if (onlyDigits.startsWith('98') && onlyDigits.length == 12) {
      return '0${onlyDigits.substring(2)}';
    }
    if (onlyDigits.startsWith('9') && onlyDigits.length == 10) return '0$onlyDigits';
    return onlyDigits;
  }

  /// اعتبارسنجی شماره موبایل ایرانی.
  static bool isValidPhone(String input) {
    final String normalized = normalizePhone(input);
    return RegExp(r'^09\d{9}$').hasMatch(normalized);
  }

  /// نمایش خوانای شماره: ۰۹۱۲ ۳۴۵ ۶۷۸۹
  static String formatPhone(String phone) {
    final String p = normalizePhone(phone);
    if (p.length != 11) return p;
    return '${p.substring(0, 4)} ${p.substring(4, 7)} ${p.substring(7)}';
  }

  /// کوتاه کردن نام برای آواتار: «مریم رضایی» → «م ر»
  static String initials(String fullName) {
    final List<String> parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return '${parts[0].substring(0, 1)} ${parts[1].substring(0, 1)}';
  }
}
