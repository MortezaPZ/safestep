# Fall model trained on SisFall

Both classes are recordings of real people. The falls are not simulated.

- Source: SisFall, Sucerquia and colleagues, Sensors 2017
- Fall files: 1798
- Activity-of-daily-living files: 2707
- Training windows: 7212
- Falls: 1798
- Activity of daily living: 5414
- Model: `src/services/fallDetection/model.json`
- Label: `sisfall-real`

The raw recordings are not in the source zip. The weights and five-fold metrics are in `model.json`.

The reproducible entry point is `npm run train:fall:sisfall`. It requires the raw files under `backend/data/falls/raw/SisFall` or a prepared 15-column feature CSV supplied through `SISFALL_FEATURE_CSV`. It refuses to fall back to synthetic data. On a successful run it updates the model, report, and the out-of-fold margin/agree-ratio sweep. Without the source data, the checked-in metrics cannot be regenerated from this package alone.
