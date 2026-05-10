import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/create_group_page.dart';
import 'package:fake_strava/groups/group_detail_page.dart';
import 'package:fake_strava/groups/group_repository.dart';

class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final repo = GroupRepository();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Groups'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: "Groups You're In"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PendingInvitesTab(repo: repo, userId: user.uid),
            _MyGroupsTab(repo: repo, userId: user.uid),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CreateGroupPage()));
          },
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text(
            'Create Group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _MyGroupsTab extends StatelessWidget {
  const _MyGroupsTab({required this.repo, required this.userId});

  final GroupRepository repo;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: repo.getUserGroupsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading groups: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.group_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Groups Yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a group to connect with others and share activities.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name = data['name'] as String? ?? 'Unnamed Group';
            final membersCount = (data['memberIds'] as List?)?.length ?? 0;

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          GroupDetailPage(groupId: doc.id, groupData: data),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: kBrandOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.group, color: kBrandOrange),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$membersCount member${membersCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PendingInvitesTab extends StatefulWidget {
  const _PendingInvitesTab({required this.repo, required this.userId});

  final GroupRepository repo;
  final String userId;

  @override
  State<_PendingInvitesTab> createState() => _PendingInvitesTabState();
}

class _PendingInvitesTabState extends State<_PendingInvitesTab> {
  final Set<String> _processingInviteIds = <String>{};
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _groupFutures =
      {};

  Future<DocumentSnapshot<Map<String, dynamic>>> _groupDocFuture(String groupId) {
    return _groupFutures.putIfAbsent(
      groupId,
      () => widget.repo.firestore.collection('groups').doc(groupId).get(),
    );
  }

  Future<void> _respondToInvite({
    required String invitationId,
    required bool accept,
  }) async {
    if (_processingInviteIds.contains(invitationId)) return;
    setState(() => _processingInviteIds.add(invitationId));
    try {
      if (accept) {
        await widget.repo.acceptInvitation(
          invitationId: invitationId,
          userId: widget.userId,
        );
      } else {
        await widget.repo.declineInvitation(
          invitationId: invitationId,
          userId: widget.userId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Failed to accept invite: $e' : 'Failed to decline invite: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingInviteIds.remove(invitationId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.repo.getPendingInvitesStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load invitations.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final invites = snapshot.data!.docs;

        if (invites.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Pending Invitations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone invites you to a group, it will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invites.length,
          itemBuilder: (context, index) {
            final inviteDoc = invites[index];
            final inviteData = inviteDoc.data();
            final invitationId = inviteDoc.id;
            final groupId = inviteData['groupId'] as String?;
            final isProcessing = _processingInviteIds.contains(invitationId);

            if (groupId == null || groupId.isEmpty) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _groupDocFuture(groupId),
                builder: (context, groupSnapshot) {
                  if (groupSnapshot.connectionState == ConnectionState.waiting) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  final groupData = groupSnapshot.data?.data();
                  final groupName =
                      groupData?['name'] as String? ?? 'Unknown Group';

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _respondToInvite(
                                          invitationId: invitationId,
                                          accept: false,
                                        ),
                                child: const Text('Decline'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _respondToInvite(
                                          invitationId: invitationId,
                                          accept: true,
                                        ),
                                child: isProcessing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Accept'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
