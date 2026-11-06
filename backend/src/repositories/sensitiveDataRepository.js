import db from '../db/index.js';
import { decryptSensitiveValue, encryptSensitiveValue, isEncryptedSensitiveValue } from '../utils/sensitiveData.js';

/** Sample existing ciphertext before encrypting legacy values with this key. */
export async function assertSensitiveKeyReadable() {
  const { rows: columns } = await db.query(`SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name IN ('users', 'identity_documents')`);
  const available = new Set(columns.map((row) => `${row.table_name}.${row.column_name}`));
  // These identifiers are a fixed allowlist, never user input.
  for (const [table, column] of [
    ['users', 'health_condition'],
    ['identity_documents', 'image_url'],
    ['identity_documents', 'health_condition_encrypted'],
  ]) {
    if (!available.has(`${table}.${column}`)) continue;
    const { rows } = await db.query(`SELECT ${column} AS value FROM ${table}
      WHERE ${column} LIKE 'enc:v1:%' LIMIT 1`);
    if (!rows.length) continue;
    try {
      decryptSensitiveValue(rows[0].value);
    } catch {
      throw new Error('کلید رمزنگاری داده‌های حساس با نمونهٔ ذخیره‌شده سازگار نیست.');
    }
    return;
  }
}

/** Idempotently encrypt legacy plaintext values on startup after migrations. */
export async function encryptLegacySensitiveData() {
  const documents = await db.query('SELECT id, image_url FROM identity_documents');
  for (const row of documents.rows) {
    if (isEncryptedSensitiveValue(row.image_url)) continue;
    await db.query(
      'UPDATE identity_documents SET image_url = $2 WHERE id = $1',
      [row.id, encryptSensitiveValue(row.image_url)],
    );
  }

  const users = await db.query(
    'SELECT id, health_condition FROM users WHERE health_condition IS NOT NULL',
  );
  for (const row of users.rows) {
    if (isEncryptedSensitiveValue(row.health_condition)) continue;
    await db.query(
      'UPDATE users SET health_condition = $2 WHERE id = $1',
      [row.id, encryptSensitiveValue(row.health_condition)],
    );
  }
}

export default { assertSensitiveKeyReadable, encryptLegacySensitiveData };
