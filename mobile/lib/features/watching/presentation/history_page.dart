import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../../../core/utils/jalali_format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../data/watching_repository.dart';
import '../domain/watched_person.dart';

/// وضعیت صفحه‌ی تاریخچه.
class HistoryState {
  const HistoryState({
    this.days = const <HistoryDay>[],
    this.selectedDay,
    this.result,
    this.loading = false,
    this.error,
  });

  final List<HistoryDay> days;
  final DateTime? selectedDay;
  final HistoryResult? result;
  final bool loading;
  final AppException? error;

  HistoryState copyWith({
    List<HistoryDay>? days,
    DateTime? selectedDay,
    HistoryResult? result,
    bool? loading,
    AppException? error,
    bool clearError = false,
  }) {
    return HistoryState(
      days: days ?? this.days,
      selectedDay: selectedDay ?? this.selectedDay,
      result: result ?? this.result,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HistoryController extends StateNotifier<HistoryState> {
  HistoryController(this._repository, this._userId) : super(const HistoryState());

  final WatchingRepository _repository;
  final String _userId;

  /// خواندن روزهای موجود و انتخاب خودکار تازه‌ترین.
  Future<void> init() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final List<HistoryDay> days = await _repository.historyDays(_userId);

      if (days.isEmpty) {
        state = state.copyWith(days: days, loading: false);
        return;
      }

      state = state.copyWith(days: days);
      await selectDay(days.first.day);
    } on AppException catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  /// بارگذاری مسیر یک روز.
  ///
  /// بازه از ابتدای همان روزِ **محلی** تا انتهایش گرفته می‌شود، نه UTC.
  /// اگر با UTC حساب کنیم، «امروز» برای کاربر ایرانی از ساعت ۳:۳۰ بامداد
  /// شروع می‌شود و نیمه‌شبِ واقعی وسط دو روز می‌افتد.
  Future<void> selectDay(DateTime day) async {
    state = state.copyWith(loading: true, selectedDay: day, clearError: true);

    final DateTime local = day.toLocal();
    final DateTime from = DateTime(local.year, local.month, local.day);
    final DateTime to = from.add(const Duration(days: 1)).subtract(
          const Duration(milliseconds: 1),
        );

    try {
      final HistoryResult result = await _repository.history(
        userId: _userId,
        from: from,
        to: to,
      );
      state = state.copyWith(result: result, loading: false);
    } on AppException catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }
}

/// کنترلر به‌ازای هر کاربر ساخته می‌شود و با بسته شدن صفحه آزاد می‌گردد.
final AutoDisposeStateNotifierProviderFamily<HistoryController, HistoryState, String>
    historyControllerProvider = StateNotifierProvider.autoDispose
        .family<HistoryController, HistoryState, String>((ref, String userId) {
  return HistoryController(ref.watch(watchingRepositoryProvider), userId);
});

/* ═══════════════════════════ صفحه ═══════════════════════════ */

/// تاریخچه‌ی مسیر یک روز.
///
/// ── چرا مسیر با گرادیان رنگی رسم می‌شود ─────────────────────────────────
/// یک خط تک‌رنگ نمی‌گوید حرکت از کجا شروع شده و به کجا رسیده. با روشن‌تر
/// شدن رنگ در طول مسیر، جهت حرکت بدون هیچ توضیحی خوانده می‌شود. برای
/// کسانی که تفاوت رنگ را نمی‌بینند، دو نشانگر «شروع» و «پایان» هم هست —
/// رنگ هرگز تنها حامل معنا نیست.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, required this.userId, this.personName});

  final String userId;
  final String? personName;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyControllerProvider(widget.userId).notifier).init();
    });
  }

  /// جا دادن کل مسیر در کادر نقشه.
  Future<void> _fitBounds(List<TrackPoint> points) async {
    if (points.isEmpty || !_mapController.isCompleted) return;

    double minLat = points.first.lat;
    double maxLat = points.first.lat;
    double minLng = points.first.lng;
    double maxLng = points.first.lng;

    for (final TrackPoint point in points) {
      if (point.lat < minLat) minLat = point.lat;
      if (point.lat > maxLat) maxLat = point.lat;
      if (point.lng < minLng) minLng = point.lng;
      if (point.lng > maxLng) maxLng = point.lng;
    }

    final GoogleMapController controller = await _mapController.future;

    // مسیرِ تک‌نقطه‌ای کادر بی‌بعد می‌سازد که نقشه را می‌شکند
    if ((maxLat - minLat).abs() < 0.0001 && (maxLng - minLng).abs() < 0.0001) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 16),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HistoryState state = ref.watch(historyControllerProvider(widget.userId));

    ref.listen<HistoryResult?>(
      historyControllerProvider(widget.userId).select((HistoryState s) => s.result),
      (HistoryResult? previous, HistoryResult? next) {
        if (next != null && next.points.isNotEmpty) {
          unawaited(_fitBounds(next.points));
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.personName == null
              ? 'تاریخچه‌ی مسیر'
              : 'مسیر ${widget.personName}',
        ),
      ),
      body: Column(
        children: <Widget>[
          _DayPicker(
            days: state.days,
            selected: state.selectedDay,
            onSelect: (DateTime day) {
              AppHaptics.tap(ref);
              ref
                  .read(historyControllerProvider(widget.userId).notifier)
                  .selectDay(day);
            },
          ),
          Expanded(child: _buildBody(state)),
          if (state.result != null && state.result!.points.isNotEmpty)
            _SummaryBar(result: state.result!),
        ],
      ),
    );
  }

  Widget _buildBody(HistoryState state) {
    if (state.error != null) {
      return ErrorView(
        error: state.error!,
        onRetry: () =>
            ref.read(historyControllerProvider(widget.userId).notifier).init(),
      );
    }

    if (state.loading && state.result == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.pageH),
        child: LoadingSkeleton(lines: 2, height: 140),
      );
    }

    if (state.days.isEmpty) {
      return const EmptyView(
        icon: Icons.timeline_outlined,
        title: 'هنوز تاریخچه‌ای نیست',
        message: 'به‌محض اینکه موقعیتی ثبت شود، مسیر روزها اینجا می‌آید.',
      );
    }

    final HistoryResult? result = state.result;

    if (result != null && result.hidden) {
      return const EmptyView(
        icon: Icons.visibility_off_outlined,
        title: 'تاریخچه در دسترس نیست',
        message: 'کاربر اشتراک‌گذاری موقعیت را خاموش کرده است.',
      );
    }

    if (result == null || result.points.isEmpty) {
      return const EmptyView(
        icon: Icons.explore_off_outlined,
        title: 'در این روز مسیری ثبت نشده',
        message: 'روز دیگری را انتخاب کنید.',
      );
    }

    return _RouteMap(
      points: result.points,
      onCreated: (GoogleMapController controller) {
        if (!_mapController.isCompleted) _mapController.complete(controller);
        unawaited(_fitBounds(result.points));
      },
    );
  }
}

