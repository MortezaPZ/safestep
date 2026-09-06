# تشخیص سقوط (فاز سوم)

استخراج ویژگی روی گوشی انجام می‌شود و رده‌بندی روی سرور، تا بدون انتشار اپ بتوان مدل را عوض کرد و همان بردار در `fall_events.features` بماند.

پنجره: ۳ ثانیه، ۵۰ هرتز، ۱۵۰ نمونه. `SMV` بر حسب g.

| # | ویژگی |
| --- | --- |
| 1–5 | smvMax, smvMin, smvMean, smvStd, smvRange |
| 6 | impactIndexRatio |
| 7–9 | preImpactMean, postImpactMean, postImpactStd |
| 10 | freeFallMinBeforePeak |
| 11–12 | gyroMax, gyroMeanPost |
| 13 | orientationChangeDeg |
| 14 | zeroCrossingsSmv |

پیش‌غربال روی دستگاه: `smvMax ≥ 2.3` و (`freeFallMinBeforePeak ≤ 0.6` یا `orientationChangeDeg ≥ 45`).

تصمیم نهایی: سقوط اگر SVM و KNN هر دو موافق باشند، یا حاشیهٔ SVM بزرگ‌تر از `1.0`، یا نسبت توافق KNN حداقل `0.8`.

تهدید اعتبار: آموزش پیش‌فرض روی **داده‌ی مصنوعی** است؛ تعمیم به سقوط واقعی نیازمند مجموعهٔ برچسب‌خوردهٔ میدانی است.
