import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/home/home_page.dart';

class SearchedUserProfilePage extends StatefulWidget {
  const SearchedUserProfilePage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.username,
  });

  final String userId;
  final String displayName;
  final String username;

  @override
  State<SearchedUserProfilePage> createState() => _SearchedUserProfilePageState();
}

class _SearchedUserProfilePageState extends State<SearchedUserProfilePage> {
  final SocialRepository _socialRepository = SocialRepository();
  bool _isLoadingFollow = false;
  
  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    setState(() => _isLoadingFollow = true);
    
    try {
      if (currentlyFollowing) {
        await _socialRepository.unfollowUser(
          currentUserId: currentUser.uid,
          targetUserId: widget.userId,
        );
      } else {
        await _socialRepository.followUserByUsername(
          currentUserId: currentUser.uid,
          username: widget.username,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update follow status: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFollow = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final isMe = currentUser.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _socialRepository.firestore.collection('users').doc(currentUser.uid).snapshots(),
        builder: (context, currentUserSnapshot) {
          final currentUserData = currentUserSnapshot.data?.data() ?? const <String, dynamic>{};
          final followingIds = ((currentUserData['followingIds'] as List?) ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false);
          final isFollowing = followingIds.contains(widget.userId);

          return Column(
            children: [
              _buildProfileHeader(isMe: isMe, isFollowing: isFollowing),
              const Divider(height: 1),
              Expanded(
                child: _buildActivityFeed(currentUser.uid, currentUserData['displayName'] ?? 'Athlete'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader({required bool isMe, required bool isFollowing}) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: kBrandOrange,
            foregroundColor: Colors.white,
            child: Text(
              widget.displayName.isNotEmpty ? widget.displayName[0].toUpperCase() : 'A',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.displayName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '@${widget.username}',
            style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (!isMe)
            SizedBox(
              width: 150,
              height: 40,
              child: FilledButton(
                onPressed: _isLoadingFollow ? null : () => _toggleFollow(isFollowing),
                style: FilledButton.styleFrom(
                  backgroundColor: isFollowing ? Colors.grey[200] : kBrandOrange,
                  foregroundColor: isFollowing ? Colors.black87 : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isLoadingFollow
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isFollowing ? 'Unfollow' : 'Follow',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityFeed(String currentUserId, String currentDisplayName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _socialRepository.firestore
          .collection('tracking_sessions')
          .where('userId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'stopped')
          .orderBy('startedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, feedSnapshot) {
        if (feedSnapshot.hasError) {
          return Center(child: Text('Unable to load activities: ${feedSnapshot.error}'));
        }
        if (!feedSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final feed = feedSnapshot.data!.docs;

        if (feed.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No activity yet.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          itemCount: feed.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = feed[index];
            return ActivityFeedCard(
              sessionId: doc.id,
              data: doc.data(),
              currentUserId: currentUserId,
              currentDisplayName: currentDisplayName,
              firestore: _socialRepository.firestore,
              socialRepository: _socialRepository,
              durationLabel: _durationLabel,
            );
          },
        );
      },
    );
  }
}
