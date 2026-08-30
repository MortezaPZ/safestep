/**
 * کنترلرهای پنل مدیریت.
 *
 * مثل بقیه‌ی کنترلرها کوتاه‌اند: استخراج ورودی، صدا زدن سرویس، برگرداندن
 * پاسخ. تمام بررسی‌های مجاز بودن در سرویس و در میان‌افزار `requireRole`
 * انجام می‌شود، نه اینجا.
 *
 * شیء `req` به سرویس پاس داده می‌شود چون لاگ حسابرسی به شناسه‌ی درخواست و
 * هشِ IP نیاز دارد — نه به بدنه‌ی درخواست.
 */
import adminService from '../services/adminService.js';
import { asyncHandler } from '../middleware/error.js';

const actorOf = (req) => ({ id: req.user.id, role: req.user.role });

export const overview = asyncHandler(async (_req, res) => {
  res.json(await adminService.overview());
});

/* ─────────────────────────── کاربران ─────────────────────────── */

export const listUsers = asyncHandler(async (req, res) => {
  const { search, role, status, limit, offset } = req.query;
  res.json(await adminService.listUsers({ search, role, status, limit, offset }));
});

export const getUser = asyncHandler(async (req, res) => {
  res.json(await adminService.getUser(req.params.id));
});

export const suspendUser = asyncHandler(async (req, res) => {
  res.json(await adminService.suspendUser(req.params.id, req.body.reason, actorOf(req), req));
});

export const activateUser = asyncHandler(async (req, res) => {
  res.json(await adminService.activateUser(req.params.id, actorOf(req), req));
});

export const deleteUser = asyncHandler(async (req, res) => {
  res.json(await adminService.deleteUser(req.params.id, actorOf(req), req));
});

export const changeRole = asyncHandler(async (req, res) => {
  res.json(await adminService.changeRole(req.params.id, req.body.role, actorOf(req), req));
});

/* ─────────────────────────── دستگاه‌ها ─────────────────────────── */

export const listDevices = asyncHandler(async (req, res) => {
  const { userId, platform, includeRevoked, limit, offset } = req.query;
  res.json(await adminService.listDevices({ userId, platform, includeRevoked, limit, offset }));
});

export const revokeDevice = asyncHandler(async (req, res) => {
  res.json(await adminService.revokeDevice(req.params.id, actorOf(req), req));
});

/* ─────────────────────────── لاگ‌ها ─────────────────────────── */

export const requestLogs = asyncHandler(async (req, res) => {
  const { from, to, route, minStatus, userId, limit, offset } = req.query;
  res.json(await adminService.requestLogs({ from, to, route, minStatus, userId, limit, offset }));
});

export const auditLogs = asyncHandler(async (req, res) => {
  const { from, to, action, actorUserId, limit, offset } = req.query;
  res.json(await adminService.auditLogs({ from, to, action, actorUserId, limit, offset }));
});

export const purgeLogs = asyncHandler(async (req, res) => {
  res.json(await adminService.purgeLogs(req.body.olderThanDays, actorOf(req), req));
});

/* ─────────────────────────── سنجه‌ها ─────────────────────────── */

export const metrics = asyncHandler(async (req, res) => {
  res.json(await adminService.metrics({ from: req.query.from, to: req.query.to }));
});

export default {
  overview,
  listUsers,
  getUser,
  suspendUser,
  activateUser,
  deleteUser,
  changeRole,
  listDevices,
  revokeDevice,
  requestLogs,
  auditLogs,
  purgeLogs,
  metrics,
};