/* ═══════════════════════════ اجزا ═══════════════════════════ */

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<HistoryDay> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageH,
          vertical: AppSpacing.sm,
        ),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final HistoryDay day = days[index];
          final bool isSelected = selected != null &&
              day.day.year == selected!.year &&
              day.day.month == selected!.month &&
              day.day.day == selected!.day;

          return Semantics(
            label: '${JalaliFormat.dayLabel(day.day)}، '
                '${Fa.digits(day.pingCount.toString())} نقطه',
            selected: isSelected,
            button: true,
            excludeSemantics: true,
            child: ChoiceChip(
              selected: isSelected,
              onSelected: (_) => onSelect(day.day),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(JalaliFormat.dayLabel(day.day)),
                  Text(
                    Fa.digits(day.pingCount.toString()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.points, required this.onCreated});

  final List<TrackPoint> points;
  final void Function(GoogleMapController) onCreated;

  /// مسیر به چند قطعه شکسته می‌شود تا گرادیان رنگی ساخته شود.
  ///
  /// Google Maps برای هر خط فقط یک رنگ می‌پذیرد، پس تنها راهِ گرادیان،
  /// چند خطِ پشت سر هم است. تعداد قطعه‌ها محدود است چون هر خط یک شیء روی
  /// نقشه است و صدها شیء، گوشی‌های ضعیف را کند می‌کند.
  static const int _maxSegments = 24;

  @override
  Widget build(BuildContext context) {
    final Set<Polyline> polylines = _buildPolylines();

    return Semantics(
      label: 'نقشه‌ی مسیر با ${Fa.digits(points.length.toString())} نقطه، '
          'از ${JalaliFormat.time(points.first.recordedAt)} '
          'تا ${JalaliFormat.time(points.last.recordedAt)}',
      child: ExcludeSemantics(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(points.first.lat, points.first.lng),
            zoom: 14,
          ),
          onMapCreated: onCreated,
          polylines: polylines,
          markers: <Marker>{
            Marker(
              markerId: const MarkerId('start'),
              position: LatLng(points.first.lat, points.first.lng),
              infoWindow: InfoWindow(
                title: 'شروع',
                snippet: JalaliFormat.time(points.first.recordedAt),
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            ),
            Marker(
              markerId: const MarkerId('end'),
              position: LatLng(points.last.lat, points.last.lng),
              infoWindow: InfoWindow(
                title: 'پایان',
                snippet: JalaliFormat.time(points.last.recordedAt),
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          },
          zoomControlsEnabled: false,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }

  Set<Polyline> _buildPolylines() {
    if (points.length < 2) return const <Polyline>{};

    final int segmentSize = (points.length / _maxSegments).ceil().clamp(1, 1000);
    final Set<Polyline> lines = <Polyline>{};

    int index = 0;
    int segment = 0;

    while (index < points.length - 1) {
      final int end = (index + segmentSize).clamp(0, points.length - 1);

      final List<LatLng> chunk = <LatLng>[
        for (int i = index; i <= end; i++) LatLng(points[i].lat, points[i].lng),
      ];

      final double progress = points.length <= 1 ? 1 : index / (points.length - 1);

      lines.add(
        Polyline(
          polylineId: PolylineId('segment_$segment'),
          points: chunk,
          width: 5,
          // از آبی تیره (شروع) به آبی روشن (پایان)
          color: Color.lerp(
                AppColors.primaryDark,
                AppColors.primary,
                progress,
              ) ??
              AppColors.primary,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );

      index = end;
      segment++;
    }

    return lines;
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.result});

  final HistoryResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: AppCard(
        semanticLabel: 'خلاصه‌ی روز: '
            'مسافت ${Fa.distance(result.distanceM)}، '
            '${Fa.digits(result.pingCount.toString())} نقطه',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _Metric(
              label: 'مسافت',
              value: Fa.distance(result.distanceM),
              icon: Icons.route_rounded,
            ),
            _Metric(
              label: 'نقاط',
              value: Fa.digits(result.pingCount.toString()),
              icon: Icons.scatter_plot_rounded,
            ),
            if (result.firstAt != null && result.lastAt != null)
              _Metric(
                label: 'بازه',
                value: '${JalaliFormat.time(result.firstAt!)}'
                    ' تا ${JalaliFormat.time(result.lastAt!)}',
                icon: Icons.schedule_rounded,
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        A11y.decorative(Icon(icon, size: 20)),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: theme.textTheme.titleSmall),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
