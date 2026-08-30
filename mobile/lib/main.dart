import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/accessibility/accessibility_settings.dart';

/// نقطه‌ی ورود اپ.
///
/// ── چرا این‌همه کار پیش از `runApp` ─────────────────────────────────────
/// تنظیمات دسترس‌پذیری (اندازه‌ی متن، کنتراست) باید **پیش از اولین فریم**
/// آماده باشند. اگر بعداً بارگذاری شوند، کاربری که متن را دو برابر کرده،
/// یک لحظه صفحه‌ی ریز می‌بیند و بعد صفحه می‌پرد. برای کاربر کم‌بینا این
/// «یک لحظه» یعنی یک صفحه‌ی کاملاً ناخوانا.
///
/// خواندن SharedPreferences چند میلی‌ثانیه طول می‌کشد؛ ارزش این را دارد که
/// اولین فریم درست باشد.
Future<void> main() async {
  // در همان zone‌ای که runApp اجرا می‌شود، تا خطاهای ناهمگام هم گرفته شوند
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // اپ فقط عمودی کار می‌کند. دلیلش تصمیم طراحی نیست، تصمیم ایمنی است:
      // دکمه‌ی اضطراری باید همیشه در یک جای ثابت باشد. کاربری که در وضعیت
      // اضطرار است، نباید با چیدمانی روبه‌رو شود که جای دکمه در آن عوض شده.
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
      ));

      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // خطاهای ویجت‌ها در حالت انتشار نباید صفحه‌ی قرمز نشان دهند
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        if (kReleaseMode) {
          // در فاز بعد، اینجا به سرویس گزارش خطا وصل می‌شود
          debugPrint('خطای ویجت: ${details.exceptionAsString()}');
        }
      };

      runApp(
        ProviderScope(
          overrides: <Override>[
            // نمونه‌ی واقعی، جایگزین provider خطاانداز می‌شود
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const SafeStepApp(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      debugPrint('خطای مدیریت‌نشده: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}
