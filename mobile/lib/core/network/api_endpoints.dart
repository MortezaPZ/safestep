/// مسیرهای API.
///
/// همه‌ی رشته‌های مسیر در یک فایل جمع شده‌اند تا هیچ‌جای اپ رشته‌ی خام
/// ننویسیم. فایده‌اش وقتی معلوم می‌شود که سرور مسیری را تغییر دهد: یک نقطه
/// عوض می‌شود، نه پنج فایل — و مهم‌تر، غلط تایپی در مسیر، به‌جای خطای زمان
/// اجرا، خطای زمان کامپایل می‌دهد.
///
/// مسیرها نسبی‌اند؛ پیشوند `/api/v1` در `AppConfig.apiUrl` نشسته است.
class ApiEndpoints {
  const ApiEndpoints._();

  /* ─────────────────────── احراز هویت ─────────────────────── */

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String logoutAll = '/auth/logout-all';
  static const String me = '/auth/me';
  static const String otpRequest = '/auth/otp/request';
  static const String otpVerify = '/auth/otp/verify';
  static const String publicConfig = '/config/public';

  /* ─────────────────────── سرپرستی ─────────────────────── */

  static const String invites = '/guardianships/invites';
  static String invite(String id) => '/guardianships/invites/$id';
  static const String redeem = '/guardianships/redeem';
  static const String guardianships = '/guardianships';
  static String guardianship(String id) => '/guardianships/$id';

  /* ─────────────────────── موقعیت ─────────────────────── */

  static const String ping = '/locations/ping';
  static const String batch = '/locations/batch';
  static const String locationStatus = '/locations/status';
  static const String watching = '/locations/watching';
  static const String currentLocation = '/locations/current';
  static const String history = '/locations/history';
  static const String historyDays = '/locations/history/days';
  static const String sharing = '/locations/sharing';

  /* ─────────────────────── هشدار و SOS ─────────────────────── */

  static const String alerts = '/alerts';
  static String alertRead(String id) => '/alerts/$id/read';
  static const String alertsReadAll = '/alerts/read-all';
  static String alertResolve(String id) => '/alerts/$id/resolve';

  static const String sos = '/sos';
  static const String sosContacts = '/sos/contacts';
  static const String sosActive = '/sos/active';

  /* ─────────────────────── محدوده‌های امن ─────────────────────── */

  static const String safeZones = '/safe-zones';
  static String safeZone(String id) => '/safe-zones/$id';

  /* ─────────────────────── ارزیابی میدانی ─────────────────────── */

  static const String evaluationReference = '/evaluation/reference';
  static const String evaluationSus = '/evaluation/sus';

  /* ─────────────────────── تنظیمات و دستگاه ─────────────────────── */

  static const String fallsDetect = '/falls/detect';
  static const String fallsReportMissed = '/falls/report-missed';
  static String fallFeedback(String id) => '/falls/$id/feedback';
  static const String falls = '/falls';
  static const String clientConfig = '/config/client';
  static const String settings = '/settings';
  static const String devices = '/devices';
  static String device(String id) => '/devices/$id';
}
