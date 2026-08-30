import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_config.dart';
import '../storage/token_store.dart';
import '../utils/app_exception.dart';
import 'api_endpoints.dart';
import 'error_mapper.dart';

/// کلاینت HTTP اپ.
///
/// ── مسئله‌ی اصلی: توکن ۱۵ دقیقه‌ای ───────────────────────────────────────
/// توکن دسترسی هر ۱۵ دقیقه منقضی می‌شود. اگر هر صفحه خودش این را مدیریت
/// کند، دو اتفاق می‌افتد: کد تکراری در همه‌جا، و صفحه‌هایی که فراموش
/// کرده‌اند و کاربر را بی‌دلیل بیرون می‌اندازند.
///
/// اینجا در یک نقطه حل شده است: با هر ۴۰۱، توکن تازه گرفته می‌شود و همان
/// درخواست دوباره فرستاده می‌شود. کاربر هیچ‌وقت متوجه نمی‌شود.
///
/// ── و مسئله‌ی ظریف‌ترش: تازه‌سازی هم‌زمان ────────────────────────────────
/// وقتی اپ باز می‌شود، معمولاً چند درخواست هم‌زمان می‌روند (وضعیت، فهرست
/// افراد، هشدارها). اگر توکن منقضی باشد، هر سه ۴۰۱ می‌گیرند و هر سه
/// تازه‌سازی را شروع می‌کنند. چون بک‌اند توکن refresh را **می‌چرخاند** —
/// یعنی با اولین استفاده، توکن قبلی باطل می‌شود — دومی و سومی شکست
/// می‌خورند و کاربر بیرون انداخته می‌شود.
///
/// راه‌حل: تازه‌سازی تک‌مسیره. اولین درخواستی که ۴۰۱ می‌گیرد تازه‌سازی را
/// شروع می‌کند و بقیه روی همان `Completer` منتظر می‌مانند.
class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    required this.onSessionExpired,
    Dio? dio,
  })  : _tokenStore = tokenStore,
        _dio = dio ?? Dio() {
    _configure();
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  /// وقتی تازه‌سازی هم شکست بخورد، یعنی نشست واقعاً تمام است.
  /// این callback به کنترلر احراز هویت می‌گوید کاربر را به صفحه‌ی ورود ببرد.
  final void Function() onSessionExpired;

  static const Uuid _uuid = Uuid();

  /// تازه‌سازی در حال انجام — بقیه‌ی درخواست‌ها روی همین منتظر می‌مانند.
  Completer<bool>? _refreshing;

  Dio get raw => _dio;

  void _configure() {
    _dio.options = BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // خودمان وضعیت را بررسی می‌کنیم تا بدنه‌ی خطای سرور در دسترس بماند
      validateStatus: (int? status) => status != null && status < 500,
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          // بدنه‌ی درخواست لاگ نمی‌شود: شامل رمز عبور و مختصات است
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          error: true,
          logPrint: (Object? object) => debugPrint('[api] $object'),
        ),
      );
    }
  }

  /* ═══════════════════════ میان‌افزارها ═══════════════════════ */

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // شناسه‌ی درخواست: با همین می‌توان یک عملیات را از اپ تا جدول
    // request_logs سرور دنبال کرد
    options.headers['X-Request-Id'] = _uuid.v4();
    options.headers[AppConfig.clientHeader] = _clientKind;

    // مسیرهای عمومی نباید هدر Authorization بگیرند
    if (!_isPublic(options.path)) {
      final String? token = await _tokenStore.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }

  void _onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final int status = response.statusCode ?? 0;

    // چون validateStatus را باز گذاشته‌ایم، خطاهای ۴xx به‌صورت پاسخ موفق
    // می‌رسند و باید دستی به خطا تبدیل شوند
    if (status >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: response.requestOptions,
          response: response,
        ),
      );
      return;
    }

    handler.next(response);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final bool isAuthError = error.response?.statusCode == 401;
    final bool alreadyRetried = error.requestOptions.extra['retried'] == true;
    final bool isRefreshCall = error.requestOptions.path == ApiEndpoints.refresh;

    // ۴۰۱ روی خودِ مسیر تازه‌سازی یعنی توکن refresh هم باطل است — پایان نشست
    if (!isAuthError || alreadyRetried || isRefreshCall || _isPublic(error.requestOptions.path)) {
      handler.next(error);
      return;
    }

    final bool refreshed = await _refreshToken();

    if (!refreshed) {
      onSessionExpired();
      handler.next(error);
      return;
    }

    try {
      final RequestOptions options = error.requestOptions;
      options.extra['retried'] = true;

      final String? token = await _tokenStore.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';

      final Response<dynamic> response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } catch (_) {
      handler.next(error);
    }
  }

  /* ═══════════════════════ تازه‌سازی توکن ═══════════════════════ */

  /// تازه‌سازی تک‌مسیره.
  ///
  /// اگر تازه‌سازی در حال انجام باشد، همین‌جا منتظر نتیجه‌ی همان می‌مانیم و
  /// درخواست دومی به سرور نمی‌فرستیم — دقیقاً همان چیزی که چرخش توکن را
  /// نمی‌شکند.
  Future<bool> _refreshToken() async {
    final Completer<bool>? inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final Completer<bool> completer = Completer<bool>();
    _refreshing = completer;

    try {
      final String? refreshToken = await _tokenStore.readRefreshToken();

      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      // از یک Dio تمیز استفاده می‌شود تا این درخواست دوباره وارد همین
      // میان‌افزار نشود و حلقه‌ی بی‌پایان نسازد
      final Dio plain = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          contentType: Headers.jsonContentType,
        ),
      );

      final Response<dynamic> response = await plain.post<dynamic>(
        ApiEndpoints.refresh,
        data: <String, dynamic>{'refreshToken': refreshToken},
      );

      final dynamic data = response.data;
      if (data is! Map) {
        completer.complete(false);
        return false;
      }

      final Object? access = data['accessToken'];
      final Object? newRefresh = data['refreshToken'];

      if (access is! String || access.isEmpty) {
        completer.complete(false);
        return false;
      }

      if (newRefresh is String && newRefresh.isNotEmpty) {
        await _tokenStore.saveTokens(accessToken: access, refreshToken: newRefresh);
      } else {
        await _tokenStore.saveAccessToken(access);
      }

      completer.complete(true);
      return true;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshing = null;
    }
  }

  /* ═══════════════════════ درخواست‌ها ═══════════════════════ */

  /// اجرای یک درخواست و تبدیل هر خطا به `AppException`.
  ///
  /// همه‌ی لایه‌های داده از این عبور می‌کنند، پس هیچ‌جای بالاتر لازم نیست
  /// `DioException` را بشناسد.
  Future<T> request<T>(
    Future<Response<dynamic>> Function(Dio dio) call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final Response<dynamic> response = await call(_dio);
      return parse(response.data);
    } catch (error, stackTrace) {
      throw ErrorMapper.map(error, stackTrace);
    }
  }

  Future<T> get<T>(
    String path,
    T Function(dynamic data) parse, {
    Map<String, dynamic>? query,
  }) {
    return request<T>(
      (Dio dio) => dio.get<dynamic>(path, queryParameters: query),
      parse,
    );
  }

  Future<T> post<T>(
    String path,
    T Function(dynamic data) parse, {
    Object? body,
    Duration? timeout,
  }) {
    return request<T>(
      (Dio dio) => dio.post<dynamic>(
        path,
        data: body,
        options: timeout == null
            ? null
            : Options(sendTimeout: timeout, receiveTimeout: timeout),
      ),
      parse,
    );
  }

  Future<T> patch<T>(String path, T Function(dynamic data) parse, {Object? body}) {
    return request<T>((Dio dio) => dio.patch<dynamic>(path, data: body), parse);
  }

  Future<T> put<T>(String path, T Function(dynamic data) parse, {Object? body}) {
    return request<T>((Dio dio) => dio.put<dynamic>(path, data: body), parse);
  }

  Future<T> delete<T>(
    String path,
    T Function(dynamic data) parse, {
    Map<String, dynamic>? query,
  }) {
    return request<T>(
      (Dio dio) => dio.delete<dynamic>(path, queryParameters: query),
      parse,
    );
  }

  /* ═══════════════════════ کمکی ═══════════════════════ */

  /// مسیرهایی که بدون توکن صدا زده می‌شوند.
  static bool _isPublic(String path) {
    return path == ApiEndpoints.login ||
        path == ApiEndpoints.register ||
        path == ApiEndpoints.refresh;
  }

  static String get _clientKind {
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'flutter-ios';
    return 'flutter-android';
  }
}

/* ═══════════════════════════ Providerها ═══════════════════════════ */

/// وقتی نشست واقعاً تمام شود، این پرچم `true` می‌شود.
///
/// کنترلر احراز هویت به آن گوش می‌دهد و کاربر را بیرون می‌برد. این واسطه
/// لازم است چون `ApiClient` نمی‌تواند مستقیم به کنترلر وابسته باشد —
/// کنترلر خودش به `ApiClient` وابسته است و حلقه می‌شد.
final StateProvider<int> sessionExpiredSignalProvider = StateProvider<int>((ref) => 0);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStore: ref.watch(tokenStoreProvider),
    onSessionExpired: () {
      // شمارنده زیاد می‌شود تا هر بار یک رویداد تازه دیده شود
      ref.read(sessionExpiredSignalProvider.notifier).state++;
    },
  );
});

/// نگه‌داشتن ارجاع به `AppException` در امضای عمومی این فایل، تا مصرف‌کننده
/// بداند چه نوع خطایی انتظار دارد.
typedef ApiFailure = AppException;
