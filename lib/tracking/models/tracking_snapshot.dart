class TrackingSnapshot {
  const TrackingSnapshot({
    required this.isTracking,
    required this.isAutoPaused,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.caloriesKcal,
    required this.points,
    required this.sessionId,
    required this.startedAt,
    required this.latitude,
    required this.longitude,
  });

  final bool isTracking;
  final bool isAutoPaused;
  final double distanceMeters;
  final double elevationGainMeters;
  final double caloriesKcal;
  final int points;
  final String? sessionId;
  final DateTime? startedAt;
  final double? latitude;
  final double? longitude;
}
