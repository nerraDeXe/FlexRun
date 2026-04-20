import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import our new internal files (will be available project-wide)
import 'package:fake_strava/core/theme.dart';

class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.firestore,
    required this.onShareMessage,
  });

  final FirebaseFirestore firestore;
  final ValueChanged<String> onShareMessage;

  Future<void> _exportSessionGpx(String sessionId) async {
    final pointSnapshots = await firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('points')
        .orderBy('timestamp')
        .get();
    if (pointSnapshots.docs.isEmpty) {
      onShareMessage('No points found for this workout.');
      return;
    }
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="Fake Strava">')
      ..writeln('  <trk>')
      ..writeln('    <name>Fake Strava Workout</name>')
      ..writeln('    <trkseg>');
    for (final doc in pointSnapshots.docs) {
      final data = doc.data();
      final lat = (data['latitude'] as num?)?.toDouble();
      final lon = (data['longitude'] as num?)?.toDouble();
      final time = data['timestamp'] as String?;
      if (lat == null || lon == null) {
        continue;
      }
      buffer.writeln('      <trkpt lat="$lat" lon="$lon">');
      if (time != null) {
        buffer.writeln('        <time>$time</time>');
      }
      buffer.writeln('      </trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    await Clipboard.setData(ClipboardData(text: utf8.decode(bytes)));
    onShareMessage('GPX copied to clipboard. Paste it into a .gpx file.');
  }

  String _formatDuration(
    DateTime? startedAt,
    DateTime? endedAt, {
    int? durationSeconds,
  }) {
    Duration? elapsed;
    if (durationSeconds != null && durationSeconds > 0) {
      elapsed = Duration(seconds: durationSeconds);
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

  String _formatWorkoutDate(DateTime? startedAt) {
    if (startedAt == null) {
      return 'Unknown date';
    }
    final local = startedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final workoutDay = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(workoutDay).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (dayDiff == 0) {
      return 'Today, $hh:$mm';
    }
    if (dayDiff == 1) {
      return 'Yesterday, $hh:$mm';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Widget _metricPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kBrandOrange),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetricBox({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kBrandOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        backgroundColor: kBrandBlack,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('tracking_sessions')
            .orderBy('startedAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final errorText = snapshot.error.toString().toLowerCase();
            final missingDefaultDatabase = errorText.contains(
              'database (default) does not exist',
            );
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  missingDefaultDatabase
                      ? 'Cloud history is unavailable because Firestore is not set up for this project yet.\n\nOpen Firebase Console -> Firestore Database and create the default database.'
                      : 'Unable to load workout history.\n\n${snapshot.error}',
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
                            children: [
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Distance',
                                  value:
                                      '${totalDistanceKm.toStringAsFixed(2)} km',
                                  icon: Icons.route,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Time',
                                  value: _formatDuration(
                                    null,
                                    null,
                                    durationSeconds: totalDurationSeconds,
                                  ),
                                  icon: Icons.timer_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
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
                              const SizedBox(width: 8),
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
                final data = sessions[sessionIndex].data();
                final sessionId = sessions[sessionIndex].id;
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
                final distanceKm = distanceMeters / 1000;
                final points = (data['points'] as num?)?.toInt() ?? 0;
                final status = (data['status'] as String?) ?? 'stopped';
                final durationSeconds =
                    (data['activeDurationSeconds'] as num?)?.toInt() ??
                    ((startedAt != null && endedAt != null)
                        ? endedAt.difference(startedAt).inSeconds
                        : 0);
                final pace = durationSeconds > 0 && distanceKm > 0
                    ? (durationSeconds / 60) / distanceKm
                    : 0.0;
                final avgSpeedKmh = durationSeconds > 0 && distanceKm > 0
                    ? distanceKm / (durationSeconds / 3600)
                    : 0.0;
                final isFinished = status == 'stopped';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${distanceKm.toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatWorkoutDate(startedAt),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isFinished ? 'Finished' : status.toUpperCase(),
                                style: TextStyle(
                                  color: isFinished
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE65100),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              tooltip: 'Export GPX',
                              icon: const Icon(Icons.file_download_outlined),
                              onPressed: () => _exportSessionGpx(sessionId),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metricPill(
                              icon: Icons.timer_outlined,
                              label: 'Time',
                              value: _formatDuration(
                                startedAt,
                                endedAt,
                                durationSeconds: durationSeconds,
                              ),
                            ),
                            _metricPill(
                              icon: Icons.speed,
                              label: 'Pace',
                              value: pace > 0
                                  ? '${pace.toStringAsFixed(2)} min/km'
                                  : '-- min/km',
                            ),
                            _metricPill(
                              icon: Icons.flash_on,
                              label: 'Speed',
                              value: avgSpeedKmh > 0
                                  ? '${avgSpeedKmh.toStringAsFixed(2)} km/h'
                                  : '-- km/h',
                            ),
                            _metricPill(
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${calories.toStringAsFixed(0)} kcal',
                            ),
                            _metricPill(
                              icon: Icons.terrain,
                              label: 'Elev',
                              value: '+${elevation.toStringAsFixed(0)} m',
                            ),
                            _metricPill(
                              icon: Icons.location_on_outlined,
                              label: 'Points',
                              value: '$points',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

