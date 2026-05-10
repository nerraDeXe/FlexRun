import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/tracking_point.dart';

import 'package:firebase_core/firebase_core.dart';

class TrackingRepository {
  TrackingRepository({FirebaseFirestore? firestore})
    : _firestore =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          );

  final FirebaseFirestore _firestore;
  bool _cloudSyncEnabled = true;

  bool _isMissingDatabaseError(Object error) {
    if (error is! FirebaseException) {
      return false;
    }
    final message = error.message?.toLowerCase() ?? '';
    return error.code == 'not-found' &&
        (message.contains('database (default) does not exist') ||
            message.contains('database fakestrava does not exist'));
  }

  void _disableCloudSync(Object error) {
    _cloudSyncEnabled = false;
    debugPrint(
      'Fake Strava: Firestore database is not provisioned. Cloud sync disabled. Error: $error',
    );
  }

  Future<void> createSession({
    required String sessionId,
    required DateTime startedAt,
    required String? userId,
    String? userDisplayName,
    String? username,
  }) async {
    if (!_cloudSyncEnabled) {
      return;
    }
    _firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .set({
          'userId': userId,
          'userDisplayName': userDisplayName,
          'username': username,
          'startedAt': startedAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'distanceMeters': 0,
          'elevationGainMeters': 0,
          'caloriesKcal': 0,
          'isAutoPaused': false,
          'isManuallyPaused': false,
          'activeDurationSeconds': 0,
          'points': 0,
        })
        .catchError((Object error) {
          if (_isMissingDatabaseError(error)) {
            _disableCloudSync(error);
          }
        });
  }

  Future<void> appendPoint({
    required String sessionId,
    required TrackingPoint point,
    required double totalDistanceMeters,
    required double elevationGainMeters,
    required double caloriesKcal,
    required bool isAutoPaused,
    required bool isManuallyPaused,
    required int elapsedSeconds,
    required int points,
  }) async {
    if (!_cloudSyncEnabled) {
      return;
    }
    final sessionRef = _firestore
        .collection('tracking_sessions')
        .doc(sessionId);
    final pointRef = sessionRef.collection('points').doc();

    final batch = _firestore.batch();
    batch.set(pointRef, point.toMap());
    batch.update(sessionRef, {
      'updatedAt': FieldValue.serverTimestamp(),
      'distanceMeters': totalDistanceMeters,
      'elevationGainMeters': elevationGainMeters,
      'caloriesKcal': caloriesKcal,
      'isAutoPaused': isAutoPaused,
      'isManuallyPaused': isManuallyPaused,
      'activeDurationSeconds': elapsedSeconds,
      'status': isManuallyPaused ? 'paused' : 'active',
      'points': points,
    });

    batch.commit().catchError((Object error) {
      if (_isMissingDatabaseError(error)) {
        _disableCloudSync(error);
      }
    });
  }

  Future<void> closeSession({
    required String sessionId,
    required DateTime endedAt,
    required double distanceMeters,
    required double elevationGainMeters,
    required double caloriesKcal,
    required int elapsedSeconds,
    required int points,
  }) async {
    if (!_cloudSyncEnabled) {
      return;
    }
    _firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .update({
          'status': 'stopped',
          'endedAt': endedAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
          'distanceMeters': distanceMeters,
          'elevationGainMeters': elevationGainMeters,
          'caloriesKcal': caloriesKcal,
          'isAutoPaused': false,
          'isManuallyPaused': false,
          'activeDurationSeconds': elapsedSeconds,
          'points': points,
        })
        .catchError((Object error) {
          if (_isMissingDatabaseError(error)) {
            _disableCloudSync(error);
          }
        });
  }

  Future<void> updatePauseState({
    required String sessionId,
    required bool isManuallyPaused,
    required int elapsedSeconds,
  }) async {
    if (!_cloudSyncEnabled) {
      return;
    }
    _firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .update({
          'updatedAt': FieldValue.serverTimestamp(),
          'status': isManuallyPaused ? 'paused' : 'active',
          'isAutoPaused': false,
          'isManuallyPaused': isManuallyPaused,
          'activeDurationSeconds': elapsedSeconds,
        })
        .catchError((Object error) {
          if (_isMissingDatabaseError(error)) {
            _disableCloudSync(error);
          }
        });
  }

  /// Deletes a session owned by [userId], including `points`, `likes`,
  /// `concurrent_runners`, and any `active_runners` broadcast doc.
  Future<void> deleteCompletedSessionForUser({
    required String sessionId,
    required String userId,
  }) async {
    final sessionRef = _firestore.collection('tracking_sessions').doc(sessionId);
    final sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      return;
    }
    final owner = sessionSnap.data()?['userId'] as String?;
    if (owner != userId) {
      throw StateError('You can only delete your own exercises.');
    }

    Future<void> deleteInBatches(
      CollectionReference<Map<String, dynamic>> col,
    ) async {
      while (true) {
        final snap = await col.limit(500).get();
        if (snap.docs.isEmpty) {
          break;
        }
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    await deleteInBatches(sessionRef.collection('points'));
    await deleteInBatches(sessionRef.collection('likes'));
    await deleteInBatches(sessionRef.collection('concurrent_runners'));

    try {
      await _firestore.collection('active_runners').doc(sessionId).delete();
    } catch (_) {
      // No live broadcast doc is fine.
    }

    await sessionRef.delete();
  }
}
