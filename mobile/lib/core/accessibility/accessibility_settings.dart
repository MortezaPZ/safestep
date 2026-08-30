import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات دسترس‌پذیری و ظاهر.
///
/// ── چرا این‌ها در اپ نگه داشته می‌شوند و نه فقط روی سرور ────────────────
/// کاربر باید بتواند **پیش از ورود به حساب** اندازه‌ی متن را بزرگ کند.
/// کسی که نمی‌تواند صفحه‌ی ورود را بخواند، هرگز به تنظیماتِ سمت سرور
/// نمی‌رسد. بنابراین منبع حقیقتِ محلی است و پس از ورود، با سرور همگام
/// می‌شود تا با تعویض گوشی هم از دست نرود.
@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.textScale = 1.0,
    this.highContrast = false,
    this.hapticFeedback = true,
    this.themeMode = ThemeMode.system,
  });

  /// ضریب بزرگ‌نمایی متنِ داخل اپ (۰٫۸ تا ۲٫۰).
  ///
  /// این ضریب **علاوه بر** تنظیم اندازه‌ی متنِ خودِ سیستم‌عامل عمل می‌کند،
  /// نه به‌جای آن. کاربری که در تنظیمات اندروید فونت را بزرگ کرده، همان
  /// بزرگی را اینجا هم می‌بیند و این ضریب رویش سوار می‌شود.
  final double textScale;

  /// حالت کنتراست بالا — پالت رنگ را کاملاً عوض می‌کند.
  final bool highContrast;

  /// بازخورد لمسی. برای کاربر نابینا، تنها تأییدِ غیرشنیداریِ لمس است.
  final bool hapticFeedback;

  final ThemeMode themeMode;

  /// کف و سقف ضریب. زیر ۰٫۸ متن ناخوانا می‌شود و بالای ۲٫۰ چیدمان
  /// صفحه‌ها می‌شکند — و صفحه‌ی شکسته، از متن کوچک هم بدتر است.
  static const double minScale = 0.8;
  static const double maxScale = 2.0;

  /// گام‌های آماده برای دکمه‌های «کوچک‌تر / بزرگ‌تر».
  static const List<double> steps = <double>[0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0];

  AccessibilitySettings copyWith({
    double? textScale,
    bool? highContrast,
    bool? hapticFeedback,
    ThemeMode? themeMode,
  }) {
    return AccessibilitySettings(
      textScale: textScale ?? this.textScale,
      highContrast: highContrast ?? this.highContrast,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccessibilitySettings &&
        other.textScale == textScale &&
        other.highContrast == highContrast &&
        other.hapticFeedback == hapticFeedback &&
        other.themeMode == themeMode;
  }

  @override
  int get hashCode => Object.hash(textScale, highContrast, hapticFeedback, themeMode);
}

/* ════════════════════════════ نگهدارنده‌ی حالت ════════════════════════════ */

const String _kTextScale = 'a11y.textScale';
const String _kHighContrast = 'a11y.highContrast';
const String _kHaptic = 'a11y.haptic';
const String _kThemeMode = 'a11y.themeMode';

class AccessibilityController extends StateNotifier<AccessibilitySettings> {
  AccessibilityController(this._prefs) : super(const AccessibilitySettings()) {
    _load();
  }

  final SharedPreferences _prefs;

  void _load() {
    final double? scale = _prefs.getDouble(_kTextScale);
    final bool? contrast = _prefs.getBool(_kHighContrast);
    final bool? haptic = _prefs.getBool(_kHaptic);
    final String? mode = _prefs.getString(_kThemeMode);

    state = AccessibilitySettings(
      textScale: _clamp(scale ?? 1.0),
      highContrast: contrast ?? false,
      hapticFeedback: haptic ?? true,
      themeMode: _parseMode(mode),
    );
  }

  static double _clamp(double value) => value.clamp(
        AccessibilitySettings.minScale,
        AccessibilitySettings.maxScale,
      );

  static ThemeMode _parseMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setTextScale(double value) async {
    final double clamped = _clamp(value);
    state = state.copyWith(textScale: clamped);
    await _prefs.setDouble(_kTextScale, clamped);
  }

  /// یک پله بزرگ‌تر. اگر روی بیشترین مقدار باشیم، تغییری نمی‌کند.
  Future<void> increaseTextScale() async {
    final List<double> steps = AccessibilitySettings.steps;
    final int index = _closestStepIndex(state.textScale);
    if (index >= steps.length - 1) return;
    await setTextScale(steps[index + 1]);
  }

  Future<void> decreaseTextScale() async {
    final List<double> steps = AccessibilitySettings.steps;
    final int index = _closestStepIndex(state.textScale);
    if (index <= 0) return;
    await setTextScale(steps[index - 1]);
  }

  /// نزدیک‌ترین گام به مقدار فعلی — چون مقدارِ همگام‌شده از سرور ممکن است
  /// دقیقاً روی هیچ گامی ننشیند.
  int _closestStepIndex(double value) {
    final List<double> steps = AccessibilitySettings.steps;
    int best = 0;
    double bestDiff = double.infinity;
    for (int i = 0; i < steps.length; i++) {
      final double diff = (steps[i] - value).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    await _prefs.setBool(_kHighContrast, value);
  }

  Future<void> setHapticFeedback(bool value) async {
    state = state.copyWith(hapticFeedback: value);
    await _prefs.setBool(_kHaptic, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kThemeMode, _modeName(mode));
  }

  /// اعمال مقادیر آمده از سرور.
  ///
  /// فقط زمانی صدا زده می‌شود که کاربر تازه وارد شده باشد؛ در طول کار،
  /// جهت همگام‌سازی برعکس است (اپ → سرور). اگر هر دو جهت همیشه فعال
  /// می‌بود، تغییرِ کاربر با پاسخِ درخواستِ در راه بازنویسی می‌شد.
  Future<void> applyRemote({
    double? textScale,
    bool? highContrast,
    bool? hapticFeedback,
  }) async {
    if (textScale != null) await setTextScale(textScale);
    if (highContrast != null) await setHighContrast(highContrast);
    if (hapticFeedback != null) await setHapticFeedback(hapticFeedback);
  }
}

/* ════════════════════════════ Providerها ════════════════════════════ */

/// در `main.dart` با نمونه‌ی واقعی بازنویسی می‌شود.
/// این الگو باعث می‌شود بارگذاری ناهمگامِ SharedPreferences یک بار در
/// شروع اپ انجام شود و بقیه‌ی برنامه با یک provider همگام کار کند.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider باید در main مقداردهی شود.');
});

final StateNotifierProvider<AccessibilityController, AccessibilitySettings>
    accessibilityProvider =
    StateNotifierProvider<AccessibilityController, AccessibilitySettings>((ref) {
  return AccessibilityController(ref.watch(sharedPreferencesProvider));
});
