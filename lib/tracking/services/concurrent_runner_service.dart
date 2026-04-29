import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_strava/core/utils.dart';
import 'package:fake_strava/tracking/models/concurrent_runner.dart';
import 'package:latlong2/latlong.dart';

class ConcurrentRunnerService {
  final FirebaseFirestore firestore;

  ConcurrentRunnerService({required this.firestore});

  /// Starts broadcasting this user's live location to Firebase
  /// Called every 60-90 seconds during active tracking
  Future<void> broadcastLiveLocation({
    required String userId,
    required String displayName,
    required String sessionId,
    required double latitude,
    required double longitude,
    required double distanceKm,
    required int elapsedSeconds,
    required double currentPaceMinPerKm,
    required bool isGhostMode,
  }) async {
    if (isGhostMode) {
      // If ghost mode is on, don't broadcast
      return;
    }

    final geohash = generateGeohash(latitude, longitude, precision: 6);
    final bearing = calculateBearing(
      latitude,
      longitude,
      latitude + 0.001, // Approximation for current bearing
      longitude + 0.001,
    );

    await firestore.collection('active_runners').doc(sessionId).set({
      'userId': userId,
      'displayName': displayName,
      'sessionId': sessionId,
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
      'geohash_prefix': geohash.substring(0, 5), // For querying
      'bearing': bearing,
      'distanceMeters': (distanceKm * 1000).toInt(),
      'activeDurationSeconds': elapsedSeconds,
      'currentPaceMinPerKm': currentPaceMinPerKm,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Queries for nearby runners within the same geohash prefix
  /// Uses a 5-minute time window to find active runners
  Future<List<ConcurrentRunner>> findNearbyRunners({
    required double latitude,
    required double longitude,
  }) async {
    final geohash = generateGeohash(latitude, longitude, precision: 6);
    final geohashPrefix = geohash.substring(0, 5);
    final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));

    try {
      final snapshot = await firestore
          .collection('active_runners')
          .where('geohash_prefix', isEqualTo: geohashPrefix)
          .where('lastUpdated', isGreaterThan: fiveMinutesAgo)
          .get();

      final runners = <ConcurrentRunner>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final runner = ConcurrentRunner.fromFirestore(data);
        runners.add(runner);
      }

      return runners;
    } catch (e) {
      print('Error finding nearby runners: $e');
      return [];
    }
  }

  /// Filters concurrent runners based on spatial-temporal criteria
  /// Returns only runners that:
  /// - Are within reasonable proximity (same geohash area)
  /// - Are moving in similar direction (bearing within 45°)
  /// - Started within 10 minutes of this user
  List<ConcurrentRunner> filterRelevantRunners({
    required List<ConcurrentRunner> candidates,
    required double userLatitude,
    required double userLongitude,
    required double userBearing,
    required DateTime userStartTime,
    double proximityKm = 1.5, // Within 1.5 km
    double bearingTolerance = 45, // ±45 degrees
    int timeWindowMinutes = 10, // Within 10 minutes of start
  }) {
    final filtered = <ConcurrentRunner>[];

    for (final runner in candidates) {
      // Check proximity (Haversine)
      final distance = haversineDistance(
        userLatitude,
        userLongitude,
        runner.latitude,
        runner.longitude,
      );
      if (distance > proximityKm) continue;

      // Check bearing similarity
      if (!areBearingsSimilar(
        userBearing,
        runner.bearing,
        tolerance: bearingTolerance,
      )) {
        continue;
      }

      // Check time window
      final timeDiff = userStartTime
          .difference(runner.startedAt)
          .inMinutes
          .abs();
      if (timeDiff > timeWindowMinutes) continue;

      filtered.add(runner);
    }

    return filtered;
  }

  /// Stores a "ran together" record for post-run summary
  Future<void> recordRanTogether({
    required String userId,
    required String sessionId,
    required RanTogetherSession ranTogetherData,
  }) async {
    await firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('concurrent_runners')
        .doc(ranTogetherData.concurrentUserId)
        .set(ranTogetherData.toFirestore());
  }

  /// Retrieves all users who ran concurrently with this session
  Future<List<RanTogetherSession>> getRanTogetherSessions(
    String sessionId,
  ) async {
    try {
      final snapshot = await firestore
          .collection('tracking_sessions')
          .doc(sessionId)
          .collection('concurrent_runners')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return RanTogetherSession(
          concurrentUserId: data['concurrentUserId'] as String? ?? '',
          concurrentUserDisplayName:
              data['concurrentUserDisplayName'] as String? ?? 'Unknown',
          concurrentSessionId: data['concurrentSessionId'] as String? ?? '',
          overlapDistance: (data['overlapDistanceKm'] as num?)?.toDouble() ?? 0,
          timeTogether: Duration(
            seconds: (data['timeTogetherSeconds'] as num?)?.toInt() ?? 0,
          ),
          metAtTime:
              DateTime.tryParse(data['metAtTime'] as String? ?? '') ??
              DateTime.now(),
          concurrentUserFastestPace:
              (data['concurrentUserFastestPace'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    } catch (e) {
      print('Error retrieving ran together sessions: $e');
      return [];
    }
  }

  /// Cleans up old active runner entries (older than 30 minutes)
  Future<void> cleanupStaleRunners() async {
    final thirtyMinutesAgo = DateTime.now().subtract(
      const Duration(minutes: 30),
    );

    await firestore
        .collection('active_runners')
        .where('lastUpdated', isLessThan: thirtyMinutesAgo)
        .get()
        .then((snapshot) {
          for (final doc in snapshot.docs) {
            doc.reference.delete();
          }
        });
  }

  /// Removes this user's active runner entry when they finish
  Future<void> stopBroadcasting(String sessionId) async {
    await firestore.collection('active_runners').doc(sessionId).delete();
  }
}
