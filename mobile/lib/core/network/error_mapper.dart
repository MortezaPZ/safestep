import 'dart:io';

import 'package:dio/dio.dart';

import '../utils/app_exception.dart';

/// تبدیل هر خطای شبکه به یک `AppException` با پیام فارسی.
///
/// ── قاعده‌ی این پروژه ───────────────────────────────────────────────────
/// هیچ پیام خامی از `dio` یا از بدنه‌ی پاسخ سرور، مستقیم به کاربر نمایش
/// داده نمی‌شود. دو دلیل:
///
/// ۱) «SocketException: Failed host lookup» برای کاربر بی‌معنا و ترسناک
///    است و هیچ نمی‌گوید که باید چه کار کند.
/// ۲) متن خطای سرور ممکن است جزئیات داخلی را لو بدهد.
///
/// استثنا: بک‌اند این پروژه عمداً پیام‌های فارسیِ آماده‌ی نمایش تولید
/// می‌کند (`error.message`). برای خطاهای ۴xx از همان استفاده می‌کنیم، چون
/// دقیق‌تر از هر پیام عمومی است — اما فقط وقتی که ساختار پاسخ دقیقاً همان
/// قراردادِ شناخته‌شده باشد.
class ErrorMapper {
  const ErrorMapper._();

  static AppException map(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;
    if (error is DioException) return _fromDio(error);
    if (error is SocketException) return AppException.network;
    return const AppException(
      message: 'خطای غیرمنتظره‌ای رخ داد. لطفاً دوباره تلاش کنید.',
      code: 'UNKNOWN',
    );
  }

  static AppException _fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppException.timeout;

      case DioExceptionType.connectionError:
        return AppException.network;

      case DioExceptionType.cancel:
        return const AppException(
          message: 'درخواست لغو شد.',
          code: 'CANCELLED',
          retryable: false,
        );

      case DioExceptionType.badCertificate:
        return const AppException(
          message: 'ارتباط امن با سرور برقرار نشد.',
          code: 'BAD_CERTIFICATE',
          kind: AppErrorKind.network,
        );

      case DioExceptionType.badResponse:
        return _fromResponse(error.response);

      case DioExceptionType.unknown:
        if (error.error is SocketException) return AppException.network;
        return const AppException(
          message: 'ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید.',
          code: 'UNKNOWN_NETWORK',
          kind: AppErrorKind.network,
        );
    }
  }

  static AppException _fromResponse(Response<dynamic>? response) {
    final int status = response?.statusCode ?? 0;
    final dynamic body = response?.data;

    // قرارداد خطای بک‌اند: { error: { code, message, details? } }
    String? serverMessage;
    String? serverCode;
    Map<String, String>? fieldErrors;

    if (body is Map && body['error'] is Map) {
      final Map<dynamic, dynamic> err = body['error'] as Map<dynamic, dynamic>;
      final Object? message = err['message'];
      final Object? code = err['code'];
      if (message is String && message.trim().isNotEmpty) serverMessage = message;
      if (code is String) serverCode = code;

      // خطاهای فیلد‌به‌فیلدِ zod: [{ field, message }, ...]
      final Object? details = err['details'];
      if (details is List) {
        final Map<String, String> map = <String, String>{};
        for (final Object? item in details) {
          if (item is Map && item['field'] is String && item['message'] is String) {
            map[item['field'] as String] = item['message'] as String;
          }
        }
        if (map.isNotEmpty) fieldErrors = map;
      }
    }

    switch (status) {
      case 400:
        return AppException(
          message: serverMessage ?? 'اطلاعات واردشده معتبر نیست.',
          code: serverCode ?? 'BAD_REQUEST',
          kind: AppErrorKind.validation,
          fieldErrors: fieldErrors,
          retryable: false,
        );

      case 401:
        return AppException(
          message: serverMessage ?? AppException.unauthorized.message,
          code: serverCode ?? 'UNAUTHORIZED',
          kind: AppErrorKind.auth,
          retryable: false,
        );

      case 403:
        return AppException(
          message: serverMessage ?? 'شما به این بخش دسترسی ندارید.',
          code: serverCode ?? 'FORBIDDEN',
          kind: AppErrorKind.forbidden,
          retryable: false,
        );

      case 404:
        return AppException(
          message: serverMessage ?? 'موردی که دنبالش بودید پیدا نشد.',
          code: serverCode ?? 'NOT_FOUND',
          retryable: false,
        );

      case 409:
        return AppException(
          message: serverMessage ?? 'این مورد از قبل وجود دارد.',
          code: serverCode ?? 'CONFLICT',
          retryable: false,
        );

      case 429:
        return AppException(
          message: serverMessage ??
              'تعداد تلاش‌ها بیش از حد مجاز است. کمی صبر کنید و دوباره تلاش کنید.',
          code: serverCode ?? 'TOO_MANY_REQUESTS',
          // قابل تلاش دوباره هست، ولی نه همین حالا
          retryable: false,
        );

      default:
        if (status >= 500) return AppException.server;
        return AppException(
          message: serverMessage ?? 'ارتباط با سرور با مشکل مواجه شد.',
          code: serverCode ?? 'HTTP_$status',
          kind: AppErrorKind.server,
        );
    }
  }
}
