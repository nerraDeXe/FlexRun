import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/groups/groups_page.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/home/searched_user_profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SocialRepository _socialRepository = SocialRepository();
  final TextEditingController _usernameController = TextEditingController();
  
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ensureProfile();
    _usernameController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onSearchChanged);
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _ensureProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _socialRepository.ensureUserProfile(user: user);
    } catch (_) {}
  }

  void _onSearchChanged() {
    final query = _usernameController.text.trim();
    if (_searchQuery == query) return;
    
    setState(() {
      _searchQuery = query;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _socialRepository.searchUsersByPrefix(prefix: query);
      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _executeSearch() {
    FocusScope.of(context).unfocus();
  }

  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const Center(child: Text('Firebase is not ready yet.'));
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Please sign in to see Home feed.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _socialRepository.firestore
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, currentUserSnapshot) {
        if (!currentUserSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData =
            currentUserSnapshot.data?.data() ?? const <String, dynamic>{};
        final followingIds =
            ((userData['followingIds'] as List?) ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false);
        final username =
            (userData['username'] as String?)?.trim().isNotEmpty == true
            ? (userData['username'] as String)
            : currentUser.uid.substring(0, 6);
        final displayName =
            (userData['displayName'] as String?)?.trim().isNotEmpty == true
            ? (userData['displayName'] as String)
            : 'Athlete';

        final allowedUsers = <String>{currentUser.uid, ...followingIds};

        return Column(
          children: [
            _buildHeaderSection(
              context: context,
              displayName: displayName,
              username: username,
              followingCount: followingIds.length,
            ),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults()
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _socialRepository.firestore
                          .collection('tracking_sessions')
                          .orderBy('startedAt', descending: true)
                          .limit(150)
                          .snapshots(),
                      builder: (context, feedSnapshot) {
                        if (feedSnapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Unable to load activity feed.\n\n${feedSnapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        if (!feedSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final allDocs = feedSnapshot.data!.docs;
                        final feed = allDocs
                            .where((doc) {
                              final data = doc.data();
                              final uid = data['userId'] as String?;
                              final status = (data['status'] as String?) ?? '';
                              if (uid == null) {
                                return false;
                              }
                              return allowedUsers.contains(uid) &&
                                  status == 'stopped';
                            })
                            .toList(growable: false);

                        if (feed.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No activity yet.\nStart a workout or follow more users to fill your Home feed.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                          itemCount: feed.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final doc = feed[index];
                            return ActivityFeedCard(
                              sessionId: doc.id,
                              data: doc.data(),
                              currentUserId: currentUser.uid,
                              currentDisplayName: widget.displayName,
                              firestore: _socialRepository.firestore,
                              socialRepository: _socialRepository,
                              durationLabel: _durationLabel,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No users found.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final id = user['id'] as String;
        final displayName = user['displayName'] as String? ?? 'Athlete';
        final username = user['username'] as String? ?? id.substring(0, 6);

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: kBrandOrange,
              foregroundColor: Colors.white,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('@$username'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to the SearchedUserProfilePage
              // We'll pass the necessary data
              importSearchedUserProfilePageAndNavigate(context, id, displayName, username);
            },
          ),
        );
      },
    );
  }

  void importSearchedUserProfilePageAndNavigate(
      BuildContext context, String id, String displayName, String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchedUserProfilePage(
          userId: id,
          displayName: displayName,
          username: username,
        ),
      ),
    );
  }

  Widget _buildHeaderSection({
    required BuildContext context,
    required String displayName,
    required String username,
    required int followingCount,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBrandOrange.withValues(alpha: 0.08),
            kBrandOrange.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kBrandOrange,
                            kBrandOrange.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          displayName.isEmpty
                              ? 'A'
                              : displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '@$username',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          'Following $followingCount',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const GroupsPage()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group, size: 14, color: Colors.black54),
                              SizedBox(width: 4),
                              Text(
                                'My Groups',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _executeSearch(),
                    decoration: InputDecoration(
                      hintText: 'Search users',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _usernameController.clear();
                                _executeSearch();
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: _executeSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text(
                      'Search',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandOrange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityFeedCard extends StatelessWidget {
  const ActivityFeedCard({
    required this.sessionId,
    required this.data,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.firestore,
    required this.socialRepository,
    required this.durationLabel,
  });

  final String sessionId;
  final Map<String, dynamic> data;
  final String currentUserId;
  final String currentDisplayName;
  final FirebaseFirestore firestore;
  final SocialRepository socialRepository;
  final String Function(int seconds) durationLabel;

  @override
  Widget build(BuildContext context) {
    final actorId = data['userId'] as String?;
    final isMine = actorId == currentUserId;
    final distanceKm =
        ((data['distanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
    final calories = (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
    final elevation = (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (data['activeDurationSeconds'] as num?)?.toInt() ?? 0;
    final pace = durationSeconds > 0 && distanceKm > 0
        ? (durationSeconds / 60) / distanceKm
        : 0.0;

    final startedAt = DateTime.tryParse(data['startedAt'] as String? ?? '');
    final startedLabel = startedAt == null
        ? 'Unknown time'
        : '${startedAt.toLocal().year}-${startedAt.toLocal().month.toString().padLeft(2, '0')}-${startedAt.toLocal().day.toString().padLeft(2, '0')} ${startedAt.toLocal().hour.toString().padLeft(2, '0')}:${startedAt.toLocal().minute.toString().padLeft(2, '0')}';

    final likesCollection = firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('likes');

    final fallbackUsername =
        (data['username'] as String?)?.trim().isNotEmpty == true
        ? (data['username'] as String)
        : (actorId != null && actorId.length >= 6
              ? actorId.substring(0, 6)
              : 'runner');
    final fallbackDisplayName =
        (data['userDisplayName'] as String?)?.trim().isNotEmpty == true
        ? (data['userDisplayName'] as String)
        : null;

    if (actorId == null) {
      return _buildFeedCard(
        context: context,
        actorUsername: fallbackUsername,
        actorDisplayName: fallbackDisplayName,
        isMine: isMine,
        startedLabel: startedLabel,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        pace: pace,
        calories: calories,
        elevation: elevation,
        likesCollection: likesCollection,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('users').doc(actorId).snapshots(),
      builder: (context, userSnapshot) {
        final profileData = userSnapshot.data?.data();
        final profileUsername =
            (profileData?['username'] as String?)?.trim().isNotEmpty == true
            ? (profileData?['username'] as String)
            : fallbackUsername;
        final profileDisplayName =
            (profileData?['displayName'] as String?)?.trim().isNotEmpty == true
            ? (profileData?['displayName'] as String)
            : fallbackDisplayName;

        return _buildFeedCard(
          context: context,
          actorUsername: profileUsername,
          actorDisplayName: profileDisplayName,
          isMine: isMine,
          startedLabel: startedLabel,
          distanceKm: distanceKm,
          durationSeconds: durationSeconds,
          pace: pace,
          calories: calories,
          elevation: elevation,
          likesCollection: likesCollection,
        );
      },
    );
  }

  Widget _buildFeedCard({
    required BuildContext context,
    required String actorUsername,
    required String? actorDisplayName,
    required bool isMine,
    required String startedLabel,
    required double distanceKm,
    required int durationSeconds,
    required double pace,
    required double calories,
    required double elevation,
    required CollectionReference<Map<String, dynamic>> likesCollection,
  }) {
    final title = isMine ? 'You' : '@$actorUsername';
    final subtitle = actorDisplayName != null && actorDisplayName.isNotEmpty
        ? '$actorDisplayName · $startedLabel'
        : startedLabel;

    return Material(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _HomeActivityDetailPage(
                    firestore: firestore,
                    sessionId: sessionId,
                    sessionData: data,
                    actorTitle: title,
                  ),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.white.withValues(alpha: 0.95)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                kBrandOrange,
                                kBrandOrange.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              (actorUsername.isNotEmpty
                                      ? actorUsername[0]
                                      : 'R')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.arrow_outward,
                            color: Colors.black54,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(
                            Icons.route,
                            '${distanceKm.toStringAsFixed(2)} km',
                          ),
                          _pill(
                            Icons.timer_outlined,
                            durationLabel(durationSeconds),
                          ),
                          _pill(
                            Icons.speed,
                            pace > 0
                                ? '${pace.toStringAsFixed(2)} min/km'
                                : '-- min/km',
                          ),
                          _pill(
                            Icons.local_fire_department,
                            '${calories.toStringAsFixed(0)} kcal',
                          ),
                          _pill(
                            Icons.terrain,
                            '+${elevation.toStringAsFixed(0)} m',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: likesCollection.snapshots(),
                      builder: (context, likeSnapshot) {
                        final likes =
                            likeSnapshot.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[];
                        final likeCount = likes.length;
                        final liked = likes.any(
                          (doc) => doc.id == currentUserId,
                        );
                        return Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: liked
                                    ? Colors.redAccent.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: isMine
                                        ? null
                                        : () async {
                                            await socialRepository.toggleLike(
                                              sessionId: sessionId,
                                              currentUserId: currentUserId,
                                              like: !liked,
                                              displayName: currentDisplayName,
                                            );
                                          },
                                    child: Icon(
                                      liked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: liked
                                          ? Colors.redAccent
                                          : Colors.black54,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$likeCount ${likeCount == 1 ? 'like' : 'likes'}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: kBrandOrange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: kBrandOrange,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Your activity',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.8),
            Colors.white.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kBrandOrange),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActivityDetailPage extends StatelessWidget {
  const _HomeActivityDetailPage({
    required this.firestore,
    required this.sessionId,
    required this.sessionData,
    required this.actorTitle,
  });

  final FirebaseFirestore firestore;
  final String sessionId;
  final Map<String, dynamic> sessionData;
  final String actorTitle;

  String _formatDuration(DateTime? startedAt, DateTime? endedAt, int seconds) {
    Duration? elapsed;
    if (seconds > 0) {
      elapsed = Duration(seconds: seconds);
    } else if (startedAt != null && endedAt != null) {
      elapsed = endedAt.difference(startedAt);
    }
    if (elapsed == null) {
      return '--:--:--';
    }
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = DateTime.tryParse(
      sessionData['startedAt'] as String? ?? '',
    );
    final endedAt = DateTime.tryParse(sessionData['endedAt'] as String? ?? '');
    final distanceKm =
        ((sessionData['distanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
    final calories = (sessionData['caloriesKcal'] as num?)?.toDouble() ?? 0;
    final elevation =
        (sessionData['elevationGainMeters'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (sessionData['activeDurationSeconds'] as num?)?.toInt() ??
        ((startedAt != null && endedAt != null)
            ? endedAt.difference(startedAt).inSeconds
            : 0);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          '$actorTitle Activity',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('tracking_sessions')
            .doc(sessionId)
            .collection('points')
            .orderBy('timestamp')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Unable to load route map.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final points = snapshot.data!.docs
              .map((doc) {
                final data = doc.data();
                final lat = (data['latitude'] as num?)?.toDouble();
                final lon = (data['longitude'] as num?)?.toDouble();
                if (lat == null || lon == null) {
                  return null;
                }
                return LatLng(lat, lon);
              })
              .whereType<LatLng>()
              .toList(growable: false);

          final center = points.isNotEmpty
              ? points.first
              : const LatLng(3.1390, 101.6869);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 280,
                    child: points.isEmpty
                        ? Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: Text(
                                'No route points available for this activity.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : FlutterMap(
                            options: MapOptions(
                              initialCenter: center,
                              initialZoom: 15,
                              initialCameraFit: points.length >= 2
                                  ? CameraFit.bounds(
                                      bounds: LatLngBounds.fromPoints(points),
                                      padding: const EdgeInsets.all(28),
                                    )
                                  : null,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: kMapThemeOptions[0].urlTemplate,
                                subdomains: kMapThemeOptions[0].subdomains,
                                userAgentPackageName: 'com.company.fakestrava',
                              ),
                              if (points.length >= 2)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: points,
                                      strokeWidth: 6,
                                      color: kBrandOrange,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (points.isNotEmpty)
                                    Marker(
                                      point: points.first,
                                      width: 32,
                                      height: 32,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E7D32),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.2,
                                              ),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  if (points.length >= 2)
                                    Marker(
                                      point: points.last,
                                      width: 32,
                                      height: 32,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFC62828),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.2,
                                              ),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.flag,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    kMapThemeOptions[0].attribution,
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricPill(
                      Icons.route,
                      '${distanceKm.toStringAsFixed(2)}',
                      'km',
                    ),
                    _metricPill(
                      Icons.timer_outlined,
                      _formatDuration(startedAt, endedAt, durationSeconds),
                      '',
                    ),
                    _metricPill(
                      Icons.local_fire_department,
                      '${calories.toStringAsFixed(0)}',
                      'kcal',
                    ),
                    _metricPill(
                      Icons.terrain,
                      '+${elevation.toStringAsFixed(0)}',
                      'm',
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

  Widget _metricPill(IconData icon, String value, [String unit = '']) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withValues(alpha: 0.95)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: kBrandOrange),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
