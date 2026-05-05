import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

Widget buildFlyoverReplayPage({
  required List<LatLng> points,
  required String title,
  List<double>? elevations,
  int durationSeconds = 0,
  double distanceKm = 0.0,
}) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(
      child: Text('3D flyover replay is available on Android only.'),
    ),
  );
}
