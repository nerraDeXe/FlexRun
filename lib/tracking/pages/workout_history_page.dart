import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({super.key, required this.firestore});

  static const double snapshotMetricHeight = 86;
  static const int maxSessions = 50;

  final FirebaseFirestore firestore;

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage>
    with AutomaticKeepAliveClientMixin {
  int _streamEpoch = 0;
  bool _isRefreshing = false;

  final SocialRepository _socialRepository = SocialRepository();
  final ScrollController _scrollController = ScrollController();

  // Cache for computed statistics
  _WorkoutStats? _cachedStats;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _historyErrorMessage(Object? error) {
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';

      // Database not found
      if (error.code == 'not-found' &&
          (message.contains('database (default) does not exist') ||
              message.contains('database fakestrava does not exist'))) {
        return 'Cloud history is unavailable because Firestore is not set up yet.\n\n'
            '1. Open Firebase Console\n'
            '2. Go to Firestore Database\n'
            '3. Create database "fakestrava"\n'
            '4. Start in test mode for development';
      }

      // Permission errors
      if (error.code == 'permission-denied') {
        return 'You don\'t have permission to access workout history.\n'
            'Please check Firestore security rules.';
      }

      // Network errors
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'Network error. Please check your internet connection.';
      }

      // Quota exceeded
      if (error.code == 'resource-exhausted') {
        return 'Firestore quota exceeded. Please try again later.';
      }
    }

    return 'Unable to load workout history.\n\n${error.toString()}';
  }

  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  _WorkoutStats? _calculateStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
  ) {
    if (sessions.isEmpty) return null;

    var totalDistanceKm = 0.0;
    var totalDurationSeconds = 0;
    var longestDistanceKm = 0.0;
    var totalCalories = 0.0;
    var totalElevation = 0.0;
    var validSessions = 0;

    for (final session in sessions) {
      try {
        final data = session.data();
        final distanceMeters = _safeDouble(data['distanceMeters']);
        final distanceKm = distanceMeters / 1000;

        _safeDateTime(data['startedAt']);
        _safeDateTime(data['endedAt']);

        final durationSeconds = _safeInt(data['activeDurationSeconds']);

        final calories = _safeDouble(data['caloriesKcal']);
        final elevation = _safeDouble(data['elevationGainMeters']);

        if (distanceKm > 0 || durationSeconds > 0) {
          totalDistanceKm += distanceKm;
          totalDurationSeconds += durationSeconds > 0 ? durationSeconds : 0;
          totalCalories += calories;
          totalElevation += elevation;
          validSessions++;

          if (distanceKm > longestDistanceKm) {
            longestDistanceKm = distanceKm;
          }
        }
      } catch (_) {
        // Skip malformed sessions
        continue;
      }
    }

    final averagePace = totalDistanceKm > 0 && totalDurationSeconds > 0
        ? (totalDurationSeconds / 60) / totalDistanceKm
        : 0.0;

    return _WorkoutStats(
      totalDistanceKm: totalDistanceKm,
      totalDurationSeconds: totalDurationSeconds,
      longestDistanceKm: longestDistanceKm,
      totalCalories: totalCalories,
      totalElevation: totalElevation,
      averagePace: averagePace,
      totalSessions: validSessions,
    );
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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

  void _reloadHistory() {
    setState(() {
      _streamEpoch++;
    });
  }

  Future<void> _refreshHistory() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _streamEpoch++;
        _cachedStats = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid ?? '';
    final currentDisplayName =
        currentUser?.displayName?.trim().isNotEmpty == true
        ? currentUser!.displayName!
        : (currentUser?.email?.split('@').first ?? 'You');

    if (currentUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Workout History'),
          backgroundColor: kBrandBlack,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Please sign in to view workout history.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        backgroundColor: kBrandBlack,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildWorkoutStream(currentUserId, currentDisplayName),
    );
  }

  Widget _buildWorkoutStream(String userId, String displayName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey<int>(_streamEpoch),
      stream: widget.firestore
          .collection('tracking_sessions')
          .where('userId', isEqualTo: userId)
          .orderBy('startedAt', descending: true)
          .limit(WorkoutHistoryPage.maxSessions)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading workout history...',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error);
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No data available.'));
        }

        final sessions = snapshot.data!.docs;

        // Calculate stats with caching
        final stats = _cachedStats ?? _calculateStats(sessions);
        _cachedStats = stats;

        if (sessions.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: _refreshHistory,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                // Could implement pagination here if needed
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: sessions.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildSummaryCard(stats!, sessions.length);
                }
                final sessionIndex = index - 1;
                final doc = sessions[sessionIndex];
                return _buildSessionCard(
                  doc,
                  userId,
                  displayName,
                  sessionIndex,
                );
              },
            ),
          ),
        );
      },
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
              _historyErrorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _reloadHistory,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kBrandOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center_outlined,
                size: 64,
                color: kBrandOrange,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Workouts Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kBrandBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start your first workout to see your history here.\n'
              'Your achievements and statistics will appear once you complete an activity.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to tracking page
                Navigator.of(context).pop();
                // Could use a better navigation mechanism
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Workout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(_WorkoutStats stats, int totalSessions) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kBrandOrange.withValues(alpha: 0.2),
                        kBrandOrange.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.analytics,
                    color: kBrandOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Training Snapshot',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kBrandBlack,
                        ),
                      ),
                      Text(
                        '$totalSessions workouts',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Total Distance',
                    value: '${stats.totalDistanceKm.toStringAsFixed(2)} km',
                    icon: Icons.route,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Total Time',
                    value: _durationLabel(stats.totalDurationSeconds),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Avg Pace',
                    value: stats.averagePace > 0
                        ? '${stats.averagePace.toStringAsFixed(2)} min/km'
                        : '-- min/km',
                    icon: Icons.speed,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Longest Run',
                    value: '${stats.longestDistanceKm.toStringAsFixed(2)} km',
                    icon: Icons.flag_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Total Calories',
                    value: '${stats.totalCalories.toStringAsFixed(0)} kcal',
                    icon: Icons.local_fire_department,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _summaryMetricBox(
                    label: 'Total Elevation',
                    value: '${stats.totalElevation.toStringAsFixed(0)} m',
                    icon: Icons.terrain,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String userId,
    String displayName,
    int index,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ActivityFeedCard(
          sessionId: doc.id,
          data: doc.data(),
          currentUserId: userId,
          currentDisplayName: displayName,
          firestore: widget.firestore,
          socialRepository: _socialRepository,
          durationLabel: _durationLabel,
          onExerciseListChanged: _reloadHistory,
        ),
      ),
    );
  }

  Widget _summaryMetricBox({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return SizedBox(
      height: WorkoutHistoryPage.snapshotMetricHeight,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kBrandOrange.withValues(alpha: 0.06),
              kBrandOrange.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kBrandOrange.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: kBrandOrange),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.black.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTypography.headingSmall.copyWith(
                  color: Colors.black.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Data class for workout statistics
class _WorkoutStats {
  final double totalDistanceKm;
  final int totalDurationSeconds;
  final double longestDistanceKm;
  final double totalCalories;
  final double totalElevation;
  final double averagePace;
  final int totalSessions;

  _WorkoutStats({
    required this.totalDistanceKm,
    required this.totalDurationSeconds,
    required this.longestDistanceKm,
    required this.totalCalories,
    required this.totalElevation,
    required this.averagePace,
    required this.totalSessions,
  });
}
