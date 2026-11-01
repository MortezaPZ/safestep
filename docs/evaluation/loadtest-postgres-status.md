# PostgreSQL load test status

The fresh run completed. Numbers are in `load-test-postgres-2026-11-01.md`.

It used an isolated local PostgreSQL 17.11 process on port 5440. Migrations ran on that database. `scripts/loadtest-postgres.js` used `DB_DRIVER=pg`. PGlite was not used.

Each of six scenarios lasted 60 seconds and used 50 independent user tokens/connections, including the POST `/sos` burst. All six HTTP scenarios reported zero request errors. Telemetry-buffer overflow warnings appeared during the run; the final buffer had 1,950 queued records and 16,936 dropped records. The result does not establish complete telemetry capture or phone-delivery latency.

This was a local PostgreSQL run, not a cloud-server measurement.
