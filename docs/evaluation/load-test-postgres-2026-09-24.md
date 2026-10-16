# PostgreSQL load test, 2026-09-24

Produced against real PostgreSQL 16.15 (official binaries, separate process, port 5433). PGlite was not used.

This is the historical run. It lasted 8 seconds per scenario and did not include an SOS burst. The current load-test script has an SOS scenario, but this report contains no SOS result.

Database: PostgreSQL 16.15, `max_connections` 100. Each scenario ran for 8 seconds. Driver: `pg`. Errors: 0.

| Scenario | Requests | Mean ms | p50 | p95 | p99 | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| POST /locations/ping (target 50/s, 13 connections) | 674 | 151.98 | 139 | 281 | 291 | 0 |
| POST /locations/ping (target 100/s, 25 connections) | 372 | 540.81 | 543 | 700 | 732 | 0 |
| POST /locations/ping (target 200/s, 50 connections) | 300 | 1264.92 | 1032 | 1979 | 2083 | 0 |
| GET /locations/watching | 6064 | 25.98 | 24 | 35 | 43 | 0 |
| GET /locations/history | 600 | 288.84 | 279 | 384 | 385 | 0 |

## Database connection snapshot after the ping scenarios

| When | Total | Active | Idle |
| --- | --- | --- | --- |
| Before | 2 | 1 | 1 |
| After ping scenarios | 10 | 5 | 5 |

This run is on a local computer, not a cloud server.
