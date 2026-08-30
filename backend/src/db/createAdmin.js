/**
 * ساخت یا ارتقای حساب مدیر سامانه.
 *
 * ── چرا ادمین از راه API ساخته نمی‌شود ──────────────────────────────────
 * هیچ endpointی برای «ثبت‌نام به‌عنوان ادمین» وجود ندارد و مسیر ثبت‌نام
 * عمومی فقط دو نقش `primary` و `guardian` را می‌پذیرد. اولین ادمین باید
 * توسط کسی ساخته شود که به خودِ سرور دسترسی دارد — یعنی از همین اسکریپت.
 * ادمین‌های بعدی را ادمین موجود از پنل می‌سازد.
 *
 * اجرا:
 *   npm run create:admin -- --phone 09121234567 --name "مدیر سامانه" --password "..."
 *
 * اگر رمز داده نشود، یک رمز تصادفی امن ساخته و یک بار چاپ می‌شود.
 * اگر شماره از قبل وجود داشته باشد، همان حساب به نقش ادمین ارتقا می‌یابد
 * (رمزش دست‌نخورده می‌ماند، مگر آنکه صریحاً رمز تازه داده شود).
 */
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import db from './index.js';
import { runMigrations } from './migrate.js';
import * as userRepository from '../repositories/userRepository.js';
import adminRepository from '../repositories/adminRepository.js';
import { normalizePhone } from '../services/authService.js';
import { hashPassword } from '../utils/crypto.js';
import { ROLES, USER_STATUS, AUDIT_ACTIONS } from '../config/constants.js';
import logRepository from './../repositories/logRepository.js';

/** تجزیه‌ی آرگومان‌های خط فرمان به شکل ‎--key value‎. */
function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

/**
 * تولید رمز تصادفی خوانا.
 * از الفبای بدون کاراکترهای مبهم (‎0/O‎ و ‎1/l‎) استفاده می‌شود، چون این رمز
 * قرار است از روی ترمینال خوانده و دستی تایپ شود.
 */
function generatePassword(length = 16) {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789@#%+=';
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += alphabet[crypto.randomInt(0, alphabet.length)];
  }
  return out;
}

export async function createAdmin({ phone, fullName, password }) {
  const normalized = normalizePhone(phone);
  const existing = await userRepository.findByPhone(normalized);

  // حساب موجود: فقط ارتقای نقش، بدون دست زدن به رمز مگر آنکه خواسته شده باشد
  if (existing) {
    const updated = await adminRepository.setUserRole(existing.id, ROLES.ADMIN);

    if (existing.status !== USER_STATUS.ACTIVE) {
      await adminRepository.setUserStatus(existing.id, USER_STATUS.ACTIVE);
    }

    if (password) {
      await userRepository.updatePassword(existing.id, await hashPassword(password));
    }

    await logRepository.insertAuditLog({
      actorUserId: existing.id,
      actorRole: ROLES.ADMIN,
      action: AUDIT_ACTIONS.USER_ROLE_CHANGE,
      entityType: 'user',
      entityId: existing.id,
      metadata: { from: existing.role, to: ROLES.ADMIN, via: 'cli' },
    });

    return { user: updated, created: false, password: password ?? null };
  }

  const finalPassword = password || generatePassword();

  const user = await userRepository.create({
    phone: normalized,
    passwordHash: await hashPassword(finalPassword),
    fullName: fullName || 'مدیر سامانه',
    role: ROLES.ADMIN,
    avatarColor: '#1F2937',
  });

  await logRepository.insertAuditLog({
    actorUserId: user.id,
    actorRole: ROLES.ADMIN,
    action: 'admin.bootstrap',
    entityType: 'user',
    entityId: user.id,
    metadata: { via: 'cli' },
  });

  return { user, created: true, password: password ? null : finalPassword };
}

/* ─────────────────────────── اجرای مستقیم ─────────────────────────── */

const isDirectRun =
  process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (isDirectRun) {
  const args = parseArgs(process.argv.slice(2));

  if (!args.phone) {
    process.stderr.write(
      '\n❌ شماره موبایل الزامی است.\n' +
        '   نمونه: npm run create:admin -- --phone 09121234567 --name "مدیر سامانه"\n\n',
    );
    process.exit(1);
  }

  if (args.password && String(args.password).length < 8) {
    process.stderr.write('\n❌ رمز عبور باید حداقل ۸ کاراکتر باشد.\n\n');
    process.exit(1);
  }

  try {
    await db.connect();
    await runMigrations();

    const result = await createAdmin({
      phone: String(args.phone),
      fullName: args.name ? String(args.name) : undefined,
      password: args.password ? String(args.password) : undefined,
    });

    const lines = [
      '',
      result.created ? '✅ حساب مدیر ساخته شد.' : '✅ حساب موجود به نقش مدیر ارتقا یافت.',
      '',
      `   نام   : ${result.user.fullName}`,
      `   شماره : ${result.user.phone}`,
      `   نقش   : ${result.user.role}`,
    ];

    if (result.password) {
      lines.push(
        '',
        `   رمز عبور : ${result.password}`,
        '   ⚠ این رمز فقط همین یک بار نمایش داده می‌شود. همین حالا ذخیره‌اش کنید.',
      );
    }

    lines.push('');
    process.stdout.write(`${lines.join('\n')}\n`);

    await db.close();
    process.exit(0);
  } catch (error) {
    process.stderr.write(`\n❌ خطا: ${error.message}\n\n`);
    await db.close().catch(() => {});
    process.exit(1);
  }
}

export default createAdmin;
