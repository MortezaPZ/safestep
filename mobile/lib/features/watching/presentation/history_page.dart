import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../../../core/utils/jalali_format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/osm_tile_layer.dart';
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
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyControllerProvider(widget.userId).notifier).init();
    });
  }

  /// جا دادن کل مسیر در کادر نقشه.
  void _fitBounds(List<TrackPoint> points) {
    if (points.isEmpty) return;

    final List<LatLng> coords = <LatLng>[
      for (final TrackPoint point in points) LatLng(point.lat, point.lng),
    ];

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: coords,
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
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
          unawaited(Future<void>.delayed(const Duration(milliseconds: 80), () {
            _fitBounds(next.points);
          }));
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
      mapController: _mapController,
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
  const _RouteMap({required this.points, required this.mapController});

  final List<TrackPoint> points;
  final MapController mapController;

  static const int _maxSegments = 24;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'نقشه‌ی مسیر با ${Fa.digits(points.length.toString())} نقطه، '
          'از ${JalaliFormat.time(points.first.recordedAt)} '
          'تا ${JalaliFormat.time(points.last.recordedAt)}',
      child: ExcludeSemantics(
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: LatLng(points.first.lat, points.first.lng),
            initialZoom: 14,
          ),
          children: <Widget>[
            const OsmTileLayer(),
            PolylineLayer(
              polylines: _buildPolylines(),
            ),
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: LatLng(points.first.lat, points.first.lng),
                  width: 18,
                  height: 18,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Marker(
                  point: LatLng(points.last.lat, points.last.lng),
                  width: 18,
                  height: 18,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Polyline> _buildPolylines() {
    if (points.length < 2) return const <Polyline>[];

    final int segmentSize = (points.length / _maxSegments).ceil().clamp(1, 1000);
    final List<Polyline> lines = <Polyline>[];

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
          points: chunk,
          strokeWidth: 5,
          color: Color.lerp(
                AppColors.primaryDark,
                AppColors.primary,
                progress,
              ) ??
              AppColors.primary,
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
          children: <Widget>[
            Expanded(
              child: _Metric(
                label: 'مسافت',
                value: Fa.distance(result.distanceM),
                icon: Icons.route_rounded,
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'نقاط',
                value: Fa.digits(result.pingCount.toString()),
                icon: Icons.scatter_plot_rounded,
              ),
            ),
            if (result.firstAt != null && result.lastAt != null)
              Expanded(
                child: _Metric(
                  label: 'بازه',
                  value: '${JalaliFormat.time(result.firstAt!)}'
                      ' تا ${JalaliFormat.time(result.lastAt!)}',
                  icon: Icons.schedule_rounded,
                ),
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
        Text(
          value,
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
