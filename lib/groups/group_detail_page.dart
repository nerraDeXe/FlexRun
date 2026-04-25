import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/add_members_page.dart';

class GroupDetailPage extends StatelessWidget {
  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupData,
  });

  final String groupId;
  final Map<String, dynamic> groupData;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isCreator = user != null && groupData['createdBy'] == user.uid;

    final name = groupData['name'] as String? ?? 'Group';
    final description = groupData['description'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddMembersPage(
                      groupId: groupId,
                      currentMemberIds: List<String>.from(groupData['memberIds'] ?? []),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'fakestrava').collection('groups').doc(groupId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading group details'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final currentData = snapshot.data!.data() ?? groupData;
          final currentMemberIds = List<String>.from(currentData['memberIds'] ?? []);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (description.isNotEmpty) ...[
                Text(
                  'About',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
              ],
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Members (${currentMemberIds.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (isCreator)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddMembersPage(
                              groupId: groupId,
                              currentMemberIds: currentMemberIds,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _MembersList(memberIds: currentMemberIds),
              
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 32),
              
              // Future-proofing Placeholder
              Center(
                child: Column(
                  children: [
                    Icon(Icons.feed_outlined, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Group Feed',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Coming Soon!\nYou will be able to share your activities here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MembersList extends StatelessWidget {
  const _MembersList({required this.memberIds});

  final List<String> memberIds;

  @override
  Widget build(BuildContext context) {
    if (memberIds.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: memberIds.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final memberId = memberIds[index];
          
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'fakestrava').collection('users').doc(memberId).snapshots(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const ListTile(
                  leading: CircleAvatar(child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('Loading...'),
                );
              }
              
              final userData = userSnapshot.data!.data();
              if (userData == null) {
                return const ListTile(title: Text('Unknown User'));
              }
              
              final displayName = userData['displayName'] as String? ?? 'Athlete';
              final username = userData['username'] as String? ?? memberId.substring(0, 6);
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: kBrandOrange.withValues(alpha: 0.2),
                  foregroundColor: kBrandOrange,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('@$username'),
              );
            },
          );
        },
      ),
    );
  }
}
