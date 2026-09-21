import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../network/server_origin.dart';

/// لایهٔ کاشی OSM از پروکسی همین سرور.
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: ServerOrigin.tileUrl,
      userAgentPackageName: 'safestep',
      maxZoom: 19,
    );
  }
}

LatLng toLatLng(double lat, double lng) => LatLng(lat, lng);
