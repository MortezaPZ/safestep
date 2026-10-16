# Training report on recorded activity, 2026-09-24

## Source

Public UCI set: "Dataset for ADL Recognition with Wrist-worn Accelerometer" (16 volunteers, 983 files, 14 activities).

https://archive.ics.uci.edu/dataset/283

The source describes wrist-accelerometer recordings of real people. The raw files and prepared feature CSV are not included in this source package.

## Class mix

| Class | Windows | Source |
| --- | --- | --- |
| 0, activity of daily living (negative) | 4000 | Real, UCI |
| 1, fall (positive) | 2000 | Simulated. A usable public corpus of real human falls was not available |

## Windows by activity

| Activity | Files | Windows |
| --- | --- | --- |
| Brush_teeth | 12 | 603 |
| Climb_stairs | 102 | 684 |
| Climb_stairs_MODEL | 20 | 80 |
| Comb_hair | 31 | 445 |
| Descend_stairs | 42 | 256 |
| Drink_glass | 100 | 745 |
| Drink_glass_MODEL | 20 | 80 |
| Eat_meat | 5 | 644 |
| Eat_soup | 3 | 134 |
| Getup_bed | 101 | 806 |
| Getup_bed_MODEL | 20 | 80 |
| Liedown_bed | 28 | 196 |
| Pour_water | 100 | 720 |
| Pour_water_MODEL | 20 | 120 |
| Sitdown_chair | 97 | 374 |
| Sitdown_chair_MODEL | 20 | 40 |
| Standup_chair | 98 | 375 |
| Standup_chair_MODEL | 20 | 40 |
| Use_telephone | 13 | 295 |
| Walk | 100 | 1770 |
| Walk_MODEL | 20 | 40 |

## Why the positive class is simulated

A public dataset of real human falls with a license that allows a university project was not available. The previous model's main weakness was marking real daily activity as a fall. This set replaces that negative class with real recordings.

## 5-fold validation

| Model | Accuracy | Precision | Recall | F1 |
| --- | --- | --- | --- | --- |
| KNN | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| SVM | 0.9993 | 1.0000 | 0.9980 | 0.9990 |

The perfect KNN score is on this mixed set (real activity, simulated falls). It is not a claim about SisFall. The later SisFall model is the one used for the defense numbers.

## Model file

The reproducible entry point is `npm run train:fall:real`. It expects a prepared 15-column feature CSV (label plus fourteen features), supplied with `REAL_FALL_FEATURE_CSV`. It writes a separate `model-real.json` and will not overwrite the deployed SisFall model. The raw source files are not included, so the prior report figures cannot be regenerated from this package alone.

```bash
npm run train:fall:real
```
