import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tracking_point.dart';

class TrackingRepository {
  TrackingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> createSession({
    required String sessionId,
    required DateTime startedAt,
  }) async {
    await _firestore.collection('tracking_sessions').doc(sessionId).set({
      'startedAt': startedAt.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'distanceMeters': 0,
      'elevationGainMeters': 0,
      'caloriesKcal': 0,
      'isAutoPaused': false,
      'points': 0,
    });
  }

  Future<void> appendPoint({
    required String sessionId,
    required TrackingPoint point,
    required double totalDistanceMeters,
    required double elevationGainMeters,
    required double caloriesKcal,
    required bool isAutoPaused,
    required int points,
  }) async {
    final sessionRef = _firestore
        .collection('tracking_sessions')
        .doc(sessionId);
    final pointRef = sessionRef.collection('points').doc();
    await _firestore.runTransaction((transaction) async {
      transaction.set(pointRef, point.toMap());
      transaction.update(sessionRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'distanceMeters': totalDistanceMeters,
        'elevationGainMeters': elevationGainMeters,
        'caloriesKcal': caloriesKcal,
        'isAutoPaused': isAutoPaused,
        'points': points,
      });
    });
  }

  Future<void> closeSession({
    required String sessionId,
    required DateTime endedAt,
    required double distanceMeters,
    required double elevationGainMeters,
    required double caloriesKcal,
    required int points,
  }) async {
    await _firestore.collection('tracking_sessions').doc(sessionId).update({
      'status': 'stopped',
      'endedAt': endedAt.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'distanceMeters': distanceMeters,
      'elevationGainMeters': elevationGainMeters,
      'caloriesKcal': caloriesKcal,
      'isAutoPaused': false,
      'points': points,
    });
  }
}
