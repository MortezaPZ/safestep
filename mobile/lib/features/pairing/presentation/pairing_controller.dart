import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../data/pairing_repository.dart';
import '../domain/pairing_models.dart';

/// وضعیت صفحه‌های اتصال.
@immutable
class PairingState {
  const PairingState({
    this.lists = const GuardianshipLists(),
    this.activeInvite,
    this.loading = false,
    this.busy = false,
    this.error,
  });

  final GuardianshipLists lists;

  /// کد دعوتِ تازه‌ساخته‌شده که همین حالا روی صفحه نمایش داده می‌شود.
  final InviteCode? activeInvite;

  /// بارگذاری اولیه‌ی فهرست
  final bool loading;

  /// عملیات کاربرآغازشده (ساخت کد، مصرف کد، قطع دسترسی)
  final bool busy;

  final AppException? error;

  PairingState copyWith({
    GuardianshipLists? lists,
    InviteCode? activeInvite,
    bool? loading,
    bool? busy,
    AppException? error,
    bool clearError = false,
    bool clearInvite = false,
  }) {
    return PairingState(
      lists: lists ?? this.lists,
      activeInvite: clearInvite ? null : (activeInvite ?? this.activeInvite),
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PairingController extends StateNotifier<PairingState> {
  PairingController(this._repository) : super(const PairingState());

  final PairingRepository _repository;

  /* ─────────────────────── فهرست ─────────────────────── */

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final GuardianshipLists lists = await _repository.list();
      state = state.copyWith(lists: lists, loading: false);
    } on AppException catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  /* ─────────────────────── ساخت کد دعوت ─────────────────────── */

  /// ساخت کد دعوت تازه.
  ///
  /// کد فقط در همین پاسخ برمی‌گردد و سرور آن را هش‌شده ذخیره می‌کند. اگر
  /// کاربر صفحه را ببندد، کد از دست می‌رود و باید تازه بسازد — این را در
  /// رابط کاربری صریح می‌گوییم تا کاربر غافلگیر نشود.
  Future<InviteCode?> createInvite(List<SharePermission> permissions) async {
    if (permissions.isEmpty) {
      state = state.copyWith(
        error: const AppException(
          message: 'حداقل یک سطح دسترسی باید انتخاب شود.',
          kind: AppErrorKind.validation,
          retryable: false,
        ),
      );
      return null;
    }

    state = state.copyWith(busy: true, clearError: true);

    try {
      final InviteCode invite = await _repository.createInvite(permissions);
      state = state.copyWith(busy: false, activeInvite: invite);
      return invite;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return null;
    }
  }

  void dismissInvite() => state = state.copyWith(clearInvite: true);

  /* ─────────────────────── مصرف کد دعوت ─────────────────────── */

  /// مصرف کد — سمت مراقب.
  ///
  /// ارقام فارسی پیش از ارسال به لاتین تبدیل می‌شوند؛ کاربری که کد را از
  /// پیامک کپی کرده ممکن است ارقام فارسی داشته باشد.
  Future<Guardianship?> redeem(String rawCode) async {
    final String code = Fa.toLatinDigits(rawCode).replaceAll(RegExp(r'\D'), '');

    if (code.length != 6) {
      state = state.copyWith(
        error: const AppException(
          message: 'کد دعوت باید ۶ رقم باشد.',
          kind: AppErrorKind.validation,
          retryable: false,
        ),
      );
      return null;
    }

    state = state.copyWith(busy: true, clearError: true);

    try {
      final Guardianship guardianship = await _repository.redeem(code);
      // فهرست تازه می‌شود تا فرد جدید بی‌درنگ در صفحه‌ی خانه دیده شود
      await load();
      state = state.copyWith(busy: false);
      return guardianship;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return null;
    }
  }

  /* ─────────────────────── تغییر و قطع دسترسی ─────────────────────── */

  Future<bool> updatePermissions(
    String guardianshipId,
    List<SharePermission> permissions,
  ) async {
    if (permissions.isEmpty) {
      state = state.copyWith(
        error: const AppException(
          message: 'حداقل یک سطح دسترسی باید بماند. برای قطع کامل، «قطع دسترسی» را بزنید.',
          kind: AppErrorKind.validation,
          retryable: false,
        ),
      );
      return false;
    }

    state = state.copyWith(busy: true, clearError: true);

    try {
      await _repository.updatePermissions(guardianshipId, permissions);
      await load();
      state = state.copyWith(busy: false);
      return true;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return false;
    }
  }

  Future<bool> revoke(String guardianshipId) async {
    state = state.copyWith(busy: true, clearError: true);

    try {
      await _repository.revoke(guardianshipId);
      await load();
      state = state.copyWith(busy: false);
      return true;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return false;
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final StateNotifierProvider<PairingController, PairingState> pairingControllerProvider =
    StateNotifierProvider<PairingController, PairingState>((ref) {
  return PairingController(ref.watch(pairingRepositoryProvider));
});
