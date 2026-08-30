import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/router.dart';
import '../../../core/accessibility/a11y.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../realtime/realtime_controller.dart';
import '../domain/watched_person.dart';
import 'watching_controller.dart';

/// نقشه‌ی زنده‌ی یک فرد تحت پایش.
///
/// ── چرا نقشه تمام‌صفحه نیست ─────────────────────────────────────────────
/// یک کارت وضعیت همیشه پایین صفحه می‌ماند. دلیلش این است که مهم‌ترین
/// اطلاعات این صفحه، خودِ نقطه روی نقشه نیست — بلکه «چند دقیقه پیش
/// به‌روز شده» و «داخل محدوده هست یا نه» است. نقطه‌ای که ندانیم برای
/// کِی است، اطلاعات نیست؛ حدس است.
///
/// ── و چرا دکمه‌ی «دنبال کردن» ────────────────────────────────────────────
/// اگر دوربین با هر به‌روزرسانی خودکار حرکت کند، مراقبی که دارد اطراف را
/// بررسی می‌کند مدام پرت می‌شود. پس دنبال‌کردن یک حالت است که با اولین
/// حرکت دستی خاموش می‌شود و با یک دکمه برمی‌گردد.
class LiveMapPage extends ConsumerStatefulWidget {
  const LiveMapPage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends ConsumerState<LiveMapPage> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  /// دوربین، موقعیت را دنبال می‌کند
  bool _following = true;

  /// آخرین نقطه‌ای که دوربین رویش رفته — تا برای نقطه‌ی تکراری حرکت نکنیم
  DateTime? _lastCameraMove;

  static const double _defaultZoom = 16;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchingControllerProvider.notifier).refreshPerson(widget.userId);
    });
  }

  Future<void> _moveCamera(TrackPoint point, {bool animate = true}) async {
    if (!_mapController.isCompleted) return;

    final GoogleMapController controller = await _mapController.future;
    final CameraUpdate update = CameraUpdate.newLatLngZoom(
      LatLng(point.lat, point.lng),
      _defaultZoom,
    );

    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }

    _lastCameraMove = point.recordedAt;
  }

  @override
  Widget build(BuildContext context) {
    final WatchedPerson? person = ref.watch(watchedPersonProvider(widget.userId));

    // با رسیدن موقعیت تازه، اگر در حالت دنبال‌کردن هستیم دوربین می‌رود
    ref.listen<WatchedPerson?>(
      watchedPersonProvider(widget.userId),
      (WatchedPerson? previous, WatchedPerson? next) {
        final TrackPoint? point = next?.location;
        if (point == null || !_following) return;
        if (_lastCameraMove != null && !point.recordedAt.isAfter(_lastCameraMove!)) {
          return;
        }
        unawaited(_moveCamera(point));

        // اعلام برای صفحه‌خوان: کاربر نابینا حرکت نقطه را نمی‌بیند
        if (previous?.location?.recordedAt != point.recordedAt) {
          A11y.announce(context, 'موقعیت به‌روزرسانی شد');
        }
      },
    );

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('نقشه')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(person.person.fullName),
        actions: <Widget>[
          IconButton(
            tooltip: 'تاریخچه‌ی مسیر',
            icon: const Icon(Icons.timeline_rounded),
            onPressed: () => context.push(AppRoutes.historyFor(widget.userId)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildMapArea(person)),
          _StatusPanel(person: person),
        ],
      ),
      floatingActionButton: person.hasLocation && !person.hidden
          ? FloatingActionButton(
              onPressed: () {
                setState(() => _following = true);
                final TrackPoint? point = person.location;
                if (point != null) unawaited(_moveCamera(point));
              },
              tooltip: _following ? 'در حال دنبال کردن' : 'برگشت به موقعیت',
              backgroundColor:
                  _following ? AppColors.primary : Theme.of(context).cardColor,
              child: Icon(
                _following ? Icons.my_location_rounded : Icons.location_searching_rounded,
                color: _following ? Colors.white : AppColors.primary,
              ),
            )
          : null,
    );
  }

  Widget _buildMapArea(WatchedPerson person) {
    // کاربر اشتراک‌گذاری را خاموش کرده — این خطا نیست، یک انتخاب است
    if (person.hidden) {
      return EmptyView(
        icon: Icons.visibility_off_outlined,
        title: 'موقعیت در دسترس نیست',
        message: person.hiddenMessage ??
            'کاربر اشتراک‌گذاری موقعیت را موقتاً خاموش کرده است.',
      );
    }

    final TrackPoint? point = person.location;

    if (point == null) {
      return const EmptyView(
        icon: Icons.location_searching_rounded,
        title: 'هنوز موقعیتی ثبت نشده',
        message: 'به‌محض اینکه اپ ایشان موقعیتی بفرستد، همین‌جا نمایش داده می‌شود.',
      );
    }

    final Color markerColor = AppColors.parse(person.person.avatarColor);

    return Semantics(
      // نقشه برای صفحه‌خوان معنا ندارد؛ توضیح متنی جایگزینش می‌شود
      label: 'نقشه‌ی موقعیت ${person.person.fullName}. '
          '${_zoneLabel(person)}. آخرین به‌روزرسانی ${Fa.timeAgo(point.recordedAt)}',
      child: ExcludeSemantics(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(point.lat, point.lng),
            zoom: _defaultZoom,
          ),
          onMapCreated: (GoogleMapController controller) {
            if (!_mapController.isCompleted) {
              _mapController.complete(controller);
            }
          },
          // اولین حرکت دستی، دنبال‌کردن را خاموش می‌کند
          onCameraMoveStarted: () {
            if (_following) setState(() => _following = false);
          },
          markers: <Marker>{
            Marker(
              markerId: MarkerId(person.userId),
              position: LatLng(point.lat, point.lng),
              infoWindow: InfoWindow(
                title: person.person.fullName,
                snippet: Fa.timeAgo(point.recordedAt),
              ),
            ),
          },
          circles: <Circle>{
            // دایره‌ی دقت: نقطه‌ی تنها این توهم را می‌سازد که موقعیت
            // دقیقاً همان‌جاست. با دایره، مراقب می‌بیند که «جایی در این
            // محدوده» درست‌تر است.
            if (point.accuracyM != null && point.accuracyM! > 0)
              Circle(
                circleId: CircleId('${person.userId}_accuracy'),
                center: LatLng(point.lat, point.lng),
                radius: point.accuracyM!,
                fillColor: markerColor.withOpacity(0.12),
                strokeColor: markerColor.withOpacity(0.35),
                strokeWidth: 1,
              ),
          },
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }

  static String _zoneLabel(WatchedPerson person) {
    if (person.zoneStatus == 'inside' && person.zoneNames.isNotEmpty) {
      return 'داخل «${person.zoneNames.first}»';
    }
    if (person.zoneStatus == 'outside') return 'خارج از محدوده‌های امن';
    return 'وضعیت محدوده نامشخص';
  }
}

