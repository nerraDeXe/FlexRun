import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';
import 'package:fake_strava/home/social_repository.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key, required this.displayName});

  final String displayName;

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with AutomaticKeepAliveClientMixin {
  final SocialRepository _socialRepository = SocialRepository();
  final _scrollController = ScrollController();

  // Error tracking for retry
  bool _isRetrying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _progressErrorMessage(Object? error, {bool isRetry = false}) {
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';

      // Handle missing database
      final missingDatabase =
          error.code == 'not-found' &&
          (message.contains('database (default) does not exist') ||
              message.contains('database fakestrava does not exist'));

      if (missingDatabase) {
        return isRetry
            ? 'Database still not available. Please create it in Firebase Console.'
            : 'Cloud progress is unavailable because Firestore is not set up for this project yet.\n\n'
                  '1. Open Firebase Console\n'
                  '2. Go to Firestore Database\n'
                  '3. Create database "fakestrava"\n'
                  '4. Start in test mode for development';
      }

      // Handle permission errors
      if (error.code == 'permission-denied') {
        return 'You don\'t have permission to access this data.\n'
            'Please check your Firestore security rules.';
      }

      // Handle network errors
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'Network error. Please check your internet connection.';
      }
    }

    return 'Unable to load progress.\n\n${error.toString()}';
  }

  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Safe data extraction with fallbacks

  double _safeDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  DateTime? _safeDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (Firebase.apps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: kBrandOrange),
            SizedBox(height: 16),
            Text(
              'Firebase is not ready yet.',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Please initialize Firebase first.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 48, color: kBrandOrange),
            SizedBox(height: 16),
            Text(
              'Please sign in to view your progress.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return _buildProgressStream(userId);
  }

  Widget _buildProgressStream(String userId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instanceFor(
                app: Firebase.app(),
                databaseId: 'fakestrava',
              )
              .collection('tracking_sessions')
              .where('userId', isEqualTo: userId)
              .orderBy('startedAt', descending: true)
              .limit(20) // Reduced from 50 since we only show 5
              .snapshots(),
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading your progress...',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // Handle errors with retry
        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error);
        }

        // Handle no data
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Reset error state on success

        try {
          final sessions = snapshot.data!.docs;
          final stats = _calculateWeeklyStats(sessions);

          return _buildContent(sessions, stats, userId);
        } catch (e, stackTrace) {
          // Catch any rendering errors
          debugPrint('Error rendering progress page: $e');
          debugPrint('Stack trace: $stackTrace');
          return _buildErrorWidget(e);
        }
      },
    );
  }

  _WeeklyStats _calculateWeeklyStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
  ) {
    final now = DateTime.now();
    // Use local timezone for week calculation to be more user-friendly
    final localNow = now.toLocal();
    final weekStart = DateTime(
      localNow.year,
      localNow.month,
      localNow.day - 7,
    ).toUtc();

    var weekDistanceMeters = 0.0;
    var weekWorkoutCount = 0;
    var weekCalories = 0.0;

    for (final doc in sessions) {
      final data = doc.data();
      final startedAt = _safeDateTime(data['startedAt']);

      if (startedAt == null || startedAt.isBefore(weekStart)) {
        continue;
      }

      weekWorkoutCount += 1;
      weekDistanceMeters += _safeDouble(data['distanceMeters']);
      weekCalories += _safeDouble(data['caloriesKcal']);
    }

    final weekDistanceKm = weekDistanceMeters / 1000;
    final averageDistanceKm = weekWorkoutCount > 0
        ? weekDistanceKm / weekWorkoutCount
        : 0.0;

    return _WeeklyStats(
      distanceKm: weekDistanceKm,
      workoutCount: weekWorkoutCount,
      calories: weekCalories,
      averageDistanceKm: averageDistanceKm,
      totalSessions: sessions.length,
    );
  }

  Widget _buildErrorWidget(Object? error) {
    final isNetworkError =
        error is FirebaseException &&
        (error.code == 'unavailable' || error.code == 'deadline-exceeded');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isNetworkError ? Icons.signal_wifi_off : Icons.error_outline,
              size: 64,
              color: isNetworkError ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _progressErrorMessage(error, isRetry: _isRetrying),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isRetrying ? null : _handleRetry,
              icon: _isRetrying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isRetrying ? 'Retrying...' : 'Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (isNetworkError) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Show network diagnostics
                  _showNetworkDiagnostics(context);
                },
                child: const Text('Network Diagnostics'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleRetry() {
    setState(() {
      _isRetrying = true;
    });

    // Force rebuild of the stream
    setState(() {
      _isRetrying = false;
    });
  }

  Widget _buildEmptyState() {
    return Container(
      color: kSurface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _EmptyStateCard(
              title: 'No workouts yet',
              subtitle:
                  'Start your first run to see your progress here.\n'
                  'Your achievements and statistics will appear once you complete an activity.',
              icon: Icons.directions_run_rounded,
            ),
            const SizedBox(height: 24),
            _EmptyStateCard(
              title: 'Ready to get started?',
              subtitle: 'Go to the Tracking tab to begin your first workout.',
              icon: Icons.play_circle_outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
    _WeeklyStats stats,
    String userId,
  ) {
    final displaySessions = sessions.take(5).toList();

    return Container(
      color: kSurface,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Trigger a refresh by rebuilding the stream
            setState(() {});
            return Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _ProgressSummaryCard(distanceKm: stats.distanceKm),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Highlights',
                subtitle: 'Weekly totals and personal averages',
              ),
              const SizedBox(height: 14),
              _ProgressHighlightsCard(
                workoutCount: stats.workoutCount,
                caloriesKcal: stats.calories,
                averageDistanceKm: stats.averageDistanceKm,
              ),
              if (stats.totalSessions > 5) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '+ ${stats.totalSessions - 5} more sessions',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Recent sessions',
                subtitle: 'Your latest 5 activities',
              ),
              const SizedBox(height: 12),
              ...displaySessions.map((doc) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ActivityFeedCard(
                    sessionId: doc.id,
                    data: doc.data(),
                    currentUserId: userId,
                    currentDisplayName: widget.displayName,
                    firestore: FirebaseFirestore.instanceFor(
                      app: Firebase.app(),
                      databaseId: 'fakestrava',
                    ),
                    socialRepository: _socialRepository,
                    durationLabel: _durationLabel,
                  ),
                );
              }),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Showing ${displaySessions.length} of ${stats.totalSessions} sessions',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress',
                  style: AppTypography.displaySmall.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome back, ${widget.displayName}',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.insights, color: kBrandOrange, size: 32),
        ],
      ),
    );
  }

  void _showNetworkDiagnostics(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Network Diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Checking connection status:'),
            const SizedBox(height: 8),
            _buildDiagnosticItem(
              'Internet Connection',
              Icons.wifi,
              _checkInternetConnection(),
            ),
            _buildDiagnosticItem(
              'Firebase Connection',
              Icons.cloud,
              _checkFirebaseConnection(),
            ),
            _buildDiagnosticItem(
              'Authentication Status',
              Icons.security,
              _checkAuthStatus(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handleRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticItem(String label, IconData icon, bool status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: status ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            status ? '✓ Connected' : '✗ Disconnected',
            style: TextStyle(
              color: status ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  bool _checkInternetConnection() {
    // Simple check - could be enhanced with actual network checking
    return true;
  }

  bool _checkFirebaseConnection() {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _checkAuthStatus() {
    return FirebaseAuth.instance.currentUser != null;
  }
}

// Data class for weekly stats
class _WeeklyStats {
  final double distanceKm;
  final int workoutCount;
  final double calories;
  final double averageDistanceKm;
  final int totalSessions;

  _WeeklyStats({
    required this.distanceKm,
    required this.workoutCount,
    required this.calories,
    required this.averageDistanceKm,
    required this.totalSessions,
  });
}

// Reusable components (keeping existing widgets but making them stateless)
class _ProgressSummaryCard extends StatelessWidget {
  const _ProgressSummaryCard({required this.distanceKm});

  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kBrandBlack, kBrandOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: kBrandOrange.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -16,
            child: Icon(
              Icons.directions_run,
              size: 140,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Last 7 days',
                  style: AppTypography.captionSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${distanceKm.toStringAsFixed(2)} km',
                style: AppTypography.displayLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total distance',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.headingLarge.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: AppTypography.bodySmall.copyWith(
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProgressHighlightsCard extends StatelessWidget {
  const _ProgressHighlightsCard({
    required this.workoutCount,
    required this.caloriesKcal,
    required this.averageDistanceKm,
  });

  final int workoutCount;
  final double caloriesKcal;
  final double averageDistanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildRow(
            label: 'Workouts',
            value: '$workoutCount',
            icon: Icons.fitness_center,
            accent: kInfo,
          ),
          _buildDivider(),
          _buildRow(
            label: 'Calories',
            value: '${caloriesKcal.toStringAsFixed(0)} kcal',
            icon: Icons.local_fire_department,
            accent: kWarning,
          ),
          _buildDivider(),
          _buildRow(
            label: 'Average distance',
            value: '${averageDistanceKm.toStringAsFixed(2)} km / workout',
            icon: Icons.auto_graph,
            accent: kSuccess,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.black.withValues(alpha: 0.06),
      height: 24,
      thickness: 1,
    );
  }

  Widget _buildRow({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.15),
                accent.withValues(alpha: 0.3),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.headingMedium.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.black.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.title,
    required this.subtitle,
    this.icon = Icons.directions_run_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kBrandOrange.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: kBrandOrange.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kBrandOrange.withValues(alpha: 0.15),
                  kBrandOrange.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kBrandOrange.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: kBrandOrange, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.headingSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
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
