import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'user_metrics.dart';

/// Repository for managing user metrics in Firestore
class UserMetricsRepository {
  final FirebaseFirestore _firestore;

  UserMetricsRepository({FirebaseFirestore? firestore})
    : _firestore =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          );

  /// Get user metrics for a specific user
  Future<UserMetrics?> getUserMetrics(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null || !data.containsKey('metrics')) {
        return null;
      }

      return UserMetrics.fromMap(data['metrics'] as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  /// Save user metrics for a specific user
  Future<void> saveUserMetrics(String userId, UserMetrics metrics) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'metrics': metrics.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// Stream user metrics for real-time updates
  Stream<UserMetrics?> watchUserMetrics(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null || !data.containsKey('metrics')) {
        return null;
      }

      return UserMetrics.fromMap(data['metrics'] as Map<String, dynamic>);
    });
  }
}
