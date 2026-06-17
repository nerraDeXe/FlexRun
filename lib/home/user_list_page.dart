import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/home/searched_user_profile_page.dart';

class UserListPage extends StatelessWidget {
  const UserListPage({
    super.key,
    required this.title,
    this.userIds,
    this.query,
  }) : assert(userIds != null || query != null,
            'Must provide either userIds or a query');

  final String title;
  final List<String>? userIds;
  final Query<Map<String, dynamic>>? query;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: query != null ? _buildQueryList() : _buildIdList(),
    );
  }

  Widget _buildQueryList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query!.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            return _UserListItem(userId: doc.id, userData: doc.data());
          },
        );
      },
    );
  }

  Widget _buildIdList() {
    if (userIds!.isEmpty) {
      return const Center(child: Text('No users found.'));
    }

    return ListView.builder(
      itemCount: userIds!.length,
      itemBuilder: (context, index) {
        final userId = userIds![index];
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          ).collection('users').doc(userId).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const ListTile(
                leading: CircleAvatar(child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text('Loading...'),
              );
            }

            final data = snapshot.data!.data();
            if (data == null) {
              return const SizedBox.shrink();
            }

            return _UserListItem(userId: userId, userData: data);
          },
        );
      },
    );
  }
}

class _UserListItem extends StatelessWidget {
  const _UserListItem({required this.userId, required this.userData});

  final String userId;
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final displayName = userData['displayName'] as String? ?? 'Athlete';
    final username = userData['username'] as String? ?? userId.substring(0, 6);

    return ListTile(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchedUserProfilePage(
              userId: userId,
              displayName: displayName,
              username: username,
            ),
          ),
        );
      },
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF97316), Color(0xFFEA580C)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            (displayName.isNotEmpty ? displayName[0] : 'A').toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        '@$username',
        style: const TextStyle(
          color: Color(0xFF64748B),
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
    );
  }
}
