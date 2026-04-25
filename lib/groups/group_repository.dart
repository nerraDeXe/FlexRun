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
