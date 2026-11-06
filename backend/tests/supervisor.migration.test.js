import fs from 'node:fs/promises';
import path from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { expect, it } from 'vitest';

it('archives changed supervisor flags and enforces one active main per primary', async () => {
  const db = new PGlite();
  try {
    await db.exec(`CREATE TABLE guardianships (
      id UUID PRIMARY KEY, primary_user_id UUID NOT NULL, status TEXT NOT NULL,
      is_main_supervisor BOOLEAN NOT NULL, created_at TIMESTAMPTZ NOT NULL
    );
    INSERT INTO guardianships VALUES
      ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000010','active',true,'2026-01-01'),
      ('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000010','active',true,'2026-02-01'),
      ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000010','revoked',true,'2026-03-01');`);
    for (const file of ['016_supervisor_flag_archive.sql', '017_supervisor_flag_cleanup.sql', '018_supervisor_unique.sql']) {
      await db.exec(await fs.readFile(path.resolve('src/db/migrations', file), 'utf8'));
    }
    const current = await db.query('SELECT id, is_main_supervisor FROM guardianships ORDER BY id');
    expect(current.rows.map((r) => r.is_main_supervisor)).toEqual([false, true, false]);
    const archived = await db.query('SELECT count(*)::int AS n FROM supervisor_flag_cleanup_archive');
    expect(archived.rows[0].n).toBe(2);
    await expect(db.query(`UPDATE guardianships SET is_main_supervisor = true
      WHERE id = '00000000-0000-4000-8000-000000000001'`)).rejects.toThrow();
  } finally { await db.close(); }
}, 30000);
