# iOS build and release

## Verification status

The iOS target has configuration for location, motion, and background notifications, but a signed iOS archive has not been verified. Complete the build and signing steps on macOS with Xcode 15 or later and an Apple Developer provisioning profile.

## Permissions and background behavior

The iOS target declares location usage descriptions for foreground and background access, motion permission for sensor-based fall detection, and background modes used by location updates and notifications. LSApplicationQueriesSchemes permits the app to open web links and phone calls.

iOS controls background execution. Location mode can extend operation, but it does not guarantee a permanently running tracker. Validate location updates and emergency alerts on a physical device before presenting iOS support as production-ready. Any additional background-task configuration must follow Apple platform requirements.

## Build on macOS

From the mobile/ directory:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

The no-code-sign build is for compilation checks only. To create a distributable IPA, configure signing and a provisioning profile in Xcode, then run:

```bash
flutter build ipa --release
```

Before distribution, replace placeholder app icons, review the location permission explanations, and test background behavior on supported iOS versions.
