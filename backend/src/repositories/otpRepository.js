import db from '../db/index.js';

export async function insert({ phone, codeHash, purpose, expiresAt }) {
  const { rows } = await db.query(
    `INSERT INTO phone_otps (phone, code_hash, purpose, expires_at)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [phone, codeHash, purpose, expiresAt],
  );
  return rows[0];
}

export async function findLatestOpen(phone, purpose) {
  const { rows } = await db.query(
    `SELECT * FROM phone_otps
     WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL
     ORDER BY created_at DESC
     LIMIT 1`,
    [phone, purpose],
  );
  return rows[0] ?? null;
}

export async function bumpAttempts(id) {
  await db.query('UPDATE phone_otps SET attempts = attempts + 1 WHERE id = $1', [id]);
}

export async function consume(id) {
  await db.query('UPDATE phone_otps SET consumed_at = now() WHERE id = $1', [id]);
}

export async function countRecent(phone, since) {
  const { rows } = await db.query(
    `SELECT COUNT(*)::int AS n FROM phone_otps
     WHERE phone = $1 AND created_at >= $2`,
    [phone, since],
  );
  return rows[0]?.n ?? 0;
}
