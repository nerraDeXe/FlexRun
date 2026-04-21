import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/utils.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key, required this.displayName});

  final String displayName;

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

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
          children: [
            Text(
              'Welcome, $displayName',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Your weekly momentum at a glance.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ProgressMetricCard(
                    label: 'Distance',
                    value:
                        '${(weekDistanceMeters / 1000).toStringAsFixed(2)} km',
                    icon: Icons.route,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProgressMetricCard(
                    label: 'Workouts',
                    value: '$weekWorkoutCount',
                    icon: Icons.fitness_center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProgressMetricCard(
              label: 'Calories',
              value: '${weekCalories.toStringAsFixed(0)} kcal',
              icon: Icons.local_fire_department,
              fullWidth: true,
            ),
            const SizedBox(height: 18),
            Text(
              'Recent Sessions',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (sessions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No workouts yet.'),
                ),
              )
            else
              ...sessions.take(5).map((doc) {
                final data = doc.data();
                final startedAt = DateTime.tryParse(
                  data['startedAt'] as String? ?? '',
                );
                final endedAt = DateTime.tryParse(
                  data['endedAt'] as String? ?? '',
                );
                final distanceMeters =
                    (data['distanceMeters'] as num?)?.toDouble() ?? 0;
                final calories =
                    (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
                final elevation =
                    (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
                final durationSeconds =
                    (data['activeDurationSeconds'] as num?)?.toInt() ??
                    ((startedAt != null && endedAt != null)
                        ? endedAt.difference(startedAt).inSeconds
                        : 0);
                final pace = durationSeconds > 0 && distanceMeters > 0
                    ? (durationSeconds / 60) / (distanceMeters / 1000)
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kBrandOrange.withValues(alpha: 0.15),
                        foregroundColor: kBrandOrange,
                        child: const Icon(Icons.directions_run),
                      ),
                      title: Text(
                        '${(distanceMeters / 1000).toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatSessionDuration(startedAt, endedAt, durationSeconds: durationSeconds)} · ${pace > 0 ? '${pace.toStringAsFixed(2)} min/km' : '-- min/km'} · ${calories.toStringAsFixed(0)} kcal · +${elevation.toStringAsFixed(0)} m',
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _ProgressMetricCard extends StatelessWidget {
  const _ProgressMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: kBrandOrange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

