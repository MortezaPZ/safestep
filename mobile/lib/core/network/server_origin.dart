import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_config.dart';

/// مبدأ سرور که کاربر روی صفحه‌ی ورود می‌گذارد.
class ServerOrigin {
  ServerOrigin._();

  static const String prefKey = 'server_origin';

  static String current = AppConfig.apiBaseUrl;

  static String normalize(String raw) {
    String value = raw.trim();
    if (value.isEmpty) return AppConfig.apiBaseUrl;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return value.replaceAll(RegExp(r'/+$'), '');
    }
    final String port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static void set(String raw) {
    current = normalize(raw);
  }

  static String get apiUrl => '$current${AppConfig.apiPrefix}';

  static String get socketUrl => current;

  static String get tileUrl => '$current/tiles/{z}/{x}/{y}.png';

  static Future<void> loadSaved() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(prefKey);
    if (stored != null && stored.isNotEmpty) {
      current = normalize(stored);
    }
  }

  static Future<void> save(String raw) async {
    set(raw);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, current);
  }
}
