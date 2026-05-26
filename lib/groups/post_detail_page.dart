import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/group_repository.dart';

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
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
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _commentController = TextEditingController();
  String? _replyingToCommentId;
  String? _replyingToUserName;

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    _commentController.clear();
    final replyId = _replyingToCommentId;
    
    setState(() {
      _replyingToCommentId = null;
      _replyingToUserName = null;
    });

    try {
      await GroupRepository().createComment(
        postId: widget.postId,
        authorId: widget.currentUserId,
        text: text,
        replyToId: replyId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting comment: $e')),
        );
      }
    }
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
          postId: widget.postId,
          userId: widget.currentUserId,
        );
        if (context.mounted) {
          Navigator.of(context).pop();
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

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postData = widget.postData;
    final description = postData['description'] as String? ?? '';
    final status = postData['status'] as String? ?? 'completed';
    final scheduledTime = postData['scheduledTime'] as Timestamp?;
    final location = postData['location'] as String?;
    final locationLat = postData['locationLat'] as double?;
    final locationLng = postData['locationLng'] as double?;
    final rsvps = List<String>.from(postData['rsvps'] ?? []);
    final isGoing = rsvps.contains(widget.currentUserId);
    final isUpcoming = status == 'upcoming';
    final isCreator = postData['creatorId'] == widget.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Details'),
        actions: [
          if (isCreator)
            IconButton(
              tooltip: 'Delete post',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmAndDeletePost(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Post Content
                Text(description, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),

                if (isUpcoming && locationLat != null && locationLng != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
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
                  ),

                if (isUpcoming && scheduledTime != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kBrandOrange.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBrandOrange.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, color: kBrandOrange),
                            const SizedBox(width: 12),
                            Text(
                              DateFormat('EEEE, MMMM d @ h:mm a').format(scheduledTime.toDate()),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        if (location != null && location.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.grey),
                              const SizedBox(width: 12),
                              Expanded(child: Text(location, style: const TextStyle(fontSize: 16))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // RSVPs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${rsvps.length} Going', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        onPressed: () {
                          GroupRepository().toggleRsvp(
                            postId: widget.postId,
                            userId: widget.currentUserId,
                            isGoing: !isGoing,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isGoing ? Colors.grey.shade300 : kBrandOrange,
                          foregroundColor: isGoing ? Colors.black : Colors.white,
                        ),
                        icon: Icon(isGoing ? Icons.close : Icons.check),
                        label: Text(isGoing ? 'Cancel RSVP' : 'RSVP'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                
                const Divider(height: 32),
                Text('Comments', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Comments List
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: GroupRepository().getCommentsStream(widget.postId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    final docs = List<DocumentSnapshot<Map<String, dynamic>>>.from(snapshot.data!.docs);
                    
                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text('No comments yet. Be the first to start the discussion!', style: TextStyle(color: Colors.grey)),
                        ),
                      );
                    }

                    // Sort chronologically by createdAt (locally since we removed the Firestore orderBy index)
                    docs.sort((a, b) {
                      final timeA = (a.data()?['createdAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
                      final timeB = (b.data()?['createdAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
                      return timeA.compareTo(timeB);
                    });

                    // Build comment tree
                    final Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> tree = {
                      'root': [],
                    };
                    
                    for (final doc in docs) {
                      final data = doc.data()!;
                      final replyToId = data['replyToId'] as String?;
                      if (replyToId == null) {
                        tree['root']!.add(doc);
                      } else {
                        tree.putIfAbsent(replyToId, () => []).add(doc);
                      }
                    }

                    return Column(
                      children: tree['root']!.map((doc) => _buildCommentNode(doc, tree, 0)).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // Comment Input
          Container(
            padding: const EdgeInsets.all(8.0).copyWith(
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -2))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingToCommentId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, left: 8, right: 8),
                    child: Row(
                      children: [
                        Text('Replying to $_replyingToUserName', style: const TextStyle(fontWeight: FontWeight.bold, color: kBrandOrange)),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() {
                            _replyingToCommentId = null;
                            _replyingToUserName = null;
                          }),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: kBrandOrange),
                      onPressed: _submitComment,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentNode(DocumentSnapshot<Map<String, dynamic>> doc, Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> tree, int depth) {
    final data = doc.data()!;
    final authorId = data['authorId'] as String? ?? 'Unknown';
    final text = data['text'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    
    final replies = tree[doc.id] ?? [];

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: GroupRepository().firestore.collection('users').doc(authorId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data();
        final fallbackUsername = authorId.length >= 6 ? authorId.substring(0, 6) : 'runner';
        final username = userData?['username'] as String? ?? fallbackUsername;
        final displayName = userData?['displayName'] as String? ?? (authorId == widget.currentUserId ? 'You' : '@$username');

        return Padding(
          padding: EdgeInsets.only(left: depth == 0 ? 0.0 : 16.0, bottom: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: kBrandOrange.withValues(alpha: 0.2),
                    child: Text(
                      (displayName.isNotEmpty ? displayName[0] : 'R').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kBrandOrange),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                              if (createdAt != null)
                                Text(
                                  DateFormat.MMMd().add_jm().format(createdAt.toDate()),
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(text, style: const TextStyle(color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40.0, top: 4.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _replyingToCommentId = doc.id;
                      _replyingToUserName = displayName;
                    });
                  },
                  child: const Text('Reply', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              ...replies.map((replyDoc) => _buildCommentNode(replyDoc, tree, depth + 1)),
            ],
          ),
        );
      }
    );
  }
}
