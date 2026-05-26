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

  // --- Group Posts & Comments ---

  Future<String> createPost({
    required String groupId,
    required String creatorId,
    required String description,
    DateTime? scheduledTime,
    String? location,
    double? locationLat,
    double? locationLng,
  }) async {
    final docRef = await _firestore.collection('group_posts').add({
      'groupId': groupId,
      'creatorId': creatorId,
      'description': description.trim(),
      'scheduledTime': scheduledTime != null ? Timestamp.fromDate(scheduledTime) : null,
      'location': location?.trim(),
      'locationLat': locationLat,
      'locationLng': locationLng,
      'createdAt': FieldValue.serverTimestamp(),
      'rsvps': [creatorId], // Creator automatically RSVPs
      'status': scheduledTime != null ? 'upcoming' : 'completed',
    });
    return docRef.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getPostsStream(String groupId) {
    return _firestore
        .collection('group_posts')
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> toggleRsvp({
    required String postId,
    required String userId,
    required bool isGoing,
  }) async {
    final postRef = _firestore.collection('group_posts').doc(postId);
    if (isGoing) {
      await postRef.update({
        'rsvps': FieldValue.arrayUnion([userId]),
      });
    } else {
      await postRef.update({
        'rsvps': FieldValue.arrayRemove([userId]),
      });
    }
  }

  Future<String> createComment({
    required String postId,
    required String authorId,
    required String text,
    String? replyToId,
  }) async {
    final docRef = await _firestore.collection('group_comments').add({
      'postId': postId,
      'authorId': authorId,
      'text': text.trim(),
      'replyToId': replyToId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getCommentsStream(String postId) {
    return _firestore
        .collection('group_comments')
        .where('postId', isEqualTo: postId)
        .snapshots();
  }

  Future<void> deletePost({
    required String postId,
    required String userId,
  }) async {
    final postRef = _firestore.collection('group_posts').doc(postId);
    final postSnap = await postRef.get();
    if (!postSnap.exists) {
      throw StateError('Post not found.');
    }
    final creatorId = postSnap.data()?['creatorId'] as String?;
    if (creatorId != userId) {
      throw StateError('You can only delete your own posts.');
    }

    final commentsQuery = await _firestore
        .collection('group_comments')
        .where('postId', isEqualTo: postId)
        .get();

    final batch = _firestore.batch();
    for (final doc in commentsQuery.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> removeMemberFromGroup({
    required String groupId,
    required String userId,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([userId]),
      'adminIds': FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> assignAdminRole({
    required String groupId,
    required String userId,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'adminIds': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> revokeAdminRole({
    required String groupId,
    required String userId,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'adminIds': FieldValue.arrayRemove([userId]),
    });
  }
}
