/// پیکربندی ثابتِ زمانِ ساخت.
///
/// مقادیر با `--dart-define` قابل بازنویسی‌اند:
///
/// ```bash
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
/// ```
///
/// ── چرا مقدار پیش‌فرض ‎10.0.2.2‎ است ─────────────────────────────────────
/// در شبیه‌ساز اندروید، `localhost` یعنی خودِ شبیه‌ساز، نه کامپیوترِ میزبان.
/// آدرس ‎10.0.2.2‎ همان میزبان است. این تنها متداول‌ترین اشتباه در اولین
/// اجرای هر اپ موبایل با بک‌اند محلی است، و مقدار پیش‌فرضِ درست، یک ساعت
/// جست‌وجو را حذف می‌کند.
///
/// روی گوشی واقعی باید IP کامپیوتر در همان شبکه‌ی وای‌فای داده شود.
class AppConfig {
  const AppConfig._();

  static const String appName = 'هم‌قدم';
  static const String appNameEn = 'SafeStep';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static const String apiPrefix = '/api/v1';

  static String get apiUrl => '$apiBaseUrl$apiPrefix';

  /// آدرس WebSocket — همان میزبان است، چون socket.io روی همان سرور HTTP
  /// سوار شده و پورت جدایی ندارد.
  static String get socketUrl => apiBaseUrl;

  /// شناسه‌ی کلاینت که در هدر `X-Client` می‌رود و در جدول `request_logs`
  /// می‌نشیند. با آن می‌توان پرسید «تأخیر اپ اندروید چقدر بوده».
  static const String clientHeader = 'X-Client';

  /* ─────────────────────── مهلت‌های شبکه ─────────────────────── */

  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// مهلت ارسال SOS عمداً کوتاه‌تر است: اگر شبکه کند باشد، بهتر است سریع
  /// شکست بخوریم و مسیر جایگزین را امتحان کنیم تا اینکه کاربر پانزده ثانیه
  /// روبه‌روی چرخنده منتظر بماند.
  static const Duration sosTimeout = Duration(seconds: 8);

  /* ─────────────────────── مقادیر پیش‌فرض ─────────────────────── */

  /// تا وقتی پیکربندی از سرور برسد، از این مقدار استفاده می‌شود.
  static const int defaultPingIntervalSec = 30;

  /// سقف دسته‌ی ارسال صف آفلاین — باید با اعتبارسنجی `/locations/batch`
  /// در سرور یکی باشد.
  static const int maxBatchSize = 200;

  /// سقف نگهداری پینگ در صف محلی. پس از این، قدیمی‌ترین‌ها حذف می‌شوند
  /// تا حافظه‌ی گوشی پر نشود.
  static const int maxQueuedPings = 5000;
}
