/**
 * میان‌افزار احراز هویت و کنترل دسترسی سطح‌رکورد.
 */
import { verifyAccessToken } from '../utils/jwt.js';
import { unauthorized, forbidden } from '../utils/errors.js';
import * as guardianshipRepository from '../repositories/guardianshipRepository.js';
import adminRepository from '../repositories/adminRepository.js';
import { ROLES, USER_STATUS } from '../config/constants.js';
import env from '../config/env.js';

/**
 * حافظه‌ی نهانِ کوتاه‌مدتِ وضعیت حساب.
 *
 * چرا اصلاً وضعیت حساب در هر درخواست بررسی می‌شود:
 *   نقش و وضعیت داخل توکن access است و آن توکن ۱۵ دقیقه اعتبار دارد. یعنی
 *   اگر فقط به توکن اتکا کنیم، حسابی که ادمین همین الان معلق کرده تا ۱۵
 *   دقیقه به کار خود ادامه می‌دهد. برای «تعلیق» این رفتار پذیرفتنی نیست.
 *
 * چرا با حافظه‌ی نهان:
 *   یک کوئری به‌ازای هر درخواست، به تأخیر هر پاسخ اضافه می‌کند — همان عددی
 *   که این فاز قرار است اندازه بگیرد. با پنجره‌ی ۱۵ ثانیه، حداکثر تأخیرِ
 *   اثرگذاریِ تعلیق ۱۵ ثانیه است و بار دیتابیس ناچیز می‌ماند.
 */
const STATE_TTL_MS = 15_000;
const stateCache = new Map();

async function accountState(userId) {
  const cached = stateCache.get(userId);
  if (cached && Date.now() - cached.at < STATE_TTL_MS) return cached.value;

  const value = await adminRepository.accountState(userId);
  stateCache.set(userId, { value, at: Date.now() });

  // جلوگیری از رشد بی‌نهایت حافظه در سرورِ طولانی‌مدت
  if (stateCache.size > 5000) stateCache.clear();

  return value;
}

/** پاک کردن حافظه‌ی نهان یک کاربر — پس از تغییر نقش یا وضعیت صدا زده می‌شود. */
export function invalidateAccountState(userId) {
  if (userId) stateCache.delete(userId);
  else stateCache.clear();
}

/**
 * الزام ورود. توکن از هدر ‎Authorization: Bearer <token> خوانده می‌شود.
 * پس از اجرا، ‎req.user شامل ‎{ id, role }‎ خواهد بود.
 *
 * نقش از دیتابیس خوانده می‌شود، نه از توکن: توکنِ کاربری که تازه ادمین شده
 * هنوز نقش قدیمی را دارد، و مهم‌تر، توکنِ ادمینی که نقشش گرفته شده هنوز
 * `admin` می‌گوید.
 */
export async function requireAuth(req, _res, next) {
  try {
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');

    if (scheme !== 'Bearer' || !token) {
      throw unauthorized('برای این کار باید وارد حساب خود شوید.');
    }

    const payload = verifyAccessToken(token);
    const state = await accountState(payload.sub);

    if (!state) throw unauthorized('حساب کاربری یافت نشد.');

    if (state.status === USER_STATUS.SUSPENDED) {
      throw forbidden('حساب شما توسط مدیر سامانه معلق شده است. با پشتیبانی تماس بگیرید.');
    }

    if (state.status === USER_STATUS.DELETED) {
      throw unauthorized('این حساب دیگر فعال نیست.');
    }

    req.user = {
      id: state.id,
      role: state.role,
      verificationStatus: state.verification_status ?? 'unverified',
    };
    next();
  } catch (error) {
    next(error);
  }
}

/**
 * احراز هویت اختیاری — اگر توکن بود کاربر را می‌شناسد، اگر نبود رد نمی‌کند.
 * برای endpointهایی مثل ‎/health که پاسخشان بسته به ورود کامل‌تر می‌شود.
 */
export function optionalAuth(req, _res, next) {
  try {
    const header = req.headers.authorization ?? '';
    const [scheme, token] = header.split(' ');

    if (scheme === 'Bearer' && token) {
      const payload = verifyAccessToken(token);
      req.user = { id: payload.sub, role: payload.role };
    }
  } catch {
    // توکن نامعتبر در مسیر اختیاری، نادیده گرفته می‌شود
  }
  next();
}

/**
 * الزام داشتن یک سطح دسترسی مشخص روی کاربر هدف.
 *
 * شناسه‌ی کاربر هدف از پارامتر مسیر یا query خوانده می‌شود. اگر بیننده
 * خودِ کاربر هدف باشد، همیشه مجاز است.
 *
 * @param {string} permission سطح دسترسی لازم
 * @param {string} [paramName] نام پارامتر حاوی شناسه‌ی کاربر هدف
 */
export function requirePermission(permission, paramName = 'userId') {
  return async (req, _res, next) => {
    try {
      const subjectId = req.params[paramName] ?? req.query[paramName] ?? req.body?.[paramName];

      if (!subjectId) {
        throw forbidden('کاربر هدف مشخص نشده است.');
      }

      // دسترسی به داده‌ی خود، همیشه مجاز است
      if (subjectId === req.user.id) {
        req.subjectId = subjectId;
        return next();
      }

      const allowed = await guardianshipRepository.hasPermission(
        subjectId,
        req.user.id,
        permission,
      );

      if (!allowed) {
        throw forbidden('شما به داده‌های این کاربر دسترسی ندارید.');
      }

      req.subjectId = subjectId;
      return next();
    } catch (error) {
      return next(error);
    }
  };
}

/** الزام نقش مشخص (مثلاً فقط کاربر اصلی). */
export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) {
      return next(forbidden('این بخش برای نقش کاربری شما در دسترس نیست.'));
    }
    return next();
  };
}

/**
 * الزام نقش مدیر سامانه.
 *
 * پیام خطا عمداً «دسترسی ندارید» است و نه «این مسیر فقط برای ادمین است»:
 * وجود یا نبودِ پنل مدیریت، اطلاعاتی است که کاربر عادی لازم نیست بداند.
 */
export const requireAdmin = requireRole(ROLES.ADMIN);

/** تا مدارک تأیید نشده، قابلیت‌های مراقبتی قفل است. */
export function requireVerified(req, _res, next) {
  if (!req.user) return next(unauthorized());
  if (req.user.role === ROLES.ADMIN) return next();
  if (req.user.verificationStatus === 'verified') return next();
  return next(forbidden('پس از تأیید مدارک توسط مدیر سامانه می‌توانید از این قابلیت استفاده کنید.'));
}
