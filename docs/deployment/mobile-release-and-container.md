# آماده‌سازی خروجی و استقرار

## Docker

از ریشهٔ مخزن بسازید تا داشبورد وب هم در تصویر قرار بگیرد:

```sh
docker build -f backend/Dockerfile -t safestep .
docker run --rm -p 4080:4080 \
  -e DATABASE_URL='postgres://…' \
  -e JWT_ACCESS_SECRET='…' \
  -e JWT_REFRESH_SECRET='…' \
  -e INVITE_CODE_PEPPER='…' \
  -e IDENTITY_DATA_ENCRYPTION_KEY='…' \
  safestep
```

پورت سرویس و داشبورد `4080` است. `DEMO_MODE` در تصویر خاموش است و باید
برای اجرای تولیدی رازهای بالا و نشانی PostgreSQL با مقادیر واقعی تزریق شوند.

## Android

شناسهٔ پیش‌فرض برنامه `ir.hamghadam.safestep` است. اگر ناشر شناسهٔ دیگری
دارد، آن را با `-PappApplicationId=...` هنگام build تعیین کند.

برای امضای انتشار، فایل محلی `mobile/android/key.properties` را از روی
`mobile/android/key.properties.example` بسازید و به یک keystore اختصاصی
اشاره دهید. فایل کلید و گذرواژه را وارد Git نکنید. build انتشار بدون این
فایل امضای debug را به‌کار نمی‌برد و APK خروجی امضانشده خواهد بود.

```sh
cd mobile
flutter build apk --release
```

HTTP ساده مجاز است فقط در manifest گونهٔ debug برای اتصال به سرور محلی؛
در manifest اصلی و نسخهٔ release غیرفعال است.
