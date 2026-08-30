import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/app_exception.dart';
import '../../tracking/presentation/tracking_controller.dart';
import '../data/sos_repository.dart';

/// وضعیت دکمه‌ی اضطراری.
enum SosPhase {
  /// آماده
  idle,

  /// شمارش معکوس پیش از ارسال — کاربر می‌تواند لغو کند
  countdown,

  /// در حال گرفتن موقعیت و ارسال
  sending,

  /// ارسال شد
  sent,

  /// ارسال ناموفق
  failed,
}

@immutable
class SosState {
  const SosState({
    this.phase = SosPhase.idle,
    this.contacts = const <String>[],
    this.result,
    this.error,
  });

  final SosPhase phase;

  /// کسانی که هشدار به آن‌ها می‌رسد
  final List<String> contacts;

  final SosResult? result;
  final AppException? error;

  bool get hasContacts => contacts.isNotEmpty;

  SosState copyWith({
    SosPhase? phase,
    List<String>? contacts,
    SosResult? result,
    AppException? error,
    bool clearError = false,
  }) {
    return SosState(
      phase: phase ?? this.phase,
      contacts: contacts ?? this.contacts,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// کنترلر هشدار اضطراری.
///
/// ── ترتیب کارها در لحظه‌ی اضطرار ────────────────────────────────────────
/// ۱) موقعیت لحظه‌ای با مهلت **۶ ثانیه** خواسته می‌شود
/// ۲) اگر نرسید، آخرین موقعیت شناخته‌شده
/// ۳) اگر آن هم نبود، درخواست **بدون مختصات** فرستاده می‌شود
///
/// مرحله‌ی سوم مهم‌ترین است: هشدارِ بی‌مختصات از هشدارِ نفرستاده بی‌نهایت
/// بهتر است. مراقب دست‌کم می‌فهمد که کمک لازم است و می‌تواند تماس بگیرد.
class SosController extends StateNotifier<SosState> {
  SosController(this._ref) : super(const SosState());

  final Ref _ref;

  SosRepository get _repository => _ref.read(sosRepositoryProvider);

  /// خواندن فهرست مخاطبان اضطراری.
  ///
  /// پیش از نمایش دکمه صدا زده می‌شود تا اگر کسی ثبت نشده، کاربر **قبل از**
  /// وضعیت اضطراری بفهمد.
  Future<void> loadContacts() async {
    try {
      final List<String> contacts = await _repository.emergencyContacts();
      state = state.copyWith(contacts: contacts);
    } catch (_) {
      // شکست خواندن مخاطبان نباید دکمه را از کار بیندازد
    }
  }

  /// شروع شمارش معکوس.
  ///
  /// ── چرا شمارش معکوس، و چرا فقط سه ثانیه ─────────────────────────────
  /// دکمه در جیب یا با لمس تصادفی فشرده می‌شود. بدون فرصت لغو، هر بار یک
  /// آژیر کاذب برای خانواده می‌رود و بعد از چند بار، کسی جدی‌اش نمی‌گیرد —
  /// که یعنی دکمه عملاً از کار افتاده.
  ///
  /// اما بیشتر از سه ثانیه هم نمی‌شود: کسی که واقعاً کمک می‌خواهد نباید
  /// منتظر بماند.
  void beginCountdown() {
    state = state.copyWith(phase: SosPhase.countdown, clearError: true);
  }

  void cancel() {
    if (state.phase == SosPhase.countdown) {
      state = state.copyWith(phase: SosPhase.idle);
    }
  }

  /// ارسال واقعی هشدار.
  Future<bool> trigger({String? note}) async {
    state = state.copyWith(phase: SosPhase.sending, clearError: true);

    final TrackingController tracking =
        _ref.read(trackingControllerProvider.notifier);

    Position? position;
    try {
      position = await tracking.currentPositionForEmergency();
    } catch (_) {
      position = null;
    }

    final int? battery = _ref.read(trackingControllerProvider).batteryLevel;

    try {
      final SosResult result = await _repository.trigger(
        lat: position?.latitude,
        lng: position?.longitude,
        accuracyM: position?.accuracy,
        batteryLevel: battery,
        note: note,
      );

      state = state.copyWith(phase: SosPhase.sent, result: result);
      return true;
    } on AppException catch (error) {
      state = state.copyWith(phase: SosPhase.failed, error: error);
      return false;
    }
  }

  void reset() => state = const SosState().copyWith(contacts: state.contacts);
}

final StateNotifierProvider<SosController, SosState> sosControllerProvider =
    StateNotifierProvider<SosController, SosState>((ref) {
  return SosController(ref);
});
