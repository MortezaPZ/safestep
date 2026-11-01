import db from '../db/index.js';
import { encryptSensitiveValue, isEncryptedSensitiveValue } from '../utils/sensitiveData.js';

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

export default { encryptLegacySensitiveData };
