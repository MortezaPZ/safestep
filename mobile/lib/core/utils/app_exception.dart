/// خطاهای اپ، با پیام آماده‌ی نمایش به کاربر.
///
/// ── قاعده ───────────────────────────────────────────────────────────────
/// هیچ پیام خطایی نباید مستقیم از سرور یا از کتابخانه‌ی شبکه به کاربر
/// نمایش داده شود. «SocketException: Failed host lookup» برای کاربر
/// بی‌معناست و برایش ترسناک است. هر خطا اینجا به یک پیام فارسیِ قابل فهم و
/// یک «کارِ بعدی» تبدیل می‌شود.
class AppException implements Exception {
  const AppException({
    required this.message,
    this.code,
    this.kind = AppErrorKind.unknown,
    this.fieldErrors,
    this.retryable = true,
  });

  /// پیام فارسی قابل نمایش
  final String message;

  /// کد ماشین‌خوان سرور (مثل `UNAUTHORIZED`) — برای تصمیم‌گیری در کد،
  /// نه برای نمایش
  final String? code;

  final AppErrorKind kind;

  /// خطاهای فیلد به فیلدِ فرم، وقتی اعتبارسنجی سرور رد کرده است
  final Map<String, String>? fieldErrors;

  /// آیا نمایش دکمه‌ی «تلاش دوباره» منطقی است؟
  /// برای «رمز نادرست» منطقی نیست؛ برای «اینترنت قطع است» هست.
  final bool retryable;

  /* ─────────────────── سازنده‌های آماده ─────────────────── */

  static const AppException network = AppException(
    message: 'اتصال اینترنت برقرار نیست. پس از وصل شدن، دوباره تلاش می‌کنیم.',
    kind: AppErrorKind.network,
    code: 'NETWORK',
  );

  static const AppException timeout = AppException(
    message: 'پاسخی از سرور نرسید. لطفاً دوباره تلاش کنید.',
    kind: AppErrorKind.network,
    code: 'TIMEOUT',
  );

  static const AppException unauthorized = AppException(
    message: 'نشست شما پایان یافته است. دوباره وارد شوید.',
    kind: AppErrorKind.auth,
    code: 'UNAUTHORIZED',
    retryable: false,
  );

  static const AppException server = AppException(
    message: 'سرور در حال حاضر پاسخ‌گو نیست. کمی بعد دوباره تلاش کنید.',
    kind: AppErrorKind.server,
    code: 'SERVER',
  );

  static const AppException locationPermission = AppException(
    message: 'برای اشتراک موقعیت، اپ به اجازه‌ی دسترسی به مکان نیاز دارد.',
    kind: AppErrorKind.permission,
    code: 'LOCATION_PERMISSION',
    retryable: false,
  );

  static const AppException locationDisabled = AppException(
    message: 'مکان‌یاب گوشی خاموش است. لطفاً آن را روشن کنید.',
    kind: AppErrorKind.permission,
    code: 'LOCATION_DISABLED',
    retryable: false,
  );

  AppException copyWith({String? message, bool? retryable}) {
    return AppException(
      message: message ?? this.message,
      code: code,
      kind: kind,
      fieldErrors: fieldErrors,
      retryable: retryable ?? this.retryable,
    );
  }

  @override
  String toString() => 'AppException($code): $message';
}

enum AppErrorKind {
  /// قطعی شبکه یا مهلت تمام‌شده — قابل تلاش دوباره
  network,

  /// توکن منقضی یا نامعتبر — کاربر باید دوباره وارد شود
  auth,

  /// ورودی نامعتبر — معمولاً همراه `fieldErrors`
  validation,

  /// دسترسی رد شده (نقش یا سطح دسترسی)
  forbidden,

  /// مجوز سیستم‌عامل (مکان، نوتیفیکیشن)
  permission,

  /// خطای سمت سرور
  server,

  /// هر چیز دیگر
  unknown,
}
