class TrackingPoint {
  const TrackingPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedMps,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final double? speedMps;
  final double? altitudeMeters;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'timestamp': timestamp.toIso8601String(),
      'speedMps': speedMps,
      'altitudeMeters': altitudeMeters,
    };
  }
}
