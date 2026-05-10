import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class GroupRepository {
  GroupRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ??
            FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'fakestrava',
            );

  final FirebaseFirestore _firestore;

  FirebaseFirestore get firestore => _firestore;

  Future<String> createGroup({
    required String name,
    required String description,
    required String creatorId,
  }) async {
    final docRef = await _firestore.collection('groups').add({
      'name': name.trim(),
      'description': description.trim(),
      'createdBy': creatorId,
      'createdAt': FieldValue.serverTimestamp(),
      'memberIds': [creatorId],
    });
    return docRef.id;
  }

  Future<void> addMemberToGroup({
    required String groupId,
    required String userId,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> inviteUserToGroup({
    required String groupId,
    required String invitedBy,
    required String inviteeId,
  }) async {
    final existingInvite = await _firestore
        .collection('groupInvitations')
        .where('groupId', isEqualTo: groupId)
        .where('inviteeId', isEqualTo: inviteeId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existingInvite.docs.isNotEmpty) {
      throw StateError('User already has a pending invitation.');
    }

    await _firestore.collection('groupInvitations').add({
      'groupId': groupId,
      'inviteeId': inviteeId,
      'invitedBy': invitedBy,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingInvitesStream(
    String userId,
  ) {
    return _firestore
        .collection('groupInvitations')
        .where('inviteeId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> acceptInvitation({
    required String invitationId,
    required String userId,
  }) async {
    final invitationRef = _firestore
        .collection('groupInvitations')
        .doc(invitationId);

    await _firestore.runTransaction((transaction) async {
      final invitationSnapshot = await transaction.get(invitationRef);
      final invitation = invitationSnapshot.data();
      if (!invitationSnapshot.exists || invitation == null) {
        throw StateError('Invitation not found.');
      }
      if (invitation['inviteeId'] != userId) {
        throw StateError('Invitation does not belong to this user.');
      }
      if (invitation['status'] != 'pending') {
        throw StateError('Invitation has already been handled.');
      }

      final groupId = invitation['groupId'] as String?;
      if (groupId == null || groupId.isEmpty) {
        throw StateError('Invitation has no group.');
      }

      final groupRef = _firestore.collection('groups').doc(groupId);
      transaction.update(groupRef, {
        'memberIds': FieldValue.arrayUnion([userId]),
      });
      transaction.update(invitationRef, {
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> declineInvitation({
    required String invitationId,
    required String userId,
  }) async {
    final invitationRef = _firestore
        .collection('groupInvitations')
        .doc(invitationId);

    await _firestore.runTransaction((transaction) async {
      final invitationSnapshot = await transaction.get(invitationRef);
      final invitation = invitationSnapshot.data();
      if (!invitationSnapshot.exists || invitation == null) {
        throw StateError('Invitation not found.');
      }
      if (invitation['inviteeId'] != userId) {
        throw StateError('Invitation does not belong to this user.');
      }
      if (invitation['status'] != 'pending') {
        throw StateError('Invitation has already been handled.');
      }

      transaction.update(invitationRef, {
        'status': 'declined',
        'respondedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getUserGroupsStream(String userId) {
    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
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
}
