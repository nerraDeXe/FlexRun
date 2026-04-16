class TrackingSnapshot {
  const TrackingSnapshot({
    required this.isTracking,
    required this.distanceMeters,
    required this.points,
    required this.sessionId,
    required this.startedAt,
  });

  final bool isTracking;
  final double distanceMeters;
  final int points;
  final String? sessionId;
  final DateTime? startedAt;
}
