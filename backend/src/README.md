# Backend Source

[Backend overview](../README.md)

This folder contains the runtime entry points and application modules for the SafeStep API.

- `server.js` starts the HTTP and Socket.IO servers; `app.js` composes middleware and routes.
- `config/` reads environment settings and shared constants.
- `controllers/` handles HTTP request and response mapping.
- `db/` owns database setup, migrations, seeding, and admin creation.
- `middleware/` handles authentication, validation, rate limits, errors, and request logs.
- `realtime/` manages Socket.IO connections and broadcasts.
- `repositories/` performs database reads and writes.
- `routes/` maps API paths to controllers.
- `services/` holds business rules, including geofencing, notifications, SOS, and fall workflows.
- `utils/` contains shared cryptography, geometry, logging, and error helpers.

The OpenAPI description is in `docs/openapi.yaml`. SQL migrations are versioned under `db/migrations/`.
