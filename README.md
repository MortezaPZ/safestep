# SafeStep

Safety and tracking for someone who wants to go out independently, and for the family that needs a reliable alert when something goes wrong.

The repository has three parts:

- `backend` — Node.js and Express. PostgreSQL in production, embedded PGlite for local tests. Geofences, alerts, and fall detection.
- `web` — the guardian and admin interface.
- `mobile` — the Flutter application.

## Backend

Node.js 20 or newer.

```powershell
cd backend
npm install
npm test
npm start
```

The API listens with `node src/server.js`. A networked PostgreSQL deployment is described in `docs/deployment-postgres.md`. Do not commit a real `.env`.

## Mobile

The Flutter project is in `mobile/`.

## Tests

`npm test` in `backend` runs the API suite.
