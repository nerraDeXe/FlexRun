import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/group_repository.dart';
import 'package:fake_strava/groups/post_detail_page.dart';

class GroupTimelineTab extends StatelessWidget {
  const GroupTimelineTab({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  final String groupId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupRepository().getPostsStream(groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading timeline'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No posts yet. Be the first to post!',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            return GroupPostCard(
              postId: doc.id,
              postData: data,
              currentUserId: currentUserId,
              groupId: groupId,
            );
          },
        );
      },
    );
  }
}

class GroupPostCard extends StatelessWidget {
  const GroupPostCard({
    super.key,
    required this.postId,
    required this.postData,
    required this.currentUserId,
    required this.groupId,
  });

  final String postId;
  final Map<String, dynamic> postData;
  final String currentUserId;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final creatorId = postData['creatorId'] as String? ?? '';
    final description = postData['description'] as String? ?? '';
    final status = postData['status'] as String? ?? 'completed';
    final scheduledTime = postData['scheduledTime'] as Timestamp?;
    final location = postData['location'] as String?;
    final locationLat = postData['locationLat'] as double?;
    final locationLng = postData['locationLng'] as double?;
    final rsvps = List<String>.from(postData['rsvps'] ?? []);
    final isGoing = rsvps.contains(currentUserId);
    final createdAt = postData['createdAt'] as Timestamp?;

    final isUpcoming = status == 'upcoming';

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
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostDetailPage(
                  postId: postId,
                  postData: postData,
                  currentUserId: currentUserId,
                  groupId: groupId,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: GroupRepository().firestore.collection('users').doc(creatorId).snapshots(),
                  builder: (context, userSnapshot) {
                    final userData = userSnapshot.data?.data();
                    final fallbackUsername = creatorId.length >= 6 ? creatorId.substring(0, 6) : 'runner';
                    final username = userData?['username'] as String? ?? fallbackUsername;
                    final displayName = userData?['displayName'] as String? ?? (creatorId == currentUserId ? 'You' : '@$username');

                    return Row(
                      children: [
                        // Premium avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF97316).withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              (displayName.isNotEmpty ? displayName[0] : 'R').toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // User info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      createdAt != null
                                          ? DateFormat.yMMMd().add_jm().format(createdAt.toDate())
                                          : 'Unknown time',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (isUpcoming) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: kBrandOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Upcoming',
                              style: TextStyle(
                                color: kBrandOrange,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (creatorId == currentUserId)
                          IconButton(
                            tooltip: 'Delete post',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: Color(0xFF94A3B8),
                            ),
                            onPressed: () => _confirmAndDeletePost(context),
                          ),
                      ],
                    );
                  }
                ),
              ),

              // Description
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  description,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B)),
                ),
              ),

              // Map Preview for Upcoming Run
              if (isUpcoming && locationLat != null && locationLng != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(locationLat, locationLng),
                        initialZoom: 14.0,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: kMapThemeRasterHdPreview.urlTemplate,
                          subdomains: kMapThemeRasterHdPreview.subdomains,
                          userAgentPackageName: 'com.company.fakestrava',
                          retinaMode: RetinaMode.isHighDensity(context),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(locationLat, locationLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin, color: kBrandOrange, size: 40),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // Upcoming Run Details (Text)
              if (isUpcoming && scheduledTime != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: kBrandOrange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, MMM d @ h:mm a').format(scheduledTime.toDate()),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                        if (location != null && location.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  location,
                                  style: const TextStyle(color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Footer (RSVP & Comments)
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      if (isUpcoming)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              GroupRepository().toggleRsvp(
                                postId: postId,
                                userId: currentUserId,
                                isGoing: !isGoing,
                              );
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isGoing ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isGoing ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                                    size: 18,
                                    color: isGoing ? kBrandOrange : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      isGoing ? 'Going (${rsvps.length})' : 'RSVP (${rsvps.length})',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isGoing ? kBrandOrange : const Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      StreamBuilder<QuerySnapshot>(
                        stream: GroupRepository().getCommentsStream(postId),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.docs.length ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Text(
                                  '$count Comments',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeletePost(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'Delete post?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        content: const Text(
          'Permanently remove this post and all its comments?',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      try {
        await GroupRepository().deletePost(
          postId: postId,
          userId: currentUserId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete post: $e')),
          );
        }
      }
    }
  }
}
