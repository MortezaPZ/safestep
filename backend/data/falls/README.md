# Fall feature datasets

Public labeled corpora (SisFall, MobiAct, UP-Fall) are **not** stored in this repository.

Convert SisFall raw `.txt` files with:

```
node backend/scripts/falls/convert_sisfall.js
```

Place files under `backend/data/falls/raw/SisFall/`. Output CSV columns: `label,f1..f14` using `backend/src/services/fallDetection/features.js`.

If no real CSV is present, `npm run train:fall` generates a physics-motivated **synthetic** set (header `# SYNTHETIC`) via `generate_synthetic.js`.
