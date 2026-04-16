class TrackingSnapshot {
  const TrackingSnapshot({
    required this.isTracking,
    required this.distanceMeters,
    required this.points,
    required this.sessionId,
    required this.startedAt,
    required this.latitude,
    required this.longitude,
  });

  final bool isTracking;
  final double distanceMeters;
  final int points;
  final String? sessionId;
  final DateTime? startedAt;
  final double? latitude;
  final double? longitude;
}
