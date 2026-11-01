# Evaluation results and limits

## Fall classifier

The current `backend/src/services/fallDetection/model.json` is labeled `sisfall-real` and records five-fold validation metrics. These are the SisFall figures to use when describing the current model:

| Model | Accuracy | Precision | Recall | F1 | TP | FP | TN | FN |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| KNN, k=5 | 0.9951 | 0.9867 | 0.9939 | 0.9903 | 1787 | 24 | 5390 | 11 |
| Linear SVM | 0.9813 | 0.9776 | 0.9466 | 0.9619 | 1702 | 39 | 5375 | 96 |

The model metadata reports 7,212 SisFall windows: 1,798 fall windows and 5,414 activity windows. The raw SisFall recordings are not included in this source package.

`backend/scripts/falls/train_sisfall.js` includes a stratified five-fold out-of-fold sweep over the combined rule's SVM margin and KNN agree-ratio thresholds. No new sweep table is included here because neither the raw recordings nor a prepared feature CSV is bundled. Set `SISFALL_FEATURE_CSV` to a prepared 15-column CSV and run `npm run train:fall:sisfall` to regenerate it; that run will also retrain and replace the deployed model.

`roc-sisfall-loo.csv` is not held-out validation. Its leave-one-out loop uses 1,443 prototypes selected from the full 7,212-window set, so each held-out prototype has already participated in the full-data selection. Do not cite its 0.9889 sensitivity as a generalization estimate; use the five-fold metrics stored in `model.json`.

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

`load-test-postgres-2026-11-01.md` is a fresh local run against PostgreSQL 17.11. Each scenario lasted 8 seconds and included an SOS burst. All HTTP scenarios reported zero request errors. The run emitted telemetry-buffer overflow warnings, so its HTTP latency and error figures do not establish complete telemetry capture or phone-delivery latency. `load-test-postgres-2026-09-24.md` remains the historical run without SOS. Both runs used local PostgreSQL; neither is a cloud-vendor latency measurement.
