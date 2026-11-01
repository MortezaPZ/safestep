# PostgreSQL load test status

The fresh run completed. Numbers are in `load-test-postgres-2026-11-01.md`.

It used an isolated local PostgreSQL 17.11 process on port 5440. Migrations ran on that database. `scripts/loadtest-postgres.js` used `DB_DRIVER=pg`. PGlite was not used.

Each of six scenarios lasted 60 seconds and used 50 independent user tokens/connections, including the POST `/sos` burst. All six HTTP scenarios reported zero request errors. Telemetry-buffer overflow warnings appeared during the run; the final buffer had 1,950 queued records and 16,936 dropped records. This run used the previous 5-second/200-row batch settings. The service now flushes every second in batches of 500, and a unit test verifies all three queues drain without drops at that configured rate. The new settings still need a PostgreSQL rerun; the prior result does not establish current telemetry capture or phone-delivery latency.

This was a local PostgreSQL run, not a cloud-server measurement.
