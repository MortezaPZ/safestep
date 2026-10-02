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
import notificationOutbox from '../services/notificationOutbox.js';
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

export const listIdentityDocuments = asyncHandler(async (req, res) => {
  const status = req.query.status === 'all' ? null : req.query.status;
  res.json(await adminService.listIdentityDocuments({ status, limit: req.query.limit, offset: req.query.offset }));
});

export const myIdentityDocuments = asyncHandler(async (req, res) => {
  res.json(await adminService.myIdentityDocuments(req.user.id));
});

export const submitIdentityDocument = asyncHandler(async (req, res) => {
  const { documentType, imageUrl, healthCondition, subjectUserId } = req.body;
  if (subjectUserId) {
    res.status(201).json(await adminService.submitIdentityDocumentForPrimary(
      actorOf(req), subjectUserId, documentType, imageUrl, healthCondition,
    ));
    return;
  }
  res.status(201).json(await adminService.submitIdentityDocument(
    req.user.id, documentType, imageUrl, healthCondition,
  ));
});

export const approveIdentityDocument = asyncHandler(async (req, res) => {
  res.json(await adminService.reviewIdentityDocument(
    req.params.id,
    'approved',
    { ...actorOf(req), healthCondition: req.body?.healthCondition },
  ));
});

export const mySupport = asyncHandler(async (req, res) => {
  res.json(await adminService.listMySupport(req.user.id));
});

export const postSupport = asyncHandler(async (req, res) => {
  res.status(201).json(await adminService.postSupportMessage(req.user.id, req.body.body));
});

export const supportInbox = asyncHandler(async (req, res) => {
  res.json(await adminService.listSupportInbox());
});

export const supportReply = asyncHandler(async (req, res) => {
  res.status(201).json(await adminService.replySupport(req.params.userId, req.body.body));
});

export const adminFalls = asyncHandler(async (_req, res) => {
  res.json(await adminService.listAdminFalls());
});

export const families = asyncHandler(async (_req, res) => {
  res.json(await adminService.listFamilies());
});

export const adminAlerts = asyncHandler(async (_req, res) => {
  res.json(await adminService.listAdminAlerts());
});

export const rejectIdentityDocument = asyncHandler(async (req, res) => {
  res.json(await adminService.reviewIdentityDocument(req.params.id, 'rejected', actorOf(req), req.body.reason));
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

export const listOutbox = asyncHandler(async (req, res) => {
  const { status, limit, offset } = req.query;
  res.json(await notificationOutbox.listOutbox({ status, limit, offset }));
});

export const retryOutbox = asyncHandler(async (req, res) => {
  res.json(await notificationOutbox.retryOutbox(req.params.id));
});

export default {
  overview,
  listUsers,
  getUser,
  listIdentityDocuments,
  myIdentityDocuments,
  submitIdentityDocument,
  approveIdentityDocument,
  mySupport,
  postSupport,
  supportInbox,
  supportReply,
  families,
  adminAlerts,
  adminFalls,
  rejectIdentityDocument,
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
  listOutbox,
  retryOutbox,
};
