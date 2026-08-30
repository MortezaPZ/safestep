/**
 * سرو کردن مستند API.
 *
 * دو مسیر ارائه می‌شود:
 *
 *   GET /api/docs             رابط تعاملی Swagger UI
 *   GET /api/docs/openapi.yaml  خودِ فایل مشخصات، برای ابزارهای بیرونی
 *
 * ── چرا Swagger UI محلی سرو می‌شود و نه از CDN ──────────────────────────
 * دو دلیل: مستند باید روی سروری که به اینترنت آزاد دسترسی ندارد هم باز
 * شود، و سیاست امنیتی محتوای این پروژه (CSP) بارگذاری اسکریپت از دامنه‌ی
 * دیگر را نمی‌پذیرد. بسته‌ی `swagger-ui-express` فایل‌های استاتیک را از
 * داخل `node_modules` سرو می‌کند.
 *
 * ── چرا این روتر پیش از helmet نصب می‌شود ───────────────────────────────
 * Swagger UI برای راه‌اندازی خودش به استایل و اسکریپت درون‌خطی نیاز دارد.
 * CSP سخت‌گیرانه‌ی اپ آن را می‌شکند و صفحه‌ی سفید می‌دهد. به‌جای سست کردن
 * CSP برای کل برنامه، این روتر **پیش از** helmet نصب می‌شود تا فقط همین
 * مسیر از آن مستثنا باشد. هیچ داده‌ی کاربری از این مسیر عبور نمی‌کند؛
 * محتوایش ایستا و عمومی است.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { Router } from 'express';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yaml';

import logger from '../utils/logger.js';

const log = logger.child({ module: 'docs' });

const SPEC_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  'openapi.yaml',
);

/**
 * ساخت روتر مستندات.
 *
 * اگر خواندن یا تجزیه‌ی فایل شکست بخورد، سرور همچنان بالا می‌آید و فقط
 * مستندات در دسترس نخواهد بود — یک خطای نگارشی در YAML نباید کل سرویس را
 * زمین بزند.
 */
export function createDocsRouter() {
  const router = Router();

  let spec = null;
  let rawSpec = '';

  try {
    rawSpec = fs.readFileSync(SPEC_PATH, 'utf8');
    spec = YAML.parse(rawSpec);
  } catch (error) {
    log.error('خواندن فایل مشخصات API شکست خورد', { error: error.message });
  }

  if (!spec) {
    router.get('/', (_req, res) => {
      res.status(503).json({
        error: {
          code: 'DOCS_UNAVAILABLE',
          message: 'مستندات API در دسترس نیست. فایل openapi.yaml را بررسی کنید.',
        },
      });
    });
    return router;
  }

  // فایل خام، برای ابزارهایی مثل Postman یا تولیدکننده‌های کد کلاینت
  router.get('/openapi.yaml', (_req, res) => {
    res.type('text/yaml; charset=utf-8').send(rawSpec);
  });

  router.get('/openapi.json', (_req, res) => {
    res.json(spec);
  });

  router.use(
    '/',
    swaggerUi.serve,
    swaggerUi.setup(spec, {
      customSiteTitle: 'هم‌قدم — مستند API',
      swaggerOptions: {
        // مسیرها بر اساس تگ مرتب می‌مانند (ترتیبی که در فایل تعریف شده)
        docExpansion: 'none',
        defaultModelsExpandDepth: 1,
        persistAuthorization: true,
        tryItOutEnabled: true,
      },
      // متن فارسی داخل Swagger UI باید راست‌به‌چپ خوانده شود
      customCss: `
        .swagger-ui .info .description,
        .swagger-ui .opblock-description-wrapper p,
        .swagger-ui .opblock-external-docs-wrapper,
        .swagger-ui .markdown p,
        .swagger-ui table.model tbody tr td:last-child { direction: rtl; text-align: right; }
        .swagger-ui .topbar { display: none; }
      `,
    }),
  );

  const pathCount = Object.keys(spec.paths ?? {}).length;
  log.info('مستندات API آماده شد', { paths: pathCount });

  return router;
}

export default createDocsRouter;
