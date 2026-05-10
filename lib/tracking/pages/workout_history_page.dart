import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.firestore,
  });

  static const double snapshotMetricHeight = 86;

  final FirebaseFirestore firestore;

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  int _streamEpoch = 0;
  final SocialRepository _socialRepository = SocialRepository();

  String _historyErrorMessage(Object? error) {
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';
      final missingDatabase =
          error.code == 'not-found' &&
          (message.contains('database (default) does not exist') ||
              message.contains('database fakestrava does not exist'));
      if (missingDatabase) {
        return 'Cloud history is unavailable because Firestore is not set up for this project yet.\n\nOpen Firebase Console -> Firestore Database and create database "fakestrava".';
      }
    }
    return 'Unable to load workout history.\n\n$error';
  }

  String _durationLabel(int seconds) {
    final duration = Duration(seconds: seconds > 0 ? seconds : 0);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
          color: kBrandOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kBrandOrange.withValues(alpha: 0.12),
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

  void _reloadHistory() {
    setState(() => _streamEpoch++);
  }

  @override
  Widget build(BuildContext context) {
    final firestore = widget.firestore;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid ?? '';
    final currentDisplayName =
        (currentUser?.displayName?.trim().isNotEmpty == true
            ? currentUser!.displayName!
            : (currentUser?.email?.split('@').first ?? 'You'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        backgroundColor: kBrandBlack,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey<int>(_streamEpoch),
        stream: firestore
            .collection('tracking_sessions')
            .where('userId', isEqualTo: currentUserId)
            .orderBy('startedAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _historyErrorMessage(snapshot.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!.docs;
          if (sessions.isEmpty) {
            return const Center(child: Text('No workouts yet.'));
          }
          var totalDistanceKm = 0.0;
          var totalDurationSeconds = 0;
          var longestDistanceKm = 0.0;
          for (final session in sessions) {
            final data = session.data();
            final distanceMeters =
                (data['distanceMeters'] as num?)?.toDouble() ?? 0;
            final distanceKm = distanceMeters / 1000;
            final startedAt = DateTime.tryParse(
              data['startedAt'] as String? ?? '',
            );
            final endedAt = DateTime.tryParse(data['endedAt'] as String? ?? '');
            final durationSeconds =
                (data['activeDurationSeconds'] as num?)?.toInt() ??
                ((startedAt != null && endedAt != null)
                    ? endedAt.difference(startedAt).inSeconds
                    : 0);
            totalDistanceKm += distanceKm;
            totalDurationSeconds += durationSeconds > 0 ? durationSeconds : 0;
            if (distanceKm > longestDistanceKm) {
              longestDistanceKm = distanceKm;
            }
          }
          final averagePace = totalDistanceKm > 0
              ? (totalDurationSeconds / 60) / totalDistanceKm
              : 0.0;
          return RefreshIndicator(
            onRefresh: () async =>
                Future<void>.delayed(const Duration(milliseconds: 300)),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: sessions.length + 1,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Training Snapshot',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Distance',
                                  value:
                                      '${totalDistanceKm.toStringAsFixed(2)} km',
                                  icon: Icons.route,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Time',
                                  value: _durationLabel(totalDurationSeconds),
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
                                  value: averagePace > 0
                                      ? '${averagePace.toStringAsFixed(2)} min/km'
                                      : '-- min/km',
                                  icon: Icons.speed,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Longest Run',
                                  value:
                                      '${longestDistanceKm.toStringAsFixed(2)} km',
                                  icon: Icons.flag_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final sessionIndex = index - 1;
                final doc = sessions[sessionIndex];
                return ActivityFeedCard(
                  sessionId: doc.id,
                  data: doc.data(),
                  currentUserId: currentUserId,
                  currentDisplayName: currentDisplayName,
                  firestore: firestore,
                  socialRepository: _socialRepository,
                  durationLabel: _durationLabel,
                  onExerciseListChanged: _reloadHistory,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
