import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/main_nav.dart';
import '../../../core/widgets/osm_tile_layer.dart';
import '../data/location_repository.dart';
import 'zone_overlay.dart';

/// نقشهٔ موقعیت خود کاربر، مثل کارت نقشه در داشبورد وب.
class MyMapPage extends ConsumerStatefulWidget {
  const MyMapPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<MyMapPage> createState() => _MyMapPageState();
}

class _MyMapPageState extends ConsumerState<MyMapPage> {
  OwnStatus? _status;
  List<MapZone> _zones = const <MapZone>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ApiClient api = ref.read(apiClientProvider);
    OwnStatus? status;
    List<MapZone> zones = const <MapZone>[];
    try {
      status = await ref.read(locationRepositoryProvider).ownStatus();
    } catch (_) {}
    try {
      final Map<String, dynamic> data = await api.get<Map<String, dynamic>>(
        ApiEndpoints.safeZones,
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      );
      zones = MapZone.parseList(data['zones']);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _status = status;
      _zones = zones;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget map = _MapBody(
      status: _status,
      zones: _zones,
      loading: _loading,
      height: widget.embedded ? 220 : null,
    );
    if (widget.embedded) return map;
    return AppScaffold(
      title: 'نقشه',
      showBackButton: false,
      bottomBar: const MainNav(current: 'map'),
      body: map,
    );
  }
}

class _MapBody extends StatelessWidget {
  const _MapBody({
    required this.status,
    required this.zones,
    required this.loading,
    this.height,
  });

  final OwnStatus? status;
  final List<MapZone> zones;
  final bool loading;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final double? lat = status?.lat;
    final double? lng = status?.lng;
    final Widget child;
    if (loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if ((lat == null || lng == null) && zones.isEmpty) {
      child = const Center(child: Text('هنوز موقعیتی ثبت نشده است.'));
    } else {
      final LatLng point = lat != null && lng != null
          ? LatLng(lat, lng)
          : LatLng(zones.first.lat, zones.first.lng);
      child = FlutterMap(
        options: MapOptions(initialCenter: point, initialZoom: 15),
        children: <Widget>[
          const OsmTileLayer(),
          ...zoneLayers(zones),
          if (lat != null && lng != null)
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: LatLng(lat, lng),
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                ),
              ],
            ),
        ],
      );
    }

    if (height != null) {
      return SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: child,
        ),
      );
    }
    return child;
  }
}
