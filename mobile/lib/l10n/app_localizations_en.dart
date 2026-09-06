// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get login => 'Log in';

  @override
  String get register => 'Sign up';

  @override
  String get roleSelect => 'Choose your role';

  @override
  String get home => 'Home';

  @override
  String get alerts => 'Alerts';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get loginHint => 'Sign in with the phone number you registered.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get passwordLabel => 'Password';

  @override
  String get noAccount => 'No account? Sign up';

  @override
  String get language => 'Language';

  @override
  String get alertSos => 'Help request';

  @override
  String get alertZoneExit => 'Left the safe zone';

  @override
  String get alertZoneEnter => 'Returned to the safe zone';

  @override
  String get alertLongStop => 'Long stop';

  @override
  String get alertGpsLost => 'Location lost';

  @override
  String get alertLowBattery => 'Low battery';

  @override
  String get alertFall => 'Fall detected';

  @override
  String get alertGeneric => 'Alert';
}
