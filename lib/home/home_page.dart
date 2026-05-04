import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/maplibre_config.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/home/flyover_replay_page_stub.dart'
    if (dart.library.io) 'package:fake_strava/home/flyover_replay_page.dart';
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
      final results = await _socialRepository.searchUsersByPrefix(
        prefix: query,
      );
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
      return const EmptyStateWidget(
        icon: Icons.cloud_off_outlined,
        title: 'Feed unavailable',
        subtitle: 'Firebase is not ready yet. Try again in a moment.',
      );
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const EmptyStateWidget(
        icon: Icons.person_off_outlined,
        title: 'Sign in required',
        subtitle: 'Please sign in to see the Home feed.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _socialRepository.firestore
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, currentUserSnapshot) {
        if (!currentUserSnapshot.hasData) {
          return const _HomeLoadingState();
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
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: ErrorStateWidget(
                              message:
                                  'Unable to load activity feed.\n${feedSnapshot.error}',
                              onAction: () => setState(() {}),
                            ),
                          );
                        }
                        if (!feedSnapshot.hasData) {
                          return const _HomeLoadingState();
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
                          return const EmptyStateWidget(
                            icon: Icons.directions_run_outlined,
                            title: 'No activity yet',
                            subtitle:
                                'Start a workout or follow more users to fill your Home feed.',
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                          itemCount: feed.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
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
      return const _SearchLoadingState();
    }

    if (_searchResults.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.search_off,
        title: 'No users found',
        subtitle: 'Try a different username or shorten your search term.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final id = user['id'] as String;
        final displayName = user['displayName'] as String? ?? 'Athlete';
        final username = user['username'] as String? ?? id.substring(0, 6);

        return AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () {
            importSearchedUserProfilePageAndNavigate(
              context,
              id,
              displayName,
              username,
            );
          },
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: kBrandOrange.withValues(alpha: 0.12),
              foregroundColor: kBrandOrange,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            title: Text(displayName, style: AppTypography.headingSmall),
            subtitle: Text('@$username', style: AppTypography.bodySmall),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              importSearchedUserProfilePageAndNavigate(
                context,
                id,
                displayName,
                username,
              );
            },
          ),
        );
      },
    );
  }

  void importSearchedUserProfilePageAndNavigate(
    BuildContext context,
    String id,
    String displayName,
    String username,
  ) {
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
          colors: [kBrandOrange.withValues(alpha: 0.11), Colors.white],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kBrandOrange,
                        kBrandOrange.withValues(alpha: 0.72),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandOrange.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      displayName.isEmpty ? 'A' : displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
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
                      Text('Welcome back', style: AppTypography.captionSmall),
                      const SizedBox(height: 2),
                      Text(displayName, style: AppTypography.displaySmall),
                      const SizedBox(height: 2),
                      Text('@$username', style: AppTypography.bodySmall),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GroupsPage()),
                    );
                  },
                  icon: const Icon(Icons.group_outlined, size: 18),
                  label: const Text('Groups'),
                  style: TextButton.styleFrom(
                    foregroundColor: kBrandBlack,
                    backgroundColor: Colors.white.withValues(alpha: 0.78),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kBrandOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.group,
                      size: 18,
                      color: kBrandOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Following $followingCount',
                    style: AppTypography.labelLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
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
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: kBrandOrange,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _executeSearch,
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandBlack,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
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

    return AppCard(
      padding: EdgeInsets.zero,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.white.withValues(alpha: 0.96)],
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
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kBrandOrange,
                            kBrandOrange.withValues(alpha: 0.78),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          (actorUsername.isNotEmpty ? actorUsername[0] : 'R')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
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
                          Text(title, style: AppTypography.headingSmall),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppTypography.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_outward_rounded,
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
                    color: kSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              icon: Icons.route,
                              label: 'Distance',
                              value: '${distanceKm.toStringAsFixed(2)} km',
                              accent: kBrandOrange,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statTile(
                              icon: Icons.timer_outlined,
                              label: 'Time',
                              value: durationLabel(durationSeconds),
                              accent: kInfo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              icon: Icons.speed,
                              label: 'Pace',
                              value: pace > 0
                                  ? '${pace.toStringAsFixed(2)} min/km'
                                  : '-- min/km',
                              accent: kBrandBlack,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statTile(
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${calories.toStringAsFixed(0)} kcal',
                              accent: kWarning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _statTile(
                        icon: Icons.terrain,
                        label: 'Elevation',
                        value: '+${elevation.toStringAsFixed(0)} m',
                        accent: kSuccess,
                        isWide: true,
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
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final likeCount = likes.length;
                    final liked = likes.any((doc) => doc.id == currentUserId);
                    return Row(
                      children: [
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: liked
                                  ? Colors.redAccent.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: InkWell(
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: liked
                                        ? Colors.redAccent
                                        : Colors.black54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$likeCount ${likeCount == 1 ? 'like' : 'likes'}',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: kBrandOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: kBrandOrange,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Your activity',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w700,
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
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    bool isWide = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [AppShadow.xs],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: kTextSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: isWide ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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

  /// Calculates pace in min/km format from distance and duration
  /// Returns "M:SS" format (e.g., "6:45" for 6 minutes 45 seconds per km)
  String _calculatePace(double distanceKm, int durationSeconds) {
    if (distanceKm <= 0 || durationSeconds <= 0) {
      return '--:--';
    }
    // Calculate seconds per km
    final secondsPerKm = durationSeconds / distanceKm;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Calculates speed in km/h for a given segment
  double _calculateSpeed(LatLng start, LatLng end, int durationMs) {
    if (durationMs <= 0) return 0;
    // Approximate distance in km using Haversine formula simplified
    const double earthRadiusKm = 6371;
    final double lat1 = start.latitude * math.pi / 180;
    final double lat2 = end.latitude * math.pi / 180;
    final double dLat = (end.latitude - start.latitude) * math.pi / 180;
    final double dLon = (end.longitude - start.longitude) * math.pi / 180;

    final double a =
        (1 - math.cos(dLat / 2)) / 2 +
        math.cos(lat1) * math.cos(lat2) * (1 - math.cos(dLon / 2)) / 2;
    final double distanceKm =
        2 * earthRadiusKm * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    final double durationHours = durationMs / (1000 * 60 * 60);
    return distanceKm / durationHours;
  }

  /// Returns color based on speed: green (fast) → yellow → red (slow)
  /// Assumes average running speed around 10 km/h
  Color _getSpeedColor(double speedKmh) {
    // Normalize speed: 15 km/h = fast (green), 5 km/h = slow (red)
    final normalized = ((speedKmh - 5) / 10).clamp(0.0, 1.0);

    if (normalized > 0.5) {
      // Green to yellow
      final t = (normalized - 0.5) * 2;
      return Color.lerp(
        const Color(0xFF4CAF50), // Green
        const Color(0xFFFDD835), // Yellow
        1 - t,
      )!;
    } else {
      // Yellow to red
      final t = normalized * 2;
      return Color.lerp(
        const Color(0xFFF44336), // Red
        const Color(0xFFFDD835), // Yellow
        1 - t,
      )!;
    }
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
    final durationLabel = _formatDuration(startedAt, endedAt, durationSeconds);
    final paceLabel = _calculatePace(distanceKm, durationSeconds);
    final averageSpeed = durationSeconds > 0
        ? distanceKm / (durationSeconds / 3600)
        : 0.0;
    final averageSpeedLabel = averageSpeed > 0
        ? '${averageSpeed.toStringAsFixed(1)} km/h'
        : '-- km/h';

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: Text(
          '$actorTitle Activity',
          style: AppTypography.headingMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: kBrandBlack,
        foregroundColor: Colors.white,
        elevation: 0,
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
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorStateWidget(
                message: 'Unable to load route map.\n${snapshot.error}',
                onAction: () => Navigator.of(context).pop(),
                actionLabel: 'Back',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _HomeDetailLoadingState();
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              _summaryCard(
                distanceKm: distanceKm,
                durationLabel: durationLabel,
                paceLabel: paceLabel,
                averageSpeedLabel: averageSpeedLabel,
                dateLabel: _formatDateTime(startedAt),
              ),
              const SizedBox(height: 14),
              _flyoverCard(
                context: context,
                points: points,
                title: '$actorTitle Activity',
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                  child: SizedBox(
                    height: 300,
                    child: points.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.route_outlined,
                            title: 'No route points',
                            subtitle:
                                'This activity does not have enough location data to draw a route.',
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
                                  polylines: _buildSpeedGradientPolylines(
                                    points,
                                    durationSeconds,
                                  ),
                                ),
                              MarkerLayer(
                                markers: [
                                  if (points.isNotEmpty)
                                    Marker(
                                      point: points.first,
                                      width: 34,
                                      height: 34,
                                      child: _routeMarker(
                                        color: const Color(0xFF2E7D32),
                                        icon: Icons.play_arrow,
                                        iconSize: 16,
                                      ),
                                    ),
                                  if (points.length >= 2)
                                    Marker(
                                      point: points.last,
                                      width: 34,
                                      height: 34,
                                      child: _routeMarker(
                                        color: const Color(0xFFC62828),
                                        icon: Icons.flag,
                                        iconSize: 14,
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
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity details', style: AppTypography.headingSmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            icon: Icons.schedule,
                            label: 'Started',
                            value: _formatDateTime(startedAt),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailTile(
                            icon: Icons.flag,
                            label: 'Ended',
                            value: _formatDateTime(endedAt),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            icon: Icons.local_fire_department,
                            label: 'Calories',
                            value: '${calories.toStringAsFixed(0)} kcal',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _detailTile(
                            icon: Icons.terrain,
                            label: 'Elevation',
                            value: '+${elevation.toStringAsFixed(0)} m',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _RanTogetherSection(firestore: firestore, sessionId: sessionId),
            ],
          );
        },
      ),
    );
  }

  List<Polyline> _buildSpeedGradientPolylines(
    List<LatLng> points,
    int totalDurationSeconds,
  ) {
    if (points.length < 2) return [];

    final polylines = <Polyline>[];
    final segmentDurationMs =
        (totalDurationSeconds * 1000) ~/ (points.length - 1);

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final speed = _calculateSpeed(start, end, segmentDurationMs);
      final color = _getSpeedColor(speed);

      polylines.add(
        Polyline(points: [start, end], strokeWidth: 6, color: color),
      );
    }

    return polylines;
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return '--';
    }
    final local = dateTime.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _summaryCard({
    required double distanceKm,
    required String durationLabel,
    required String paceLabel,
    required String averageSpeedLabel,
    required String dateLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kBrandBlack, kBrandOrange.withValues(alpha: 0.92)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [AppShadow.lg],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity summary',
            style: AppTypography.labelSmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(
            '${distanceKm.toStringAsFixed(2)} km',
            style: AppTypography.displayMedium.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Total distance',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: durationLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryStat(
                  icon: Icons.speed,
                  label: 'Pace',
                  value: paceLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryStat(
                  icon: Icons.bolt,
                  label: 'Avg speed',
                  value: averageSpeedLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style:
                      AppTypography.labelSmall.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.headingSmall.copyWith(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flyoverCard({
    required BuildContext context,
    required List<LatLng> points,
    required String title,
  }) {
    final hasRoute = points.length >= 2;
    final hasStyle = kResolvedMapStyleUrl.isNotEmpty;
    final canFlyover = hasRoute && hasStyle;
    final subtitle = !hasRoute
        ? 'Not enough route data to replay yet.'
        : !hasStyle
            ? 'Add a MapTiler key or style URL to enable 3D replay.'
            : 'Cinematic replay that follows your route.';
    final buttonLabel = canFlyover
        ? 'Play 3D flyover'
        : hasStyle
            ? 'Route too short'
            : 'Key required';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.threed_rotation_rounded,
                  color: kBrandOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3D flyover replay', style: AppTypography.headingSmall),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canFlyover
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => buildFlyoverReplayPage(
                            points: points,
                            title: title,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                backgroundColor: kBrandBlack,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kBrandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: kBrandOrange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: kTextSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeMarker({
    required Color color,
    required IconData icon,
    required double iconSize,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(height: 144),
        SizedBox(height: 12),
        SkeletonCard(height: 126),
        SizedBox(height: 12),
        SkeletonCard(height: 126),
      ],
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemBuilder: (_, __) => const SkeletonCard(height: 70),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: 4,
    );
  }
}

class _HomeDetailLoadingState extends StatelessWidget {
  const _HomeDetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(height: 300),
        SizedBox(height: 14),
        SkeletonCard(height: 120),
        SizedBox(height: 14),
        SkeletonCard(height: 120),
      ],
    );
  }
}

/// Widget to display runners who ran concurrently (from "Ran with you" records)
class _RanTogetherSection extends StatelessWidget {
  const _RanTogetherSection({required this.firestore, required this.sessionId});

  final FirebaseFirestore firestore;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: firestore
          .collection('tracking_sessions')
          .doc(sessionId)
          .collection('concurrent_runners')
          .get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final concurrentRunners = snapshot.data!.docs;

        return Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people, size: 20, color: kBrandOrange),
                  const SizedBox(width: 8),
                  const Text(
                    'Ran with you',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${concurrentRunners.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: concurrentRunners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = concurrentRunners[index];
                  final data = doc.data();
                  final displayName =
                      data['concurrentUserDisplayName'] as String? ??
                      'Unknown Runner';
                  final overlapKm =
                      (data['overlapDistanceKm'] as num?)?.toDouble() ?? 0;
                  final timeTogetherSeconds =
                      (data['timeTogetherSeconds'] as num?)?.toInt() ?? 0;
                  final duration = Duration(seconds: timeTogetherSeconds);
                  final durationStr =
                      '${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: kBrandOrange,
                          foregroundColor: Colors.white,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '${overlapKm.toStringAsFixed(1)} km • $durationStr',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.favorite_border,
                          size: 18,
                          color: kBrandOrange,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
