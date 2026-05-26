import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/add_members_page.dart';
import 'package:fake_strava/groups/create_post_page.dart';
import 'package:fake_strava/groups/group_repository.dart';
import 'package:fake_strava/groups/widgets/group_timeline_tab.dart';

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupData,
  });

  final String groupId;
  final Map<String, dynamic> groupData;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isCreator = user != null && widget.groupData['createdBy'] == user.uid;

    final name = widget.groupData['name'] as String? ?? 'Group';
    final description = widget.groupData['description'] as String? ?? '';
    final currentUserId = user?.uid ?? '';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
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
                        groupId: widget.groupId,
                        currentMemberIds: List<String>.from(
                          widget.groupData['memberIds'] ?? [],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
          bottom: const TabBar(
            indicatorColor: kBrandOrange,
            labelColor: kBrandOrange,
            unselectedLabelColor: Colors.grey,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Timeline'),
              Tab(text: 'Your Posts'),
              Tab(text: 'Members'),
              Tab(text: 'About'),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          ).collection('groups').doc(widget.groupId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Error loading group details'));
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final currentData = snapshot.data!.data() ?? widget.groupData;
            final currentMemberIds = List<String>.from(
              currentData['memberIds'] ?? [],
            );
            final createdBy = currentData['createdBy'] as String? ?? '';
            final adminIds = List<String>.from(
              currentData['adminIds'] ?? [],
            );

            return TabBarView(
              children: [
                // Timeline Tab
                GroupTimelineTab(
                  groupId: widget.groupId,
                  currentUserId: currentUserId,
                ),

                // Your Posts Tab
                _YourPostsTab(groupId: widget.groupId, userId: currentUserId),

                // Members Tab
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Members (${currentMemberIds.length})',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (isCreator)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AddMembersPage(
                                    groupId: widget.groupId,
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
                    const SizedBox(height: 16),
                    _MembersList(
                      groupId: widget.groupId,
                      memberIds: currentMemberIds,
                      currentUserId: currentUserId,
                      createdBy: createdBy,
                      adminIds: adminIds,
                    ),
                  ],
                ),

                // About Tab
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'About',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      description.isEmpty
                          ? 'No description provided.'
                          : description,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreatePostPage(
                  groupId: widget.groupId,
                  creatorId: currentUserId,
                ),
              ),
            );
          },
          backgroundColor: kBrandOrange,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}

class _MembersList extends StatelessWidget {
  const _MembersList({
    required this.groupId,
    required this.memberIds,
    required this.currentUserId,
    required this.createdBy,
    required this.adminIds,
  });

  final String groupId;
  final List<String> memberIds;
  final String currentUserId;
  final String createdBy;
  final List<String> adminIds;

  Future<bool> _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmText,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(confirmText),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (memberIds.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: memberIds.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.grey.shade100,
        ),
        itemBuilder: (context, index) {
          final memberId = memberIds[index];

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instanceFor(
              app: Firebase.app(),
              databaseId: 'fakestrava',
            ).collection('users').doc(memberId).snapshots(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const ListTile(
                  leading: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  title: Text('Loading...'),
                );
              }

              final userData = userSnapshot.data!.data();
              if (userData == null) {
                return const ListTile(title: Text('Unknown User'));
              }

              final displayName =
                  userData['displayName'] as String? ?? 'Athlete';
              final username =
                  userData['username'] as String? ?? memberId.substring(0, 6);

              final isTargetOwner = memberId == createdBy;
              final isTargetAdmin = adminIds.contains(memberId);
              final isCurrentUserOwner = currentUserId == createdBy;
              final isCurrentUserAdmin = adminIds.contains(currentUserId);

              // Determine if current user can manage the target user
              final canManage = (isCurrentUserOwner || isCurrentUserAdmin) && 
                                !isTargetOwner && 
                                memberId != currentUserId;

              Widget? trailingWidget;

              if (canManage) {
                final List<PopupMenuEntry<String>> menuItems = [];

                if (isCurrentUserOwner) {
                  if (isTargetAdmin) {
                    menuItems.add(
                      const PopupMenuItem<String>(
                        value: 'revoke_admin',
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
                            SizedBox(width: 8),
                            Text('Revoke Admin'),
                          ],
                        ),
                      ),
                    );
                  } else {
                    menuItems.add(
                      const PopupMenuItem<String>(
                        value: 'make_admin',
                        child: Row(
                          children: [
                            Icon(Icons.shield, color: Colors.green, size: 20),
                            SizedBox(width: 8),
                            Text('Make Admin'),
                          ],
                        ),
                      ),
                    );
                  }
                }

                // Both owner and admin can remove member, EXCEPT other admins and the owner.
                if (!isTargetAdmin && !isTargetOwner) {
                  menuItems.add(
                    const PopupMenuItem<String>(
                      value: 'remove_member',
                      child: Row(
                        children: [
                          Icon(Icons.person_remove, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Remove Member', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  );
                }

                if (menuItems.isNotEmpty) {
                  trailingWidget = PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                    onSelected: (value) async {
                      if (value == 'make_admin') {
                        final confirm = await _showConfirmationDialog(
                          context,
                          title: 'Promote to Admin',
                          content: 'Are you sure you want to make $displayName an admin of this group?',
                          confirmText: 'Promote',
                        );
                        if (confirm) {
                          await GroupRepository().assignAdminRole(
                            groupId: groupId,
                            userId: memberId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$displayName is now an admin.')),
                            );
                          }
                        }
                      } else if (value == 'revoke_admin') {
                        final confirm = await _showConfirmationDialog(
                          context,
                          title: 'Revoke Admin Privilege',
                          content: 'Are you sure you want to remove admin privileges from $displayName?',
                          confirmText: 'Revoke',
                        );
                        if (confirm) {
                          await GroupRepository().revokeAdminRole(
                            groupId: groupId,
                            userId: memberId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$displayName is no longer an admin.')),
                            );
                          }
                        }
                      } else if (value == 'remove_member') {
                        final confirm = await _showConfirmationDialog(
                          context,
                          title: 'Remove Member',
                          content: 'Are you sure you want to remove $displayName from the group?',
                          confirmText: 'Remove',
                        );
                        if (confirm) {
                          await GroupRepository().removeMemberFromGroup(
                            groupId: groupId,
                            userId: memberId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$displayName has been removed.')),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (context) => menuItems,
                  );
                }
              }

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isTargetOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFFEDD5),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Owner',
                          style: TextStyle(
                            color: Color(0xFFEA580C),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else if (isTargetAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFDBEAFE),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  '@$username',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                  ),
                ),
                trailing: trailingWidget,
              );
            },
          );
        },
      ),
    );
  }
}

class _YourPostsTab extends StatelessWidget {
  const _YourPostsTab({required this.groupId, required this.userId});

  final String groupId;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupRepository().firestore
          .collection('group_posts')
          .where('groupId', isEqualTo: groupId)
          .where('creatorId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading posts: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList();

        // Sort locally by createdAt descending to avoid composite index requirement
        docs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.post_add_outlined,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Posts Yet',
                    style: AppTypography.headingLarge.copyWith(
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Any posts you make in this group will show up here.',
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            return GroupPostCard(
              postId: doc.id,
              postData: data,
              currentUserId: userId,
              groupId: groupId,
            );
          },
        );
      },
    );
  }
}
