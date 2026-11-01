import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import env from '../config/env.js';

const ENCRYPTED_PREFIX = 'enc:v1:';
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const encryptionKey = createHash('sha256')
  .update(env.auth.identityDataEncryptionKey, 'utf8')
  .digest();

export function isEncryptedSensitiveValue(value) {
  return typeof value === 'string' && value.startsWith(ENCRYPTED_PREFIX);
}

export function encryptSensitiveValue(value) {
  if (value === null || value === undefined || value === '') return value ?? null;
  const plaintext = String(value);
  if (isEncryptedSensitiveValue(plaintext)) return plaintext;
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return ENCRYPTED_PREFIX + [iv, tag, ciphertext].map((part) => part.toString('base64')).join(':');
}

export function decryptSensitiveValue(value) {
  if (value === null || value === undefined || value === '') return value ?? null;
  if (!isEncryptedSensitiveValue(value)) return value;
  const [ivText, tagText, ciphertextText] = value.slice(ENCRYPTED_PREFIX.length).split(':');
  if (!ivText || !tagText || ciphertextText === undefined) {
    throw new Error('Stored sensitive data has an invalid encrypted format.');
  }
  const decipher = createDecipheriv('aes-256-gcm', encryptionKey, Buffer.from(ivText, 'base64'));
  decipher.setAuthTag(Buffer.from(tagText, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextText, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

export function validateIdentityImageDataUrl(value) {
  if (typeof value !== 'string' || value.length > 7_000_000) {
    throw new Error('تصویر مدرک باید حداکثر ۵ مگابایت باشد.');
  }
  const match = value.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/]+={0,2})$/);
  if (!match) throw new Error('تصویر باید JPEG، PNG یا WebP و به‌صورت Base64 باشد.');
  const [, mimeType, encoded] = match;
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES || bytes.toString('base64') !== encoded) {
    throw new Error('حجم یا قالب Base64 تصویر معتبر نیست.');
  }

  const isJpeg = mimeType === 'image/jpeg' && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng = mimeType === 'image/png' &&
    bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const isWebp = mimeType === 'image/webp' &&
    bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP';
  if (!isJpeg && !isPng && !isWebp) {
    throw new Error('محتوای تصویر با نوع فایل اعلام‌شده سازگار نیست.');
  }
  return value;
}

export default {
  isEncryptedSensitiveValue,
  encryptSensitiveValue,
  decryptSensitiveValue,
  validateIdentityImageDataUrl,
};
