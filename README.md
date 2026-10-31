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

Evaluation methodology, measured results, and limitations are in [docs/evaluation/results-and-limitations.md](docs/evaluation/results-and-limitations.md). iOS permissions and build requirements are in [docs/ios-build.md](docs/ios-build.md). PostgreSQL deployment is in [docs/deployment-postgres.md](docs/deployment-postgres.md).

## Installation

```powershell
cd backend
npm install
npm test
npm start
```

`npm start` runs `node src/server.js`. Do not commit a real `.env`.

The Flutter project is in mobile/. No signed iOS distribution archive has been verified; see docs/ios-build.md for build requirements and platform limits.

## Usage

Seed and run the API, then open the web console. Guardian accounts, zones, and alerts are part of the backend. The demo-oriented walkthrough with seeded phone numbers lives in the separate `safestep-demo` repository. This repository is the full product tree, including the Flutter app.

## Safe-zone ownership

A primary user can create zones for their own account. A main supervisor can create zones for a linked primary user.

## Testing

Run the backend suite from the backend directory with npm test.

## Limitations

- A signed iOS distribution archive has not been verified; see docs/ios-build.md.
- Map tiles need a network. The API can run without them
- Production secrets must be long random values. The examples in `.env` files are for local use
