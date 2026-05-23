import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/groups/groups_page.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/home/searched_user_profile_page.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final SocialRepository _socialRepository = SocialRepository();
  final TextEditingController _usernameController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  late AnimationController _scrollController;
  late Animation<double> _headerAnimation;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _ensureProfile();
    _usernameController.addListener(_onSearchChanged);

    _scrollController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _headerAnimation = CurvedAnimation(
      parent: _scrollController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onSearchChanged);
    _usernameController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _socialRepository.ensureUserProfile(user: user);
    } catch (_) {}
  }

  void _onSearchChanged() {
    final query = _usernameController.text.trim();
    if (_searchQuery == query) return;

    setState(() => _searchQuery = query);

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

    setState(() => _isSearching = true);

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
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _clearSearch() {
    _usernameController.clear();
    setState(() => _searchQuery = '');
    FocusScope.of(context).unfocus();
  }

  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onScroll(double offset) {
    if (_scrollOffset != offset) {
      setState(() => _scrollOffset = offset);
      if (offset > 50 && !_scrollController.isCompleted) {
        _scrollController.forward();
      } else if (offset <= 50 && _scrollController.isCompleted) {
        _scrollController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return _buildMinimalErrorState(
        icon: Icons.cloud_off,
        title: 'Offline',
        subtitle: 'Check your connection',
      );
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return _buildMinimalErrorState(
        icon: Icons.person_off,
        title: 'Not signed in',
        subtitle: 'Please sign in to continue',
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FC),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _socialRepository.firestore
              .collection('users')
              .doc(currentUser.uid)
              .snapshots(),
          builder: (context, currentUserSnapshot) {
            if (!currentUserSnapshot.hasData) {
              return const _ImmersiveLoadingState();
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

            return NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo is ScrollUpdateNotification) {
                  _onScroll(scrollInfo.metrics.pixels);
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  _buildImmersiveHeader(
                    displayName: displayName,
                    username: username,
                    followingCount: followingIds.length,
                  ),
                  SliverToBoxAdapter(child: _buildHeroSearchBar()),
                  if (_searchQuery.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: _buildNeoSearchResults(),
                    )
                  else
                    _buildDynamicActivityFeed(allowedUsers, currentUser.uid),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMinimalErrorState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: 48, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveHeader({
    required String displayName,
    required String username,
    required int followingCount,
  }) {
    return SliverPersistentHeader(
      pinned: true,
      floating: false,
      delegate: _ImmersiveHeaderDelegate(
        displayName: displayName,
        username: username,
        followingCount: followingCount,
        animation: _headerAnimation,
        scrollOffset: _scrollOffset,
      ),
    );
  }

  Widget _buildHeroSearchBar() {
    return AnimatedBuilder(
      animation: _headerAnimation,
      builder: (context, child) {
        final opacity = 1.0 - (_scrollOffset / 100).clamp(0.0, 1.0);
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 20),
          child: Transform.translate(
            offset: Offset(0, _scrollOffset * 0.3),
            child: Opacity(
              opacity: opacity,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E293B),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Find athletes',
                          hintStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: _searchFocusNode.hasFocus
                                ? const Color(0xFFF97316)
                                : const Color(0xFF94A3B8),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: _clearSearch,
                                  child: Container(
                                    margin: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: const Color(0xFFE2E8F0),
                    ),
                    _buildNeomorphicButton(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNeomorphicButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const GroupsPage()));
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFF97316), const Color(0xFFEA580C)],
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Center(
          child: Icon(Icons.groups_rounded, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildNeoSearchResults() {
    if (_isSearching) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF97316)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Searching',
                style: TextStyle(fontSize: 14, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return SliverFillRemaining(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                Icons.person_search_rounded,
                size: 48,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No athletes found',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different name',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final user = _searchResults[index];
        final id = user['id'] as String;
        final displayName = user['displayName'] as String? ?? 'Athlete';
        final username = user['username'] as String? ?? id.substring(0, 6);
        return _buildNeomorphicUserCard(id, displayName, username);
      }, childCount: _searchResults.length),
    );
  }

  Widget _buildNeomorphicUserCard(
    String id,
    String displayName,
    String username,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SearchedUserProfilePage(
                  userId: id,
                  displayName: displayName,
                  username: username,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFF97316),
                        const Color(0xFFF97316).withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Color(0xFFF97316),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicActivityFeed(
    Set<String> allowedUsers,
    String currentUserId,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _socialRepository.firestore
          .collection('tracking_sessions')
          .orderBy('startedAt', descending: true)
          .limit(150)
          .snapshots(),
      builder: (context, feedSnapshot) {
        if (feedSnapshot.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildErrorWidget(),
            ),
          );
        }

        if (!feedSnapshot.hasData) {
          return const SliverFillRemaining(child: _ImmersiveLoadingState());
        }

        final allDocs = feedSnapshot.data!.docs;
        final feed = allDocs
            .where((doc) {
              final data = doc.data();
              final uid = data['userId'] as String?;
              final status = (data['status'] as String?) ?? '';
              return uid != null &&
                  allowedUsers.contains(uid) &&
                  status == 'stopped';
            })
            .toList(growable: false);

        if (feed.isEmpty) {
          return SliverFillRemaining(child: _buildEmptyFeedHero());
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final doc = feed[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ActivityFeedCard(
                  sessionId: doc.id,
                  data: doc.data(),
                  currentUserId: currentUserId,
                  currentDisplayName: widget.displayName,
                  firestore: _socialRepository.firestore,
                  socialRepository: _socialRepository,
                  durationLabel: _durationLabel,
                ),
              );
            }, childCount: feed.length),
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 16),
          const Text(
            'Unable to load feed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pull down to refresh',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFeedHero() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF97316).withValues(alpha: 0.1),
                const Color(0xFFF97316).withValues(alpha: 0.05),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.sports_score_rounded,
              size: 56,
              color: Color(0xFFF97316),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Empty road ahead',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Start a workout or follow athletes\nto see their achievements',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFF97316), const Color(0xFFEA580C)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF97316).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () {
              // Navigate to discover
            },
            icon: const Icon(Icons.explore_rounded, size: 18),
            label: const Text(
              'Discover Athletes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImmersiveHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String displayName;
  final String username;
  final int followingCount;
  final Animation<double> animation;
  final double scrollOffset;

  _ImmersiveHeaderDelegate({
    required this.displayName,
    required this.username,
    required this.followingCount,
    required this.animation,
    required this.scrollOffset,
  });

  @override
  double get minExtent => 100;
  @override
  double get maxExtent => 220;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final percentCollapsed = (shrinkOffset / maxExtent).clamp(0.0, 1.0);
    final opacity = 1.0 - percentCollapsed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: percentCollapsed > 0.5
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFFFFF7ED), Colors.white],
                ),
              ),
            ),
          ),

          // Collapsed title (appears when scrolling)
          AnimatedOpacity(
            opacity: percentCollapsed > 0.6 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),

          // Expanded content
          Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 60 + (30 * (1 - percentCollapsed)),
              bottom: 16,
            ),
            child: Opacity(
              opacity: opacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAnimatedAvatar(percentCollapsed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF64748B),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 20 - (percentCollapsed * 4),
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@$username',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildFollowerChip(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedAvatar(double percentCollapsed) {
    final size = 56.0 - (percentCollapsed * 16);
    final fontSize = 20.0 - (percentCollapsed * 8);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF97316), Color(0xFFEA580C)],
        ),
        borderRadius: BorderRadius.circular(18 - (percentCollapsed * 6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayName.isEmpty ? 'A' : displayName[0].toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowerChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_rounded, size: 14, color: const Color(0xFFF97316)),
          const SizedBox(width: 6),
          Text(
            '$followingCount',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'following',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

class _ImmersiveLoadingState extends StatelessWidget {
  const _ImmersiveLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FC),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF97316)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your feed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
