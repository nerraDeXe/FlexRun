class TrackingSnapshot {
  const TrackingSnapshot({
    required this.isTracking,
    required this.isAutoPaused,
    required this.isManuallyPaused,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.caloriesKcal,
    required this.points,
    required this.elapsedSeconds,
    required this.sessionId,
    required this.startedAt,
    required this.latitude,
    required this.longitude,
    this.currentHeartRate,
    this.heartRateReadings = const [],
  });

  final bool isTracking;
  final bool isAutoPaused;
  final bool isManuallyPaused;
  final double distanceMeters;
  final double elevationGainMeters;
  final double caloriesKcal;
  final int points;
  final int elapsedSeconds;
  final String? sessionId;
  final DateTime? startedAt;
  final double? latitude;
  final double? longitude;
  final int? currentHeartRate;
  final List<int> heartRateReadings;

  /// Calculate average heart rate from readings
  int get averageHeartRate {
    if (heartRateReadings.isEmpty) return 0;
    final sum = heartRateReadings.fold<int>(0, (a, b) => a + b);
    return (sum / heartRateReadings.length).round();
  }
}
