import 'dart:math';

import '../models/tracking_point.dart';

class DistanceCalculator {
  static const double _earthRadiusMeters = 6371000;

  static double haversineMeters(TrackingPoint from, TrackingPoint to) {
    final lat1 = _degToRad(from.latitude);
    final lon1 = _degToRad(from.longitude);
    final lat2 = _degToRad(to.latitude);
    final lon2 = _degToRad(to.longitude);
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * pi / 180;
}
