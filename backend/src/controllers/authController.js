/**
 * کنترلر احراز هویت.
 * کنترلرها فقط ورودی را به سرویس می‌دهند و خروجی را به HTTP تبدیل می‌کنند.
 */
import authService from '../services/authService.js';
import otpService from '../services/otpService.js';
import { asyncHandler } from '../middleware/error.js';
import env from '../config/env.js';

function webClient(req) {
  return req.get('x-client-kind') === 'web';
}

function sendAuthResult(req, res, result, status = 200) {
  if (webClient(req)) {
    res.cookie('safestep_refresh', result.refreshToken, {
      httpOnly: true,
      secure: env.isProduction,
      sameSite: 'lax',
      path: '/api/v1/auth',
      maxAge: 30 * 24 * 60 * 60 * 1000,
    });
    const { refreshToken, ...publicResult } = result;
    res.status(status).json(publicResult);
    return;
  }
  res.status(status).json(result);
}

function refreshCookie(req) {
  const raw = req.headers.cookie ?? '';
  const item = raw.split(';').map((part) => part.trim()).find((part) => part.startsWith('safestep_refresh='));
  return item ? decodeURIComponent(item.slice('safestep_refresh='.length)) : null;
}

export const register = asyncHandler(async (req, res) => {
  const result = await authService.register(req.body, {
    userAgent: req.headers['user-agent'],
    req,
  });
  sendAuthResult(req, res, result, 201);
});

export const login = asyncHandler(async (req, res) => {
  const result = await authService.login(req.body, {
    userAgent: req.headers['user-agent'],
    req,
  });
  sendAuthResult(req, res, result);
});

export const refresh = asyncHandler(async (req, res) => {
  const result = await authService.refresh(req.body?.refreshToken ?? refreshCookie(req), {
    userAgent: req.headers['user-agent'],
  });
  sendAuthResult(req, res, result);
});

export const logout = asyncHandler(async (req, res) => {
  const result = await authService.logout(req.body?.refreshToken ?? refreshCookie(req));
  res.clearCookie('safestep_refresh', { httpOnly: true, secure: env.isProduction, sameSite: 'lax', path: '/api/v1/auth' });
  res.json(result);
});

export const logoutAll = asyncHandler(async (req, res) => {
  const result = await authService.logoutAll(req.user.id);
  res.json(result);
});

export const me = asyncHandler(async (req, res) => {
  const result = await authService.me(req.user.id);
  res.json(result);
});

export const requestOtp = asyncHandler(async (req, res) => {
  const result = await otpService.requestOtp(req.body, { ip: req.ip });
  res.json(result);
});

export const verifyOtp = asyncHandler(async (req, res) => {
  res.json(await otpService.verifyOtp(req.body));
});
