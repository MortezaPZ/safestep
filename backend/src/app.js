/**
 * ساخت اپلیکیشن Express.
 *
 * از server.js جدا نگه داشته شده تا تست‌های یکپارچه بتوانند بدون باز کردن
 * پورت شبکه، اپ را بالا بیاورند و روی آن درخواست بزنند.
 */
import path from 'node:path';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';

import env from './config/env.js';
import apiRoutes from './routes/index.js';
import { notFoundHandler, errorHandler } from './middleware/error.js';
import requestLog from './middleware/requestLog.js';
import { createDocsRouter } from './docs/index.js';
import telemetryService from './services/telemetryService.js';
import db from './db/index.js';
import notificationAdapter from './services/notificationAdapter.js';
import smsAdapter from './services/smsAdapter.js';
import hub from './realtime/hub.js';
import logger from './utils/logger.js';
import { isValidTileCoord, fetchTilePng } from './services/tileProxy.js';

const log = logger.child({ module: 'app' });

/**
 * مسیر پوشه‌ی وب‌اپ که همین سرور سرو می‌کند.
 * قابل بازنویسی با WEB_ROOT است، چون در کانتینر ساختار پوشه با
 * اجرای محلی فرق دارد و مسیر نسبی به backend همیشه درست نیست.
 */
const WEB_ROOT = env.webRoot;

export function createApp() {
  const app = express();

  // پشت پراکسی (مثلاً در Docker یا سرویس میزبانی)، IP واقعی کلاینت
  // از هدر X-Forwarded-For خوانده شود تا محدودسازی نرخ درست کار کند
  app.set('trust proxy', 1);
  app.disable('x-powered-by');

  /* ─────────────────────── مستندات API ─────────────────────── */

  // پیش از helmet نصب می‌شود: Swagger UI به اسکریپت و استایل درون‌خطی نیاز
  // دارد و CSP سخت‌گیرانه‌ی اپ آن را می‌شکند. به‌جای سست کردن CSP برای کل
  // برنامه، فقط همین مسیرِ ایستا و عمومی از آن مستثنا می‌شود.
  app.use('/api/docs', createDocsRouter());

  app.use(
    helmet({
      // وب‌اپ از همین مبدأ سرو می‌شود و به نقشه‌ی OpenStreetMap نیاز دارد
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          // هر دو صورت لازم است: دامنه‌ی اصلی و زیردامنه‌ها.
          // الگوی ‎*.tile.openstreetmap.org خودِ ‎tile.openstreetmap.org را پوشش نمی‌دهد.
          imgSrc: ["'self'", 'data:'],
          connectSrc: ["'self'", 'ws:', 'wss:'],
          fontSrc: ["'self'", 'data:'],
        },
      },
      crossOriginEmbedderPolicy: false,
    }),
  );

  app.use(
    cors({
      origin(origin, callback) {
        // درخواست بدون Origin (اپ موبایل، curl) مجاز است
        if (!origin || env.corsOrigins.includes(origin)) return callback(null, true);
        return callback(new Error('این مبدأ اجازه‌ی دسترسی ندارد.'));
      },
      credentials: true,
    }),
  );

  // مدارک می‌توانند به‌صورت data URL تصویر ارسال شوند؛ سقف با اعتبارسنجی
  // endpoint مدارک هم‌راستا است تا تصویر قبل از رسیدن به route قطع نشود.
  app.use(express.json({ limit: '8mb' }));
  app.use(express.urlencoded({ extended: false, limit: '8mb' }));

  // پس از تجزیه‌ی بدنه و پیش از مسیریابی: شناسه‌ی درخواست ساخته می‌شود و
  // زمان‌سنجی آغاز می‌گردد. خودِ ثبت، پس از ارسال کامل پاسخ انجام می‌شود.
  app.use(requestLog);

  /* ─────────────────────────── سلامت سرویس ─────────────────────────── */

  app.get('/health', async (_req, res) => {
    try {
      const database = await db.healthCheck();
      res.json({
        ok: true,
        service: 'safestep-backend',
        version: '1.0.0',
        env: env.nodeEnv,
        uptimeSec: Math.floor(process.uptime()),
        database,
        notifications: notificationAdapter.status(),
        sms: smsAdapter.status(),
        telemetry: telemetryService.status(),
        realtime: { connectedUsers: hub.connectedUserCount() },
        docs: '/api/docs',
        demoMode: env.demo.enabled,
      });
    } catch (error) {
      res.status(503).json({
        ok: false,
        error: { code: 'DB_UNAVAILABLE', message: 'اتصال به دیتابیس برقرار نیست.' },
        detail: env.isProduction ? undefined : error.message,
      });
    }
  });

  app.get('/tiles/:z/:x/:y.png', async (req, res, next) => {
    const { z, x, y } = req.params;
    if (!isValidTileCoord(z, x, y)) {
      return res.status(400).type('text').send('invalid tile');
    }
    try {
      const png = await fetchTilePng(z, x, y);
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Cache-Control', 'public, max-age=86400');
      return res.send(png);
    } catch (error) {
      if (error.status === 502 || error.message === 'tile upstream failed') {
        return res.status(502).type('text').send('tile unavailable');
      }
      return next(error);
    }
  });

  /* ─────────────────────────── API ─────────────────────────── */

  app.use('/api/v1', apiRoutes);

  /* ─────────────────────── وب‌اپ داشبورد خانواده ─────────────────────── */

  app.use(
    express.static(WEB_ROOT, {
      index: 'index.html',
      maxAge: env.isProduction ? '1h' : 0,
      extensions: ['html'],
    }),
  );

  // هر مسیر غیر API که فایل ایستا نبود، به وب‌اپ سپرده می‌شود (مسیریابی سمت کلاینت)
  app.get(/^\/(?!api\/).*/, (req, res, next) => {
    if (req.method !== 'GET') return next();
    return res.sendFile(path.join(WEB_ROOT, 'index.html'), (error) => {
      if (error) next();
    });
  });

  app.use(notFoundHandler);
  app.use(errorHandler);

  log.debug('اپلیکیشن Express ساخته شد', { webRoot: WEB_ROOT });

  return app;
}

export default createApp;
