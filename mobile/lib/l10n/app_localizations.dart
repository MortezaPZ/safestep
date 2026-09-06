import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa')
  ];

  /// No description provided for @login.
  ///
  /// In fa, this message translates to:
  /// **'ورود'**
  String get login;

  /// No description provided for @register.
  ///
  /// In fa, this message translates to:
  /// **'ثبت‌نام'**
  String get register;

  /// No description provided for @roleSelect.
  ///
  /// In fa, this message translates to:
  /// **'نقش خود را انتخاب کنید'**
  String get roleSelect;

  /// No description provided for @home.
  ///
  /// In fa, this message translates to:
  /// **'خانه'**
  String get home;

  /// No description provided for @alerts.
  ///
  /// In fa, this message translates to:
  /// **'هشدارها'**
  String get alerts;

  /// No description provided for @welcomeBack.
  ///
  /// In fa, this message translates to:
  /// **'خوش برگشتید'**
  String get welcomeBack;

  /// No description provided for @loginHint.
  ///
  /// In fa, this message translates to:
  /// **'با شماره‌ای که با آن ثبت‌نام کرده‌اید وارد شوید.'**
  String get loginHint;

  /// No description provided for @phoneLabel.
  ///
  /// In fa, this message translates to:
  /// **'شماره موبایل'**
  String get phoneLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In fa, this message translates to:
  /// **'رمز عبور'**
  String get passwordLabel;

  /// No description provided for @noAccount.
  ///
  /// In fa, this message translates to:
  /// **'حساب ندارم؛ ثبت‌نام می‌کنم'**
  String get noAccount;

  /// No description provided for @language.
  ///
  /// In fa, this message translates to:
  /// **'زبان'**
  String get language;

  /// No description provided for @alertSos.
  ///
  /// In fa, this message translates to:
  /// **'درخواست کمک'**
  String get alertSos;

  /// No description provided for @alertZoneExit.
  ///
  /// In fa, this message translates to:
  /// **'خروج از محدوده'**
  String get alertZoneExit;

  /// No description provided for @alertZoneEnter.
  ///
  /// In fa, this message translates to:
  /// **'بازگشت به محدوده'**
  String get alertZoneEnter;

  /// No description provided for @alertLongStop.
  ///
  /// In fa, this message translates to:
  /// **'توقف طولانی'**
  String get alertLongStop;

  /// No description provided for @alertGpsLost.
  ///
  /// In fa, this message translates to:
  /// **'قطع موقعیت'**
  String get alertGpsLost;

  /// No description provided for @alertLowBattery.
  ///
  /// In fa, this message translates to:
  /// **'باتری کم'**
  String get alertLowBattery;

  /// No description provided for @alertFall.
  ///
  /// In fa, this message translates to:
  /// **'تشخیص سقوط'**
  String get alertFall;

  /// No description provided for @alertGeneric.
  ///
  /// In fa, this message translates to:
  /// **'هشدار'**
  String get alertGeneric;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
