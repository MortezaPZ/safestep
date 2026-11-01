import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { describe, it, expect } from 'vitest';

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationPath = path.resolve(
  here,
  '../src/db/migrations/011_notification_claim_and_delivery_keys.sql',
);

describe('مهاجرت حذف ردیف‌های تکراری تحویل اعلان', () => {
  it('پیش از حذف، تلاش‌های قدیمی را آرشیو می‌کند و آخرین ردیف را نگه می‌دارد', async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        CREATE TABLE notification_outbox (id BIGSERIAL PRIMARY KEY);
        CREATE TABLE alert_deliveries (
          id BIGSERIAL PRIMARY KEY,
          alert_id UUID NOT NULL,
          recipient_user_id UUID NOT NULL,
          channel VARCHAR(16) NOT NULL,
          status VARCHAR(16) NOT NULL,
          latency_ms INTEGER,
          attempts INTEGER NOT NULL DEFAULT 1,
          error_code VARCHAR(64),
          delivered_at TIMESTAMPTZ,
          acknowledged_at TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        INSERT INTO alert_deliveries
          (alert_id, recipient_user_id, channel, status, attempts, created_at)
        VALUES
          ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'fcm', 'failed', 1, '2026-01-01T00:00:00Z'),
          ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'fcm', 'sent', 2, '2026-01-01T00:00:01Z');
      `);

      const sql = await fs.readFile(migrationPath, 'utf8');
      await db.exec(sql);

      const archived = await db.query(
        `SELECT original_id, original_row->>'status' AS status,
                (original_row->>'attempts')::int AS attempts
           FROM alert_delivery_dedup_archive`,
      );
      const retained = await db.query(
        `SELECT status, attempts FROM alert_deliveries`,
      );

      expect(archived.rows).toEqual([{ original_id: 1, status: 'failed', attempts: 1 }]);
      expect(retained.rows).toEqual([{ status: 'sent', attempts: 2 }]);
    } finally {
      await db.close();
    }
  });
});
