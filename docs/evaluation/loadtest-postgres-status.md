# PostgreSQL load test status

The fresh run completed. Numbers are in `load-test-postgres-2026-11-01.md`.

It used an isolated local PostgreSQL 17.11 process on port 5433. Migrations ran on that database. `scripts/loadtest-postgres.js` used `DB_DRIVER=pg`. PGlite was not used.

Each scenario lasted 8 seconds and included POST `/sos` with 10 connections. All six HTTP scenarios reported zero request errors. Telemetry-buffer overflow warnings appeared during the run, so the result does not establish complete telemetry capture or phone-delivery latency.

This was a local PostgreSQL run, not a cloud-server measurement.
