# Evaluation results and limitations

## Alert delivery

Accuracy, on a leave-one-out pass over the stored SisFall prototypes, threshold `0.80`: sensitivity `0.9889`, false-positive rate `0.0009`. The PostgreSQL 16.15 load test reported no request-delivery errors.

Latency for storing a location, mean:

| Target rate | Requests | Mean ms | p50 | p95 | p99 |
| --- | --- | --- | --- | --- | --- |
| 50/s | 674 | 151.98 | 139 | 281 | 291 |
| 100/s | 372 | 540.81 | 543 | 700 | 732 |
| 200/s | 300 | 1264.92 | 1032 | 1979 | 2083 |

The "people I watch" list averaged `25.98` ms. Source: `docs/evaluation/load-test-postgres-2026-09-24.md`.

## ROC

`roc-sisfall-loo.csv` is leave-one-out over 1443 stored prototypes of the `sisfall-real` model, not a held-out test set. At threshold `0.80`: sensitivity `0.9889`, false-positive rate `0.0009` (356 true positives, 1 false positive, 4 false negatives).

`roc-threshold.csv` scores that same model on the synthetic `dataset.csv`. AUC is about `0.500`. The synthetic file is not the SisFall distribution and is not the number to cite as model accuracy.

## Geofence hysteresis

`geofence-false-alarms.csv`. A person on the edge of a 150 m circle, with about 15 m of noise:

| Hysteresis (m) | False exits | Real exits |
| --- | --- | --- |
| 0 | 100 | 1 |
| 10 | 39 | 1 |
| 25 | 0 | 1 |
| 40 | 0 | 1 |

## Position error

`position-error.csv`. The reference point is the demo home. `error_m` is the Haversine distance. A sample whose reported GPS accuracy is worse than 30 m is invalid under the proposal rule (`valid_sample = 0`).

## SisFall training

`model.json` is labeled `sisfall-real`, trained `2026-10-02T21:20:52.395Z`. The run read 1798 fall files and 2707 activity-of-daily-living files. The synthetic `dataset.csv` is not used at inference.

## Interpretation and scope

- GPS-reported accuracy is not the same thing as error against the reference point. A sample worse than 30 m of reported accuracy is invalid.
- The fall model is trained on SisFall. The synthetic `dataset.csv` is not used at inference, and its ROC is about chance.
- An automatic emergency call is not the SOS button. SOS is started by the person and is delivered according to the emergency permission.
- An admin does not receive live coordinates or route history.
- After sharing is turned off, the primary guardian loses the live feed. A limited guardian did not have the emergency path.
- The load test ran on PostgreSQL 16.15. There is no cloud-vendor latency number in the report.
