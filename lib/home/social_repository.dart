import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class SocialRepository {
  SocialRepository({FirebaseFirestore? firestore})
    : _firestore =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          );

  final FirebaseFirestore _firestore;

  FirebaseFirestore get firestore => _firestore;

  String _normalizeUsername(String source) {
    final lower = source.trim().toLowerCase();
    final sanitized = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    if (trimmed.isEmpty) {
      return 'runner';
    }
    return trimmed;
  }

  Future<void> ensureUserProfile({required User user}) async {
    final displayName =
        (user.displayName != null && user.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Runner');
    final ref = _firestore.collection('users').doc(user.uid);
    final existing = await ref.get();
    final data = existing.data();
    final existingUsername = data?['username'] as String?;
    final username =
        (existingUsername != null && existingUsername.trim().isNotEmpty)
        ? existingUsername.trim()
        : _normalizeUsername(displayName);

    await ref.set({
      'displayName': displayName,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> followUserByUsername({
    required String currentUserId,
    required String username,
  }) async {
    final normalized = _normalizeUsername(username);
    final match = await _firestore
        .collection('users')
        .where('usernameLower', isEqualTo: normalized)
        .limit(1)
        .get();

    if (match.docs.isEmpty) {
      throw StateError('No user found with username "$normalized".');
    }

    final targetDoc = match.docs.first;
    if (targetDoc.id == currentUserId) {
      throw StateError('You cannot follow yourself.');
    }

    final targetData = targetDoc.data();
    final targetUsername =
        (targetData['username'] as String?) ?? targetDoc.id.substring(0, 6);

    await _firestore.collection('users').doc(currentUserId).set({
      'followingIds': FieldValue.arrayUnion(<String>[targetDoc.id]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return targetUsername;
  }

  Future<void> unfollowUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    await _firestore.collection('users').doc(currentUserId).set({
      'followingIds': FieldValue.arrayRemove(<String>[targetUserId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> searchUsersByPrefix({
    required String prefix,
  }) async {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final query = await _firestore
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: normalized)
        .where('usernameLower', isLessThan: '$normalized\uf8ff')
        .limit(20)
        .get();

    return query.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> toggleLike({
    required String sessionId,
    required String currentUserId,
    required bool like,
    required String displayName,
  }) async {
    final ref = _firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('likes')
        .doc(currentUserId);

    if (like) {
      await ref.set({
        'userId': currentUserId,
        'displayName': displayName,
        'likedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    await ref.delete();
  }
}
