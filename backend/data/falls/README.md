# مجموعه‌داده‌های سقوط

فایل‌های خام مجموعه‌های عمومی در مخزن نگهداری نمی‌شوند. نسخهٔ قابل‌بازتولید
SisFall از mirror ثابت [Hugging Face](https://huggingface.co/datasets/Trupal7/Sisfall_Dataset/tree/f8a95e5c953169985dc9641e1a5772e6b7b47a83)
گرفته شده است. کارت mirror مجوز CC BY 4.0 را اعلام می‌کند؛ برای استناد، مقالهٔ
اصلی [SisFall: A Fall and Movement Dataset](https://doi.org/10.3390/s17010198)
را ذکر کنید.

## دریافت و آموزش SisFall

از ریشهٔ مخزن در PowerShell اجرا کنید. پیش از ادامه، مقدار `Hash` باید با مقدار
زیر برابر باشد: `7f0dd1583e39fee0f402a6855976eb12517f7eaecdacce871d5b3421793ad665`.

```powershell
$archive = Join-Path $env:TEMP 'SisFall_dataset.zip'
$staging = Join-Path $env:TEMP 'sisfall-extracted'
$raw = 'backend/data/falls/raw/SisFall'
Invoke-WebRequest -Uri 'https://huggingface.co/datasets/Trupal7/Sisfall_Dataset/resolve/f8a95e5c953169985dc9641e1a5772e6b7b47a83/SisFall_dataset.zip' -OutFile $archive
Get-FileHash -LiteralPath $archive -Algorithm SHA256
Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
New-Item -ItemType Directory -Force -Path $raw | Out-Null
Get-ChildItem -LiteralPath (Join-Path $staging 'SisFall_dataset') -Directory |
  Where-Object { $_.Name -match '^(SA|SE)\d+$' } |
  Copy-Item -Destination $raw -Recurse -Force
npm --prefix backend run train:fall:sisfall
```

مبدل به‌صورت بازگشتی فایل‌های ضبط را می‌خواند. CSV ویژگی‌ها ۱۷ ستون دارد:
`subject_id,recording_id,label,f1..f14`. اگر CSV گروه‌بندی‌شدهٔ دیگری را با
`SISFALL_FEATURE_CSV` بدهید، اسکریپت وجود شناسهٔ فرد و ضبط را بررسی می‌کند، اما
منشأ یا hash آن CSV را تأیید نمی‌کند.

در مسیر پیش‌فرض آموزش، ضبط خام هر بار با مبدل جاری به یک فایل موقت تبدیل
می‌شود؛ `dataset.csv` موجود به‌طور تصادفی بازنویسی یا به‌جای دادهٔ بازتولیدشده
مصرف نمی‌شود. برای فعالیت روزمره و سقوط به‌یکسان یک پنجره حول بزرگ‌ترین
اندازهٔ بردار شتاب انتخاب می‌شود؛ نزدیک ابتدا یا انتهای ضبط، پنجره در مرز
فایل محدود می‌شود. هیچ فعالیت روزمره‌ای بر اساس پیش‌غربال حذف نمی‌شود.
اگر ضبط‌های خام در جای دیگری نگهداری می‌شوند، می‌توان مسیر پوشهٔ آن‌ها را با
متغیر `SISFALL_RAW_DIR` داد؛ مسئولیت تأیید منشأ و هش همچنان با اجراکننده است.

برای ژیروسکوپ، قرارداد تبدیل مستند مجموعه با بازهٔ ±۲۰۰۰ درجه بر ثانیه و
تفکیک ۱۶ بیت از `4000 / 65536` درجه بر ثانیه به ازای هر واحد خام استفاده
می‌کند (معادل ۱۶٫۳۸۴ واحد در هر درجه بر ثانیه). ضریب ۱۴٫۳۷۵ حساسیت ذکرشده
برای خود حسگر ITG-3200 است و با قرارداد تمام‌بازهٔ فوق یکسان نیست؛ از این رو
برای بازتولید مشخصات مجموعه، قرارداد مجموعه انتخاب شده است. اعداد مدل قبلی
با این پیش‌پردازش قابل تعمیم به مدل بازآموزی‌نشده نیستند؛ پس از تهیهٔ دادهٔ
خام، مدل و CSV امتیازهای بیرونی و جاروب باید از همان اجرای مشترک تولید شوند.

آرشیو در commit ثابت `f8a95e5c953169985dc9641e1a5772e6b7b47a83`، طبق کارت
mirror، شامل ۴٬۵۰۵ فایل ضبط قابل‌شناسایی است: ۱٬۷۹۸ سقوط شبیه‌سازی‌شده و
۲٬۷۰۷ فعالیت روزمره. `Readme.txt` خود آرشیو ۴٬۵۱۰ فایل را ادعا می‌کند؛ این
اختلاف را به‌عنوان محدودیت منشأ نگه دارید و تعداد قابل‌خواندن را از خروجی
مبدل گزارش کنید. پنج نام `D17_SE15_R01..R05.txt` در پوشهٔ `SA15` هستند؛
مبدل شناسهٔ پوشه را مرجع می‌گیرد و آزمون رگرسیون آن در
`backend/tests/fall.training.test.js` است.

طبق README مجموعه، سالمندان فقط فعالیت‌های روزمره را انجام داده‌اند، به‌جز
SE06 که متخصص جودو بوده و سقوط‌ها را هم شبیه‌سازی کرده است. پس اعتبارسنجی
گروه‌بندی‌شده روی این داده، عملکرد سقوط برای سالمندان ناتوان یا کاربران
واقعی را اثبات نمی‌کند.

`npm run train:fall` مدل عمومی را در `backend/data/falls/model-generic.json`
می‌نویسد و مدل فعال `src/services/fallDetection/model.json` را جایگزین نمی‌کند.
اگر dataset موجود نباشد این مسیر دادهٔ مصنوعی می‌سازد؛ جای آموزش SisFall را
نمی‌گیرد.
