import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

Widget buildFlyoverReplayPage({
  required List<LatLng> points,
  required String title,
}) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(
      child: Text('3D flyover replay is available on Android only.'),
    ),
  );
}
