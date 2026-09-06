import jwt from 'jsonwebtoken';
import env from '../config/env.js';
import { generateInviteCode, hashInviteCode, timingSafeEqual } from '../utils/crypto.js';
import { normalizePhone } from '../utils/phone.js';
import * as otpRepository from '../repositories/otpRepository.js';
import * as userRepository from '../repositories/userRepository.js';
import * as smsAdapter from './smsAdapter.js';
import { badRequest, tooManyRequests, unauthorized } from '../utils/errors.js';

const PURPOSES = new Set(['register', 'login', 'change_phone']);
const ISSUER = 'safestep';

export async function requestOtp({ phone, purpose }, { ip } = {}) {
  if (!PURPOSES.has(purpose)) throw badRequest('هدف کد تأیید نامعتبر است.');
  const normalized = normalizePhone(phone);
  const recent = await otpRepository.countRecent(normalized, new Date(Date.now() - 10 * 60_000));
  if (recent >= 3) {
    throw tooManyRequests('تعداد درخواست کد برای این شماره زیاد است. ده دقیقه دیگر تلاش کنید.');
  }

  const code = generateInviteCode();
  const expiresAt = new Date(Date.now() + 3 * 60_000);
  await otpRepository.insert({
    phone: normalized,
    codeHash: hashInviteCode(code),
    purpose,
    expiresAt,
  });
  await smsAdapter.send({ phone: normalized, code, purpose });
  return {
    ok: true,
    expiresInSec: 180,
    smsDriver: env.sms.driver,
    hint: env.sms.driver === 'console'
      ? 'کد در لاگ سرور چاپ شد (حالت توسعه)'
      : null,
    ip: ip ?? null,
  };
}

export async function verifyOtp({ phone, code, purpose }) {
  if (!PURPOSES.has(purpose)) throw badRequest('هدف کد تأیید نامعتبر است.');
  const normalized = normalizePhone(phone);
  const row = await otpRepository.findLatestOpen(normalized, purpose);
  if (!row) throw unauthorized('کد تأیید یافت نشد. دوباره درخواست کنید.');
  if (new Date(row.expires_at).getTime() < Date.now()) {
    throw unauthorized('کد تأیید منقضی شده است.');
  }
  if (row.attempts >= 5) {
    throw tooManyRequests('تعداد تلاش برای این کد تمام شده است.');
  }

  const expected = hashInviteCode(String(code).padStart(6, '0'));
  if (!timingSafeEqual(expected, row.code_hash)) {
    await otpRepository.bumpAttempts(row.id);
    throw unauthorized('کد تأیید نادرست است.');
  }

  await otpRepository.consume(row.id);
  const verificationToken = jwt.sign(
    { typ: 'phone_verify', phone: normalized, purpose },
    env.auth.accessSecret,
    { expiresIn: '10m', issuer: ISSUER },
  );
  return { verificationToken, expiresInSec: 600 };
}

export function readVerificationToken(token, { phone, purpose }) {
  if (!token) return null;
  try {
    const payload = jwt.verify(token, env.auth.accessSecret, { issuer: ISSUER });
    if (payload.typ !== 'phone_verify') return null;
    if (purpose && payload.purpose !== purpose) return null;
    if (phone && payload.phone !== phone) return null;
    return payload;
  } catch {
    return null;
  }
}

export default { requestOtp, verifyOtp, readVerificationToken };
