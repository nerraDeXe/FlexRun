/// Model representing a runner running concurrently on a similar route
class ConcurrentRunner {
  final String userId;
  final String displayName;
  final String sessionId;
  final double distanceKm;
  final int elapsedSeconds;
  final double currentPaceMinPerKm;
  final DateTime startedAt;
  final double latitude;
  final double longitude;
  final double bearing;

  ConcurrentRunner({
    required this.userId,
    required this.displayName,
    required this.sessionId,
    required this.distanceKm,
    required this.elapsedSeconds,
    required this.currentPaceMinPerKm,
    required this.startedAt,
    required this.latitude,
    required this.longitude,
    required this.bearing,
  });

  /// Converts Firestore snapshot data to ConcurrentRunner
  factory ConcurrentRunner.fromFirestore(Map<String, dynamic> data) {
    return ConcurrentRunner(
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Unknown',
      sessionId: data['sessionId'] as String? ?? '',
      distanceKm: (data['distanceMeters'] as num?)?.toDouble() ?? 0 / 1000,
      elapsedSeconds: (data['activeDurationSeconds'] as num?)?.toInt() ?? 0,
      currentPaceMinPerKm:
          (data['currentPaceMinPerKm'] as num?)?.toDouble() ?? 0,
      startedAt:
          DateTime.tryParse(data['startedAt'] as String? ?? '') ??
          DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      bearing: (data['bearing'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Converts to Firestore-compatible map
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'displayName': displayName,
      'sessionId': sessionId,
      'distanceMeters': (distanceKm * 1000).toInt(),
      'activeDurationSeconds': elapsedSeconds,
      'currentPaceMinPerKm': currentPaceMinPerKm,
      'startedAt': startedAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'bearing': bearing,
    };
  }

  @override
  String toString() => 'ConcurrentRunner($displayName, $distanceKm km)';
}

/// Model for a "ran together" session - the result of concurrent runner matching
class RanTogetherSession {
  final String concurrentUserId;
  final String concurrentUserDisplayName;
  final String concurrentSessionId;
  final double overlapDistance; // km of route that overlapped
  final Duration timeTogether; // how long they ran concurrently
  final DateTime metAtTime; // when they first met on route
  final double concurrentUserFastestPace; // their fastest pace during overlap

  RanTogetherSession({
    required this.concurrentUserId,
    required this.concurrentUserDisplayName,
    required this.concurrentSessionId,
    required this.overlapDistance,
    required this.timeTogether,
    required this.metAtTime,
    required this.concurrentUserFastestPace,
  });

  /// Converts to Firestore-compatible map for storage
  Map<String, dynamic> toFirestore() {
    return {
      'concurrentUserId': concurrentUserId,
      'concurrentUserDisplayName': concurrentUserDisplayName,
      'concurrentSessionId': concurrentSessionId,
      'overlapDistanceKm': overlapDistance,
      'timeTogetherSeconds': timeTogether.inSeconds,
      'metAtTime': metAtTime.toIso8601String(),
      'concurrentUserFastestPace': concurrentUserFastestPace,
    };
  }
}
