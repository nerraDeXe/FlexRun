import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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
      return SafeArea(
        bottom: false,
        child: const EmptyStateWidget(
          icon: Icons.cloud_off_outlined,
          title: 'Feed unavailable',
          subtitle: 'Firebase is not ready yet. Try again in a moment.',
        ),
      );
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return SafeArea(
        bottom: false,
        child: const EmptyStateWidget(
          icon: Icons.person_off_outlined,
          title: 'Sign in required',
          subtitle: 'Please sign in to see the Home feed.',
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _socialRepository.firestore
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, currentUserSnapshot) {
        if (!currentUserSnapshot.hasData) {
          return SafeArea(
            bottom: false,
            child: const _HomeLoadingState(),
          );
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

        return SafeArea(
          bottom: false,
          child: Column(
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
                                final status =
                                    (data['status'] as String?) ?? '';
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
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                            itemCount: feed.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
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
          ),
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
          colors: [kBrandOrange.withValues(alpha: 0.08), Colors.white],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kBrandOrange,
                        kBrandOrange.withValues(alpha: 0.68),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandOrange.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      displayName.isEmpty ? 'A' : displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        TextSpan(
                          style: AppTypography.bodyMedium.copyWith(
                            color: kTextPrimary,
                            height: 1.25,
                          ),
                          children: [
                            TextSpan(
                              text: 'Welcome back, ',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text: displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.black.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '$followingCount people you follow',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kBrandOrange.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 15,
                          color: kBrandOrange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$followingCount',
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _executeSearch(),
                      style: AppTypography.bodySmall,
                      decoration: InputDecoration(
                        hintText: 'Search athletes',
                        hintStyle: AppTypography.bodySmall.copyWith(
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 8),
                          child: Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Colors.black.withValues(alpha: 0.5),
                                ),
                                onPressed: () {
                                  _usernameController.clear();
                                  _executeSearch();
                                },
                                splashRadius: 20,
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: kBrandOrange,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Groups',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const GroupsPage()),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.group_outlined,
                            size: 22,
                            color: kBrandOrange,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kBrandOrange, kBrandOrange.withValues(alpha: 0.88)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandOrange.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _executeSearch,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
      itemBuilder: (_, _) => const SkeletonCard(height: 70),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemCount: 4,
    );
  }
}
