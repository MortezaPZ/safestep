# SafeStep Mobile

Flutter client for the full SafeStep product. It supports the primary user, guardians, and administrators across sign-in, onboarding, location sharing, safe zones, pairing, alerts, SOS, and live tracking.

## Structure

- [`lib/app/`](<lib/app/>) boots the application and defines routes.
- [`lib/core/`](<lib/core/>) contains shared networking, device registration, push notifications, storage, accessibility, and UI foundations.
- [`lib/features/`](<lib/features/>) groups screens and domain logic by product capability.
- [`assets/`](<assets/>) holds the Persian typeface and app images.
- [`android/`](<android/>) and [`ios/`](<ios/>) contain the native platform shells and build configuration.

## Run locally

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4080
```

The default API host is for the Android emulator. On a physical phone, use a reachable computer IP, or enter the server origin on the sign-in screen. The client uses `/api/v1` for REST and the same origin for Socket.IO. See [`../docs/ios-build.md`](<../docs/ios-build.md>) for iOS build and signing requirements.

Flutter analysis and mobile tests are run from this directory with `flutter analyze` and `flutter test`.