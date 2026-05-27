import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';
import 'package:fake_strava/home/social_repository.dart';

class ProgressPage extends StatelessWidget {
  ProgressPage({super.key, required this.displayName});

  final String displayName;
  final SocialRepository _socialRepository = SocialRepository();

  String _progressErrorMessage(Object? error) {
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';
      final missingDatabase =
          error.code == 'not-found' &&
          (message.contains('database (default) does not exist') ||
              message.contains('database fakestrava does not exist'));
      if (missingDatabase) {
        return 'Cloud progress is unavailable because Firestore is not set up for this project yet.\n\nOpen Firebase Console -> Firestore Database and create database "fakestrava".';
      }
    }
    return 'Unable to load progress.\n\n$error';
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

    final userId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instanceFor(
                app: Firebase.app(),
                databaseId: 'fakestrava',
              )
              .collection('tracking_sessions')
              .where('userId', isEqualTo: userId)
              .orderBy('startedAt', descending: true)
              .limit(50)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_progressErrorMessage(snapshot.error)),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sessions = snapshot.data!.docs;
        final now = DateTime.now().toUtc();
        final weekStart = now.subtract(const Duration(days: 7));
        var weekDistanceMeters = 0.0;
        var weekWorkoutCount = 0;
        var weekCalories = 0.0;

        for (final doc in sessions) {
          final data = doc.data();
          final startedAt = DateTime.tryParse(
            data['startedAt'] as String? ?? '',
          );
          if (startedAt == null || startedAt.isBefore(weekStart)) {
            continue;
          }
          weekWorkoutCount += 1;
          weekDistanceMeters +=
              (data['distanceMeters'] as num?)?.toDouble() ?? 0;
          weekCalories += (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
        }

        final weekDistanceKm = weekDistanceMeters / 1000;
        final averageDistanceKm = weekWorkoutCount > 0
            ? weekDistanceKm / weekWorkoutCount
            : 0.0;

        return Container(
          color: kSurface,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
              children: [
                // Enhanced header section
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kBrandOrange.withValues(alpha: 0.08),
                        Colors.white,
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Progress',
                          style: AppTypography.displaySmall.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.insights,
                        color: kBrandOrange,
                        size: 32,
                      ),
                    ],
                  ),
                ),
                _ProgressSummaryCard(distanceKm: weekDistanceKm),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Highlights',
                  subtitle: 'Weekly totals and personal averages',
                ),
                const SizedBox(height: 14),
                _ProgressHighlightsCard(
                  workoutCount: weekWorkoutCount,
                  caloriesKcal: weekCalories,
                  averageDistanceKm: averageDistanceKm,
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Recent sessions',
                  subtitle: 'Your latest 5 activities',
                ),
                const SizedBox(height: 12),
                if (sessions.isEmpty)
                  const _EmptyStateCard(
                    title: 'No workouts yet',
                    subtitle: 'Start your first run to see progress here.',
                  )
                else
                  ...sessions.take(5).map((doc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ActivityFeedCard(
                        sessionId: doc.id,
                        data: doc.data(),
                        currentUserId: userId ?? '',
                        currentDisplayName: displayName,
                        firestore: FirebaseFirestore.instanceFor(
                          app: Firebase.app(),
                          databaseId: 'fakestrava',
                        ),
                        socialRepository: _socialRepository,
                        durationLabel: _durationLabel,
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
          child: Icon(
            icon,
            color: accent,
            size: 22,
          ),
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
  const _EmptyStateCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
            child: Icon(
              Icons.directions_run_rounded,
              color: kBrandOrange,
              size: 24,
            ),
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
