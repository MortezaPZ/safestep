# Android client setup

## Prerequisites

Install Flutter 3.22 or newer and the Android SDK. The backend requires Node.js 20 or newer.

## Start the local API

From backend, install dependencies, create local development seed data, and start the API:

- npm install
- npm run seed
- npm start

The API listens on port 4080 by default. Seeded accounts and data are for local development only. Do not reuse them in production or expose the development server to the public internet.

## Run the Android app

From mobile, install Flutter packages and launch the app:

- flutter pub get
- flutter run

The Android emulator uses http://10.0.2.2:4080 by default. For a physical device on the same private network, set API_BASE_URL at build time, for example with --dart-define=API_BASE_URL=http://192.168.1.20:4080.

An iOS build requires Xcode on macOS.