/// کارت وضعیت زیر نقشه.
class _StatusPanel extends ConsumerWidget {
  const _StatusPanel({required this.person});

  final WatchedPerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final TrackPoint? point = person.location;

    final bool connected = ref.watch(
      realtimeControllerProvider.select(
        (RealtimeState s) => s.status == SocketStatus.connected,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: AppCard(
        accentColor: _statusColor(person),
        semanticLabel: _semanticSummary(person, connected),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                A11y.decorative(
                  Icon(_statusIcon(person), color: _statusColor(person), size: 28),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _statusTitle(person),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (person.isOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    child: const Text(
                      'آنلاین',
                      style: TextStyle(color: AppColors.success, fontSize: 12),
                    ),
                  ),
              ],
            ),

            if (point != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xxs,
                children: <Widget>[
                  _Fact(
                    icon: Icons.schedule_rounded,
                    label: Fa.timeAgo(point.recordedAt),
                  ),
                  if (point.accuracyM != null)
                    _Fact(
                      icon: Icons.adjust_rounded,
                      label: 'دقت ${Fa.distance(point.accuracyM!)}',
                    ),
                  if (point.batteryLevel != null)
                    _Fact(
                      icon: _batteryIcon(point.batteryLevel!),
                      label: 'باتری ${Fa.percent(point.batteryLevel!)}',
                    ),
                  if (point.isSimulated)
                    const _Fact(
                      icon: Icons.movie_outlined,
                      label: 'حالت نمایش',
                      color: AppColors.simulated,
                    ),
                ],
              ),
            ],

            if (!connected) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'اتصال زنده برقرار نیست؛ ممکن است داده کمی قدیمی باشد.',
                style: theme.textTheme.bodySmall,
              ),
            ],

            const SizedBox(height: AppSpacing.sm),

            AppButton(
              label: 'تاریخچه‌ی مسیر',
              icon: Icons.timeline_rounded,
              variant: AppButtonVariant.outlined,
              onPressed: () => context.push(AppRoutes.historyFor(person.userId)),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusTitle(WatchedPerson person) {
    if (person.hidden) return 'اشتراک‌گذاری خاموش است';
    if (person.gpsStale) return 'موقعیت قدیمی است';
    if (person.zoneStatus == 'inside' && person.zoneNames.isNotEmpty) {
      return 'در «${person.zoneNames.first}»';
    }
    if (person.zoneStatus == 'outside') return 'خارج از محدوده‌های امن';
    return 'در حال پایش';
  }

  static IconData _statusIcon(WatchedPerson person) {
    if (person.hidden) return Icons.visibility_off_outlined;
    if (person.gpsStale) return Icons.gps_off_rounded;
    if (person.zoneStatus == 'inside') return Icons.home_rounded;
    if (person.zoneStatus == 'outside') return Icons.explore_outlined;
    return Icons.location_on_rounded;
  }

  static Color _statusColor(WatchedPerson person) {
    if (person.hidden) return AppColors.lightTextMuted;
    if (person.gpsStale) return AppColors.warning;
    if (person.zoneStatus == 'inside') return AppColors.success;
    if (person.zoneStatus == 'outside') return AppColors.warning;
    return AppColors.primary;
  }

  static IconData _batteryIcon(int level) {
    if (level <= 15) return Icons.battery_alert_rounded;
    if (level <= 50) return Icons.battery_3_bar_rounded;
    return Icons.battery_full_rounded;
  }

  static String _semanticSummary(WatchedPerson person, bool connected) {
    final StringBuffer buffer = StringBuffer()
      ..write('${person.person.fullName}. ')
      ..write('${_statusTitle(person)}. ');

    final TrackPoint? point = person.location;
    if (point != null) {
      buffer.write('آخرین به‌روزرسانی ${Fa.timeAgo(point.recordedAt)}. ');
      if (point.batteryLevel != null) {
        buffer.write('باتری ${Fa.percent(point.batteryLevel!)}. ');
      }
    }

    if (!connected) buffer.write('اتصال زنده برقرار نیست.');

    return buffer.toString();
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        A11y.decorative(Icon(icon, size: 16, color: color)),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
