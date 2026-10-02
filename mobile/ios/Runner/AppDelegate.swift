import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ── نکته: flutter_foreground_task روی iOS یک سرویس اعلان دائمی ارائه
    // نمی‌دهد. کد فلاتر این موضوع را به درستی مدیریت می‌کند (پاس می‌شود
    // اگر پلتفرم iOS باشد)، ولی این یعنی خود سیستم‌عامل مالک چرخهٔ حیات
    // پس‌زمینه است. `BGTaskScheduler` زیر فقط نقطهٔ شروع برای ردیابی
    // پایدارتر در iOS است و به تنهایی کافی نیست — نیازمند
    // `BGTaskSchedulerPermittedIdentifiers` در Info.plist است.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
