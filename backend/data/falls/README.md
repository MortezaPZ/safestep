# مجموعه‌داده‌های سقوط

فایل‌های خام مجموعه‌های عمومی در مخزن نگهداری نمی‌شوند. نسخهٔ قابل‌بازتولید
SisFall از mirror ثابت [Hugging Face](https://huggingface.co/datasets/Trupal7/Sisfall_Dataset/tree/f8a95e5c953169985dc9641e1a5772e6b7b47a83)
گرفته شده است. کارت mirror مجوز CC BY 4.0 را اعلام می‌کند؛ برای استناد، مقالهٔ
اصلی [SisFall: A Fall and Movement Dataset](https://doi.org/10.3390/s17010198)
را ذکر کنید.

## دریافت و آموزش SisFall

از ریشهٔ مخزن در PowerShell اجرا کنید. پیش از ادامه، مقدار `Hash` باید با مقدار
ثبت‌شده در گزارش آموزش برابر باشد:

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

اگر فایل دادهٔ مصنوعی موجود باشد، `npm run train:fall` همچنان فقط دادهٔ
synthetic تولید می‌کند و جای آموزش SisFall را نمی‌گیرد.
