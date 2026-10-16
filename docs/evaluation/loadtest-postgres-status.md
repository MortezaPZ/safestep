# PostgreSQL load test status

The historical run completed. Numbers are in `load-test-postgres-2026-09-24.md`.

PostgreSQL 16.15 was a separate process on port 5433. Migrations ran on that database. `scripts/loadtest-postgres.js` used `DB_DRIVER=pg`. PGlite was not used.

That run lasted 8 seconds per scenario and did not include SOS. The current `backend/scripts/loadtest-postgres.js` adds an SOS burst scenario; no SOS load result is reported until a new run is completed.

This machine is not a cloud server. The historical numbers are from local PostgreSQL.
