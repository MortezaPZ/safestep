import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// یک محدوده امن برای رسم روی نقشه، با نام همیشه خوانا.
class MapZone {
  const MapZone({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    this.color,
  });

  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  final Color? color;

  static List<MapZone> parseList(Object? raw) {
    if (raw is! List) return const <MapZone>[];
    final List<MapZone> zones = <MapZone>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(item);
      final double? lat = _num(map['centerLat']);
      final double? lng = _num(map['centerLng']);
      final double? radius = _num(map['radiusM']);
      if (lat == null || lng == null || radius == null || radius <= 0) continue;
      zones.add(MapZone(
        name: (map['name'] ?? 'محدوده امن').toString(),
        lat: lat,
        lng: lng,
        radiusM: radius,
        color: _color(map['color']),
      ));
    }
    return zones;
  }

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static Color? _color(Object? raw) {
    final String text = (raw ?? '').toString();
    if (!text.startsWith('#') || text.length != 7) return null;
    final int? value = int.tryParse(text.substring(1), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

List<Widget> zoneLayers(List<MapZone> zones) {
  if (zones.isEmpty) return const <Widget>[];
  return <Widget>[
    CircleLayer(
      circles: <CircleMarker>[
        for (final MapZone zone in zones)
          CircleMarker(
            point: LatLng(zone.lat, zone.lng),
            radius: zone.radiusM,
            useRadiusInMeter: true,
            color: (zone.color ?? const Color(0xFF00AFA3)).withOpacity(0.18),
            borderColor: zone.color ?? const Color(0xFF008F87),
            borderStrokeWidth: 2,
          ),
      ],
    ),
    MarkerLayer(
      markers: <Marker>[
        for (final MapZone zone in zones)
          Marker(
            point: LatLng(zone.lat, zone.lng),
            width: 160,
            height: 36,
            alignment: Alignment.center,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    zone.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF103B3A),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  ];
}
