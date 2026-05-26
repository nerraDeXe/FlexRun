import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/create_group_page.dart';
import 'package:fake_strava/groups/group_detail_page.dart';
import 'package:fake_strava/groups/group_repository.dart';
import 'package:fake_strava/groups/widgets/group_timeline_tab.dart';

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
        backgroundColor: kSurface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: const _GroupsPageHeader(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey.shade600,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: "Groups You're In"),
                      Tab(text: 'Pending'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _MyGroupsTab(repo: repo, userId: user.uid),
                    _PendingInvitesTab(repo: repo, userId: user.uid),
                  ],
                ),
              ),
            ],
          ),
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

BoxDecoration _groupGlowCardDecoration({Color accent = kBrandOrange}) {
  return BoxDecoration(
    color: kSurfaceCard,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: accent.withValues(alpha: 0.12),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: accent.withValues(alpha: 0.06),
        blurRadius: 14,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

class _GroupsPageHeader extends StatelessWidget {
  const _GroupsPageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBrandOrange.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Community',
              style: AppTypography.displaySmall.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Icon(
            Icons.groups_rounded,
            color: kBrandOrange,
            size: 32,
          ),
        ],
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
                    Icons.groups_outlined,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Groups Yet',
                    style: AppTypography.headingLarge.copyWith(
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a group to connect with others and share activities.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name = data['name'] as String? ?? 'Unnamed Group';
            final description = data['description'] as String? ?? '';
            final membersCount = (data['memberIds'] as List?)?.length ?? 0;

            return Container(
              decoration: _groupGlowCardDecoration(),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            GroupDetailPage(groupId: doc.id, groupData: data),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [kBrandOrange, kBrandBlack],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: kBrandOrange.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.group, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black.withValues(alpha: 0.88),
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: Colors.black.withValues(alpha: 0.52),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: kBrandOrange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$membersCount member${membersCount == 1 ? '' : 's'}',
                                  style: AppTypography.captionSmall.copyWith(
                                    color: kBrandOrange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: kTextTertiary),
                      ],
                    ),
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
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Pending Invitations',
                    style: AppTypography.headingLarge.copyWith(
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone invites you to a group, it will show up here.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: invites.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final inviteDoc = invites[index];
            final inviteData = inviteDoc.data();
            final invitationId = inviteDoc.id;
            final groupId = inviteData['groupId'] as String?;
            final isProcessing = _processingInviteIds.contains(invitationId);

            if (groupId == null || groupId.isEmpty) {
              return const SizedBox.shrink();
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _groupDocFuture(groupId),
              builder: (context, groupSnapshot) {
                if (groupSnapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    decoration: _groupGlowCardDecoration(accent: Colors.grey),
                    padding: const EdgeInsets.all(20),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                final groupData = groupSnapshot.data?.data();
                final groupName =
                    groupData?['name'] as String? ?? 'Unknown Group';
                final invitedBy = inviteData['invitedBy'] as String? ?? 'Someone';

                return Container(
                  decoration: _groupGlowCardDecoration(accent: kInfo),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: kInfo.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.mail, color: kInfo),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    groupName,
                                    style: AppTypography.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black.withValues(alpha: 0.88),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Invited by $invitedBy',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: Colors.black.withValues(alpha: 0.52),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _respondToInvite(
                                          invitationId: invitationId,
                                          accept: false,
                                        ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _respondToInvite(
                                          invitationId: invitationId,
                                          accept: true,
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: kInfo,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isProcessing
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

