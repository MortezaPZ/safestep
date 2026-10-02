# ─────────────────────────────────────────────────────────────
#  SafeStep / هم‌قدم — استقرار واقعی روی PostgreSQL شبکه‌ای
#  این فقط تنظیمات و اسکریپت است؛ خود دیپلوی با اعتبارنامهٔ کارفرما
#  اجرا می‌شود و چیزی جعل نمی‌شود.
# ─────────────────────────────────────────────────────────────
#
# هدف: نشان دادن اینکه چه چیزی برای اجرای واقعی کم است، بدون اینکه
# سرویس فرضی یا خروجی جعلی ساخته شود.
#
# پیش‌نیازها (هیچ‌کدام در مخزن نیستند و نباشند):
#   ۱. یک سرور PostgreSQL در دسترس — یا ابری (Supabase, Neon, RDS,
#      Aiven) یا روی VPS خودتان.
#   ۲. Node 20+ روی سرور اپ.
#   ۳. متغیرهای محیطی واقعی (فایل .env — هرگز در مخزن commit نمی‌شود).
#
# ── گام ۱: ساخت دیتابیس ──────────────────────────────────────
#
# روی سرور PostgreSQL:
#
#   CREATE ROLE safestep WITH LOGIN PASSWORD 'یک-رمز-تصادفی-بلند';
#   CREATE DATABASE safestep OWNER safestep;
#   GRANT ALL PRIVILEGES ON DATABASE safestep TO safestep;
#
# اگر PostgreSQL روی همان ماشین است و از پیکربندی پیش‌فرض استفاده
# می‌کنید، مطمئن شوید pg_hba.conf اجازهٔ اتصال از طرف اپ را می‌دهد.
#
# ── گام ۲: فایل .env ─────────────────────────────────────────
#
#   cp backend/.env.example backend/.env
#
# سپس این مقادیر را با مقادیر واقعی پر کنید:
#
#   NODE_ENV=production
#   PORT=4080
#   DB_DRIVER=pg
#   DATABASE_URL=postgres://safestep:<رمز>@<هاست>:5432/safestep
#
#   # این سه تا حتماً باید تصادفی و بلند باشند؛ در غیر این صورت سرور
#   # بالا نمی‌آید (assertProductionSecrets آن را متوقف می‌کند):
#   node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
#   JWT_ACCESS_SECRET=<خروجی بالا>
#   JWT_REFRESH_SECRET=<یک خروجی دیگر>
#   INVITE_CODE_PEPPER=<یک خروجی دیگر>
#
#   DEMO_MODE=false          # شبیه‌ساز موقعیت را در تولید خاموش کن
#   WEB_ROOT=/app/web        # مسیر پوشهٔ وب‌اپ روی سرور
#
# ── گام ۳: مهاجرت و دادهٔ اولیه ─────────────────────────────
#
#   cd backend
#   npm ci --omit=dev
#   npm run migrate           # همهٔ migrationها از 001 تا 008 اعمال می‌شود
#   npm run create:admin      # اولین حساب مدیر را می‌سازد
#   npm run seed              # اختیاری — حساب‌های دمو
#
# ── گام ۴: اجرا ─────────────────────────────────────────────
#
#   npm start                 # پورت ۴۰۸۰ یا PORT
#
# یا با یک مدیر پردازه (پیشنهاد می‌شود):
#
#   npm install -g pm2
#   pm2 start src/server.js --name safestep-backend
#   pm2 save
#   pm2 startup               # اجرای خودکار پس از ری‌استارت
#
# ── گام ۵: بررسی سلامت ──────────────────────────────────────
#
#   curl http://localhost:4080/health
#
# پاسخ باید «driver»: «pg» را نشان دهد — نه «pglite». اگر pglite است،
# یعنی DATABASE_URL درست تنظیم نشده و دیتابیس روی WASM درون‌پردازه‌ای
# اجرا می‌شود که برای تولید مناسب نیست.
#
# ── گام ۶: تست بار روی همین دیتابیس واقعی ──────────────────
#
#   DATABASE_URL=postgres://safestep:<رمز>@<هاست>:5432/safestep \
#     LOADTEST_DURATION=15 npm run loadtest:postgres
#
# این دستور اگر DATABASE_URL به Postgres اشاره نکند صریحاً رد می‌شود
# (کد خروج ۴) و هرگز PGlite را جایگزین نمی‌کند.
#
# ── چه چیزی برای اجرای واقعی کم است ──────────────────────────
#
# این مخزن یک پروژهٔ کامل است، ولی برای استقرار واقعی این موارد باید
# از بیرون تأمین شوند. هیچ‌کدام را جعل نمی‌کنیم:
#
#   • یک هاست/سرور. هیچ IP، دامنه یا آدرس موجودی در پروژه نیست.
#   • یک سرور PostgreSQL واقعی. هیچ DATABASE_URL واقعی در پروژه
#     نیست (و نباید باشد — رازها در مخزن جایی ندارند).
#   • اعتبارنامهٔ Firebase برای نوتیفیکیشن فشار واقعی. مسیر فایل حساب
#     سرویس در FCM_SERVICE_ACCOUNT_PATH تعریف شده ولی خالی است؛ بدون
#     آن، نوتیفیکیشن روی مسیر درون‌برنامه‌ای + WebSocket می‌ماند.
#   • گواهی TLS. خود اپ HTTP است؛ لایهٔ TLS باید توسط یک reverse proxy
#     (nginx, Caddy) یا سرویس میزبانی اضافه شود.
#   • فایل .env واقعی. فقط .env.example در مخزن است.
#
# تنظیمات Reverse proxy نمونه (nginx، فقط مرجع — باید روی سرور خودتان
# نصب و پیکربندی شود):
#
#   server {
#     listen 443 ssl http2;
#     server_name <دامنه>;
#
#     location / {
#       proxy_pass http://127.0.0.1:4080;
#       proxy_set_header Host $host;
#       proxy_set_header X-Real-IP $remote_addr;
#       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#       proxy_set_header X-Forwarded-Proto $scheme;
#     }
#
#     # WebSocket برای موقعیت زنده
#     location /socket.io/ {
#       proxy_pass http://127.0.0.1:4080;
#       proxy_http_version 1.1;
#       proxy_set_header Upgrade $http_upgrade;
#       proxy_set_header Connection "upgrade";
#     }
#   }
#
# Docker: backend/Dockerfile وجود دارد و برای Postgres شبکه‌ای کار
# می‌کند، ولی هیچ docker-compose.yml در مخزن نیست — چون نمی‌توانیم
# رمز دیتابیس یا نام هاست واقعی را بدانیم. وقتی سرور دیتابیس
# انتخاب شد، این فایل را کنار پروژه بسازید:
#
#   # docker-compose.yml (نمونه — مقادیر را پر کنید)
#   services:
#     app:
#       build: ./backend
#       ports:
#         - "4080:4080"
#       environment:
#         NODE_ENV: production
#         PORT: 4080
#         DB_DRIVER: pg
#         DATABASE_URL: postgres://safestep:***@db:5432/safestep
#         JWT_ACCESS_SECRET: ${JWT_ACCESS_SECRET}
#         JWT_REFRESH_SECRET: ${JWT_REFRESH_SECRET}
#         INVITE_CODE_PEPPER: ${INVITE_CODE_PEPPER}
#         DEMO_MODE: "false"
#       depends_on:
#         db:
#           condition: service_healthy
#     db:
#       image: postgres:16-alpine
#       environment:
#         POSTGRES_USER: safestep
#         POSTGRES_PASSWORD: ***
#         POSTGRES_DB: safestep
#       volumes:
#         - pgdata:/var/lib/postgresql/data
#       healthcheck:
#         test: ["CMD-SHELL", "pg_isready -U safestep -d safestep"]
#         interval: 5s
#         retries: 10
#   volumes:
#     pgdata:
