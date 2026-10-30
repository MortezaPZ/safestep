# SafeStep

A safety and tracking system for someone who wants to go out independently, and for the family that needs a reliable alert when something goes wrong.

## Overview

The person can see who is watching and can stop sharing. The family still gets an emergency signal when the person asks for help, and the backend can raise a fall, a geofence exit, or a lost GPS fix.

## Features

- Live location for an active guardianship
- Safe zones, with hysteresis so a noisy GPS fix on the boundary does not flap
- Fall detection trained on SisFall, plus the earlier synthetic dataset kept separate from that evaluation
- Alerts, SOS, and an append-style notification outbox
- A web console for guardians and admins
- A Flutter client for Android and iOS

## Technology Stack

- Node.js 20+ and Express
- PostgreSQL in production
- PGlite for the local test database
- Flutter
- Socket.IO

## Architecture

```
mobile/     Flutter client
web/        Guardian and admin interface
backend/    HTTP API, Socket.IO, geofence and fall services
docs/       Deployment and evaluation notes
```

The API does not import the test runner. Production uses `DB_DRIVER=pg`. Tests use the embedded PostgreSQL-compatible engine so the suite does not need a server.

Fall-model metrics, load-test numbers, and the geofence hysteresis table are in `docs/evaluation/defense-and-metrics.md`. iOS build status is in `docs/ios-build-status.md`. A networked PostgreSQL deployment is in `docs/deployment-postgres.md`.

## Installation

```powershell
cd backend
npm install
npm test
npm start
```

`npm start` runs `node src/server.js`. Do not commit a real `.env`.

The Flutter project is in `mobile/`. An iOS archive needs Xcode on macOS. This Windows tree cannot produce an IPA. The Info.plist permission keys required by location, motion, and background alerts are documented in `docs/ios-build-status.md`.

## Usage

Seed and run the API, then open the web console. Guardian accounts, zones, and alerts are part of the backend. The demo-oriented walkthrough with seeded phone numbers lives in the separate `safestep-demo` repository. This repository is the full product tree, including the Flutter app.

## Testing

Run the backend suite from the backend directory with npm test.

Known issue: some safe-zone integration cases return HTTP 403 where the tests expect HTTP 201. The affected cases are in backend/tests/safezones.integration.test.js and should be resolved before a production release.
## Limitations

- iOS has not been archived on a Mac in this workspace
- Map tiles need a network. The API can run without them
- Production secrets must be long random values. The examples in `.env` files are for local use
