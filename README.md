# SafeStep

A safety and location-tracking system for people who want to move independently and for the family members who support them.

## Overview

The mobile app shares location with active guardians. Users can see who is watching and turn sharing off. Emergency signals remain available, and the backend can detect falls, geofence exits, and lost GPS fixes.

## Features

- Live location for active guardianships, with controls for viewing and stopping sharing
- Safe zones with hysteresis for noisy GPS readings at zone boundaries
- Fall detection trained on SisFall; synthetic training data is kept separate from that evaluation
- SOS, alerts, and an append-style notification outbox
- Guardian and administrator web console
- Flutter app for Android and iOS
- Evaluation dashboard for reviewing fall-model and location-monitoring results

## Technology

- Node.js 20+ and Express
- PostgreSQL in production; PGlite for local tests
- Flutter and Socket.IO

## Architecture

    mobile/     Flutter app
    web/        Guardian and administrator interface
    backend/    HTTP API, Socket.IO, geofence and fall services
    docs/       Deployment, evaluation, and platform notes

Production uses DB_DRIVER=pg. The API does not import the test runner.

## Installation

From the backend directory:

    npm install
    npm test
    npm start

The start command runs node src/server.js. Do not commit a real .env file.

The Flutter project is in mobile/. A signed iOS distribution archive has not been verified; see the iOS build guide for build requirements and platform limitations.

## Usage

Seed and run the API, then open the web console. The separate safestep-demo repository contains a seeded walkthrough. This repository is the full product tree, including the Flutter app.

## Documentation

Evaluation data, measured metrics, and model limitations are in the [evaluation materials](docs/evaluation/) and [training reports](docs/phase3/). PostgreSQL deployment instructions are in [docs/deployment-postgres.md](docs/deployment-postgres.md). iOS permissions and build requirements are in [the iOS build guide](docs/ios-build.md).

## Testing

Run the backend suite from the backend directory with npm test.

## Limitations

- A signed iOS distribution archive has not been verified; see docs/ios-build.md.
- Fall-model accuracy and alert thresholds need validation on independent real-world data and devices.
- Map tiles need a network; the API can run without them.
- Production secrets must be long random values. Examples in .env files are for local use.

## License

See the repository license file if one is present.