import { ALERT_TYPES, FALL_FEEDBACK, ROLES, WS_EVENTS, AUDIT_ACTIONS } from '../config/constants.js';
import * as fallEventRepository from '../repositories/fallEventRepository.js';
import * as userRepository from '../repositories/userRepository.js';
import * as guardianshipRepository from '../repositories/guardianshipRepository.js';
import { PERMISSIONS } from '../config/constants.js';
import { predict } from './fallDetection/classifier.js';
import { raiseAlert } from './alertService.js';
import hub from '../realtime/hub.js';
import auditService from './auditService.js';
import { badRequest, forbidden, notFound } from '../utils/errors.js';

export async function detect(user, body, { source = 'device' } = {}) {
  if (user.role !== ROLES.PRIMARY) {
    throw forbidden('فقط کاربر اصلی می‌تواند رویداد سقوط ارسال کند.');
  }

  if (body.clientEventId) {
    const existing = await fallEventRepository.findByClientEvent(user.id, body.clientEventId);
    if (existing) {
      const settings = await userRepository.getSettings(user.id);
      return {
        isFall: existing.classifiedAsFall,
        fallEventId: existing.id,
        countdownSec: settings?.fallCountdownSec ?? 30,
        duplicate: true,
      };
    }
  }

  const prediction = predict(body.features);
  const settings = await userRepository.getSettings(user.id);
  const enabled = settings?.fallDetectionEnabled !== false;
  const isFall = prediction.isFall && enabled;

  const row = await fallEventRepository.insert({
    userId: user.id,
    detectedAt: body.detectedAt ?? new Date(),
    modelName: prediction.modelName,
    modelVersion: prediction.modelVersion,
    confidence: prediction.confidence,
    features: body.features,
    lat: body.lat,
    lng: body.lng,
    detectionSource: source,
    svmMargin: prediction.votes.svm.margin,
    knnAgree: prediction.votes.knn.agreeRatio,
    classifiedAsFall: isFall,
    clientEventId: body.clientEventId,
  });

  await auditService.record({
    action: AUDIT_ACTIONS.FALL_DETECTED,
    actor: user,
    entityType: 'fall_event',
    entityId: row.id,
    metadata: { isFall, source },
  });

  if (isFall) {
    hub.emitToUser(user.id, WS_EVENTS.FALL_DETECTED, {
      fallEventId: row.id,
      countdownSec: settings?.fallCountdownSec ?? 30,
      confidence: prediction.confidence,
    });
  }

  return {
    isFall,
    fallEventId: row.id,
    countdownSec: settings?.fallCountdownSec ?? 30,
    confidence: prediction.confidence,
    votes: prediction.votes,
  };
}

async function raiseFromFall(row, feedback) {
  const result = await raiseAlert({
    userId: row.userId,
    type: ALERT_TYPES.FALL_DETECTED,
    location: { lat: row.lat, lng: row.lng },
    context: { confidence: row.confidence },
    metadata: {
      fallEventId: row.id,
      confidence: row.confidence,
      feedback,
    },
  });
  await fallEventRepository.linkAlert(row.id, result.alert.id);
  return result;
}

export async function submitFeedback(user, id, { feedback, respondedWithinSec }) {
  if (!Object.values(FALL_FEEDBACK).includes(feedback)) {
    throw badRequest('بازخورد نامعتبر است.');
  }
  const row = await fallEventRepository.findById(id);
  if (!row || row.userId !== user.id) throw notFound('رویداد سقوط یافت نشد.');

  if (row.userFeedback) {
    return { fallEvent: row, duplicate: true };
  }

  const updated = await fallEventRepository.applyFeedback(id, { feedback, respondedWithinSec });
  await auditService.record({
    action: AUDIT_ACTIONS.FALL_FEEDBACK,
    actor: user,
    entityType: 'fall_event',
    entityId: id,
    metadata: { feedback },
  });

  if (feedback === FALL_FEEDBACK.FALSE_ALARM) {
    hub.emitToUser(user.id, WS_EVENTS.FALL_RESOLVED, { fallEventId: id, feedback });
    return { fallEvent: updated };
  }

  await raiseFromFall(updated, feedback);
  hub.emitToUser(user.id, WS_EVENTS.FALL_RESOLVED, { fallEventId: id, feedback });
  return { fallEvent: { ...updated, alertRaised: true } };
}

export async function reportMissed(user, body = {}) {
  if (user.role !== ROLES.PRIMARY) {
    throw forbidden('فقط کاربر اصلی می‌تواند سقوط ازدست‌رفته را گزارش کند.');
  }
  const row = await fallEventRepository.insert({
    userId: user.id,
    detectedAt: body.detectedAt ?? new Date(),
    features: body.features ?? [],
    lat: body.lat,
    lng: body.lng,
    detectionSource: 'manual',
    classifiedAsFall: false,
    userFeedback: FALL_FEEDBACK.CONFIRMED,
    feedbackAt: new Date(),
    respondedWithinSec: 0,
  });
  return { fallEvent: row };
}

export async function listFalls(viewer, { userId, limit, before }) {
  const subjectId = userId ?? viewer.id;
  if (viewer.id !== subjectId) {
    const ok = await guardianshipRepository.hasPermission(
      subjectId,
      viewer.id,
      PERMISSIONS.EMERGENCY,
    );
    if (!ok) throw forbidden('برای فهرست سقوط به دسترسی اضطراری نیاز است.');
  } else if (viewer.role === ROLES.ADMIN && viewer.id === subjectId) {
    throw forbidden('ادمین به رویدادهای سقوط کاربران دسترسی ندارد.');
  }
  const items = await fallEventRepository.listForUsers([subjectId], { limit, before });
  return { falls: items };
}

export async function expireUnanswered(now = new Date()) {
  const due = await fallEventRepository.listExpiredPositives(now.toISOString());
  const raised = [];
  for (const row of due) {
    const updated = await fallEventRepository.applyFeedback(row.id, {
      feedback: FALL_FEEDBACK.NO_RESPONSE,
      respondedWithinSec: null,
    });
    if (!updated) continue;
    await raiseFromFall({ ...row, ...updated }, FALL_FEEDBACK.NO_RESPONSE);
    raised.push(row.id);
  }
  return { raised: raised.length };
}

export default { detect, submitFeedback, reportMissed, listFalls, expireUnanswered };
