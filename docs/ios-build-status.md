# iOS build status

No iOS archive has been produced.

This machine is Windows. Xcode runs only on macOS, so `xcodebuild` and `codesign` are not available here. No IPA was fabricated, and this note does not claim one was compiled.

What did change are Flutter gaps that would have broken a real iOS build.

## Info.plist keys

`ios/Runner/Info.plist` had no location, motion, or background keys.

- Without a location usage string, `Geolocator` gets no iOS permission and the request fails with `kCLAuthorizationStatusDenied`. Tracking, exit alerts, and SOS would not run.
- `sensors_plus` crashes on the first read without `NSMotionUsageDescription`.
- `flutter_local_notifications` cannot show a background alert without `UIBackgroundModes`.
- `url_launcher` cannot open a `tel:` link from the alert screen without `LSApplicationQueriesSchemes`.

Keys added:

| Key | Why |
| --- | --- |
| `NSLocationWhenInUseUsageDescription` | Required for `Geolocator` while the app is in use |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Always permission, and the basis of the `location` background mode |
| `NSMotionUsageDescription` | Accelerometer and gyroscope. Missing key crashes `sensors_plus` |
| `UIBackgroundModes` = `fetch`, `location`, `remote-notification` | Live location and alerts in the background |
| `LSApplicationQueriesSchemes` = `https`, `tel` | Open a link or dial from the alert screen |
| `UIRequiresPersistentWiFi` = false | Ordinary default |

## Background queue on iOS

`flutter_foreground_task` does not provide a persistent notification service on iOS. `_startForegroundService()` returns immediately unless the platform is Android-like. iOS shows no "SafeStep is active" notification, and iOS stops location after a short background execution window.

`UIBackgroundModes: location` extends that window. A truly persistent iOS tracker still needs `BGTaskScheduler` in `AppDelegate.swift`, `BGTaskSchedulerPermittedIdentifiers`, and the `background-processing` capability. That was not implemented. Writing Swift that cannot be compiled on this machine would not have been a verified fix. A comment in `AppDelegate.swift` records the gap.

## What a real archive still needs

None of this can be done on the current Windows machine.

1. macOS with Xcode 15+ for `xcodebuild`.
2. An Apple Developer account for signing and TestFlight.
3. A development or distribution certificate and a provisioning profile. `CODE_SIGN_STYLE` is `Automatic`.
4. `pod install` on the Mac, the first time.
5. Real iOS icons. The imported Flutter `Assets.xcassets` placeholders are still there.
6. A review-ready location usage string. Apple often rejects a vague always-location justification.
7. An App Store Connect listing.
8. Manual review, because motion and background location are flagged.

## Build command, once Xcode is available

```bash
cd mobile
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  --no-codesign
```

`--no-codesign` is only for a local check. A store upload drops that flag, uses a developer account, and then:

```bash
xcrun altool --upload-app --type ios -f build/ios/ipa/SafeStep.ipa \
  --apiKey <APPLE_API_KEY> --apiIssuer <APPLE_API_ISSUER>
```

## Result

- IPA built: no.
- Info.plist keys that iOS requires for the core features: yes.
- Would the app have obtained a location permission without those keys: no.
