# PostgreSQL load test status

The run completed. Numbers are in `load-test-postgres-2026-09-24.md`.

PostgreSQL 16.15 was a separate process on port 5433. Migrations ran on that database. `scripts/loadtest-postgres.js` used `DB_DRIVER=pg`. PGlite was not used.

This machine is not a cloud server. The numbers are from local PostgreSQL.
