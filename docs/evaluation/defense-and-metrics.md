# Evaluation results and limits

## Fall classifier

The current `backend/src/services/fallDetection/model.json` is labeled `sisfall-public-simulated-falls`. It was retrained from 4,505 peak-centered windows converted from 4,505 recordings in a pinned public SisFall mirror. Validation groups all windows by subject and performs nested five-fold cross-validation:

| Model | Accuracy | Precision | Recall | F1 | TP | FP | TN | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| KNN | 0.9802 | 0.9760 | 0.9744 | 0.9752 | 1752 | 43 | 2664 | 46 |
| Linear SVM | 0.9678 | 0.9625 | 0.9566 | 0.9596 | 1720 | 67 | 2640 | 78 |
| Combined rule | 0.9789 | 0.9803 | 0.9666 | 0.9734 | 1738 | 35 | 2672 | 60 |

The model keeps all 4,505 training windows as KNN points. The final KNN uses k=9; the values selected independently within outer folds are recorded in the model. SisFall falls were safely simulated during collection. The dataset README says older participants performed ADLs only except SE06, a Judo expert who also simulated falls; these scores therefore do not establish fall performance for frail older adults, unexpected real-world falls, or a new device population. See `docs/phase3/04-sisfall-training-report.md` for the pinned mirror revision, archive hash, conversion details, and the archive's recording-count discrepancy.

`docs/evaluation/fall-rule-threshold-sweep.csv` contains 48 out-of-fold combinations of the combined rule's `margin` and `agreeRatio` thresholds. The individual scores are in `docs/evaluation/fall-out-of-fold-scores.csv`. The `sensitivity` column is serialized from out-of-fold recall. Treat this as a diagnostic sweep; select production thresholds only with a separate participant-level validation set.

`roc-sisfall-loo.csv` is a legacy artifact from the previous 1,443-prototype model. It is not held-out validation: its prototypes were selected using the full 7,212-window set. Do not cite its 0.9889 sensitivity as a generalization estimate or as a metric for the current model. Use only the subject-grouped CV results above.

## Synthetic ROC

`roc-threshold.csv` scores the synthetic `dataset.csv`, not SisFall. Its AUC is **1.000**: at threshold 0.05 it reports 2,000 true positives and zero false positives. This perfect separation describes the synthetic generator only and is not a model-accuracy result to use in the thesis.

## Geofence simulation

`geofence-false-alarms.csv` is a deterministic engine simulation of boundary noise and a constructed outward walk. Both columns use the same `debounce_count=1`. It is useful for comparing hysteresis settings, but it is not a measurement from a real walk.

## Position error

No real-walk GPS samples have been collected in this package. The former `position-error.csv` was a geometry self-check: it moved a point by an offset and measured the distance back to the same point. It contained no GPS fixes or walking data, so it has been removed from the evaluation artifacts. Collect 20–30 real-walk samples against a surveyed reference before reporting position error.

## SUS

No independent participant survey has been collected. The former twenty rows were a structured review of the demo by two roles, not responses from ten independent families. Those response rows have been removed from the evaluation artifacts. The mobile app now has a SUS form; collect real responses before reporting a SUS mean.

## Alert delivery to a phone

FCM is not active in the current build, and there is no measured phone-receipt latency. After FCM is configured, export the relevant `alert_deliveries` rows and measure delivery on real devices. Server-side request time is not phone-receipt time.

## PostgreSQL load test

`load-test-postgres-2026-11-01.md` is a historical local run against PostgreSQL 17.11 using previous telemetry settings. The newer `load-test-postgres-2026-11-06-isolated-pg17.md` ran six 60-second scenarios on an isolated PostgreSQL 17.11 instance, including an SOS burst; it reported zero HTTP errors and zero dropped telemetry at the sampled point. Neither run measures phone-delivery latency or cloud-vendor performance.
