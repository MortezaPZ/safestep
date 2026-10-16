# Android client

Use this to install and try the app on an Android phone. You do not need to build from source if you have the APK.

## 1. Install

`hamghadam.apk` is next to the project or under `safestep/docs/` (about 180 MB, a debug build).

1. Copy the file to the phone.
2. Open it and install. If Android warns about an unknown source, allow installs from the app that received the file.

## 2. Server on the computer

```bash
cd backend
npm install
npm run seed
npm start
```

The computer browser should open `http://localhost:4080`.

The phone and the computer must be on the same Wi-Fi network.

Find the computer's IPv4 address with `ipconfig` on Windows. Example: `192.168.1.25`.

In the app, set the server address to:

```text
http://192.168.1.25:4080
```

Use your own address. `localhost` on the phone does not reach the computer.

## 3. Demo login

Password for every seeded account: `Test@1234`.

- Guardian: `09121110002`
- Primary user: `09121110001`

## 4. Build from Android Studio

Open the `mobile` folder.

```bash
cd mobile
flutter pub get
flutter create . --platforms=android
flutter run
```

On a real phone, set the same server address on the login screen.

An iOS IPA is not produced on Windows.

## Field evaluation

Open **Field evaluation** from the primary or guardian home page to register a reference point or submit the SUS questionnaire. For position-error measurements, enter coordinates for a known surveyed point. The GPS button only fills an approximate phone fix; it is not ground truth.

## Mobile test coverage

`mobile/test/widget_test.dart` currently contains one test, which checks server-address normalization. The source package does not contain 25 mobile tests.

## Video

Short guide: `docs/mobile-guide.mp4`.
