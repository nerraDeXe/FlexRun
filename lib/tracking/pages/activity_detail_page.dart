/// Activity detail page.
library;

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/maplibre_config.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';
import 'package:fake_strava/tracking/widgets/ai_insights_section.dart';
import 'package:fake_strava/home/flyover_replay_page_stub.dart'
    if (dart.library.io) 'package:fake_strava/home/flyover_replay_page.dart';

class ActivityDetailPage extends StatelessWidget {
  const ActivityDetailPage({
    super.key,
    required this.firestore,
    required this.sessionId,
    required this.sessionData,
    required this.actorTitle,
  });

  final FirebaseFirestore firestore;
  final String sessionId;
  final Map<String, dynamic> sessionData;
  final String actorTitle;

  String get _pageTitle =>
      actorTitle == 'You' ? 'Your Activity' : '$actorTitle Activity';

  bool _isOwnActivity() {
    final ownerId = sessionData['userId'] as String?;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return ownerId != null && currentUserId != null && ownerId == currentUserId;
  }

  String _formatDuration(DateTime? startedAt, DateTime? endedAt, int seconds) {
    Duration? elapsed;
    if (seconds > 0) {
      elapsed = Duration(seconds: seconds);
    } else if (startedAt != null && endedAt != null) {
      elapsed = endedAt.difference(startedAt);
    }
    if (elapsed == null) return '--:--';

    final parts = <String>[];
    if (elapsed.inHours > 0) parts.add('${elapsed.inHours}h');
    if (elapsed.inMinutes.remainder(60) > 0) {
      parts.add('${elapsed.inMinutes.remainder(60)}m');
    }
    if (elapsed.inSeconds.remainder(60) > 0 || parts.isEmpty) {
      parts.add('${elapsed.inSeconds.remainder(60)}s');
    }

    return parts.join(' ');
  }

  String _calculatePace(double distanceKm, int durationSeconds) {
    if (distanceKm <= 0 || durationSeconds <= 0) return '--:--';
    final secondsPerKm = durationSeconds / distanceKm;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double _calculateSpeed(LatLng start, LatLng end, int durationMs) {
    if (durationMs <= 0) return 0;
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

  Color _getSpeedColor(double speedKmh) {
    final normalized = ((speedKmh - 5) / 10).clamp(0.0, 1.0);
    if (normalized > 0.5) {
      final t = (normalized - 0.5) * 2;
      return Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFDD835),
        1 - t,
      )!;
    } else {
      final t = normalized * 2;
      return Color.lerp(
        const Color(0xFFF44336),
        const Color(0xFFFDD835),
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
    final pointsCount = (sessionData['points'] as num?)?.toInt() ?? 0;
    final isMine = _isOwnActivity();
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

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: Text(
          _pageTitle,
          style: AppTypography.headingMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: kBrandBlack,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (isMine)
            IconButton(
              tooltip: 'Delete exercise',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                confirmAndDeleteExercise(
                  context,
                  firestore: firestore,
                  sessionId: sessionId,
                  userId: uid,
                  popRouteAfterDelete: true,
                );
              },
            ),
        ],
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
            return const _ActivityDetailLoadingState();
          }

          bool isValidLatLon(double? lat, double? lon) {
            return lat != null &&
                lon != null &&
                lat.isFinite &&
                lon.isFinite &&
                lat >= -90 &&
                lat <= 90 &&
                lon >= -180 &&
                lon <= 180;
          }

          final points = snapshot.data!.docs
              .map((doc) {
                final data = doc.data();
                final lat = (data['latitude'] as num?)?.toDouble();
                final lon = (data['longitude'] as num?)?.toDouble();
                if (!isValidLatLon(lat, lon)) return null;
                return LatLng(lat!, lon!);
              })
              .whereType<LatLng>()
              .toList(growable: false);

          final elevations = snapshot.data!.docs
              .map((doc) {
                final data = doc.data();
                final lat = (data['latitude'] as num?)?.toDouble();
                final lon = (data['longitude'] as num?)?.toDouble();
                if (!isValidLatLon(lat, lon)) return null;
                final raw = (data['elevation'] as num?)?.toDouble();
                return (raw != null && raw.isFinite) ? raw : 0.0;
              })
              .whereType<double>()
              .toList(growable: false);

          final center = points.isNotEmpty
              ? points.first
              : const LatLng(3.1390, 101.6869);

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              children: [
                _HeroStatsCard(
                  distanceKm: distanceKm,
                  durationLabel: durationLabel,
                  paceLabel: paceLabel,
                  averageSpeed: averageSpeed,
                  startedAt: startedAt,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _QuickStatsGrid(
                        calories: calories,
                        elevation: elevation,
                        pointsCount: pointsCount,
                        startedAt: startedAt,
                        endedAt: endedAt,
                      ),
                      const SizedBox(height: 16),
                      AIInsightsSection(
                        firestore: firestore,
                        sessionId: sessionId,
                        sessionData: sessionData,
                        isMine: isMine,
                      ),
                      _FlyoverCard(
                        context: context,
                        points: points,
                        elevations: elevations,
                        title: _pageTitle,
                        durationSeconds: durationSeconds,
                        distanceKm: distanceKm,
                      ),
                      const SizedBox(height: 16),
                      _RouteMapCard(
                        points: points,
                        initialCenter: center,
                        polylines: points.length >= 2
                            ? _buildSpeedGradientPolylines(
                                points,
                                durationSeconds,
                              )
                            : const <Polyline>[],
                      ),
                      const SizedBox(height: 16),
                      _RanTogetherSection(
                        firestore: firestore,
                        sessionId: sessionId,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
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
      final speed = _calculateSpeed(
        points[i],
        points[i + 1],
        segmentDurationMs,
      );
      polylines.add(
        Polyline(
          points: [points[i], points[i + 1]],
          strokeWidth: 5,
          color: _getSpeedColor(speed),
        ),
      );
    }
    return polylines;
  }
}

// Hero stats card
class _HeroStatsCard extends StatelessWidget {
  const _HeroStatsCard({
    required this.distanceKm,
    required this.durationLabel,
    required this.paceLabel,
    required this.averageSpeed,
    required this.startedAt,
  });

  final double distanceKm;
  final String durationLabel;
  final String paceLabel;
  final double averageSpeed;
  final DateTime? startedAt;

  String _getWeekday(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  String _cleanDurationLabel(String label) {
    final parts = label.split(' ');
    String h = '0';
    String m = '0';
    String s = '0';
    for (final part in parts) {
      if (part.contains('h')) {
        h = part.replaceAll('h', '');
      } else if (part.contains('m')) {
        m = part.replaceAll('m', '');
      } else if (part.contains('s')) {
        s = part.replaceAll('s', '');
      }
    }
    if (h != '0') {
      return '$h:${m.padLeft(2, '0')}:${s.padLeft(2, '0')}';
    } else {
      return '$m:${s.padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = startedAt?.toLocal();
    final month = date != null
        ? '${date.year}.${date.month.toString().padLeft(2, '0')}'
        : '';
    final day = date != null ? date.day.toString() : '';
    final weekday = date != null ? _getWeekday(date.weekday) : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrandBlack, kBrandBlack.withValues(alpha: 0.95)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      month,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      day,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      weekday,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kBrandOrange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: kBrandOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, color: kBrandOrange, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${averageSpeed.toStringAsFixed(1)} km/h',
                        style: const TextStyle(
                          color: kBrandOrange,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _HeroStatItem(
                    value: distanceKm.toStringAsFixed(2),
                    unit: 'km',
                    label: 'Distance',
                  ),
                ),
                Container(width: 1, height: 50, color: Colors.white24),
                Expanded(
                  child: _HeroStatItem(
                    value: paceLabel,
                    unit: 'min/km',
                    label: 'Pace',
                  ),
                ),
                Container(width: 1, height: 50, color: Colors.white24),
                Expanded(
                  child: _HeroStatItem(
                    value: _cleanDurationLabel(durationLabel),
                    unit: durationLabel.contains('h') ? 'hr' : 'min',
                    label: 'Duration',
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

class _HeroStatItem extends StatelessWidget {
  const _HeroStatItem({
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// Quick stats grid
class _QuickStatsGrid extends StatelessWidget {
  const _QuickStatsGrid({
    required this.calories,
    required this.elevation,
    required this.pointsCount,
    required this.startedAt,
    required this.endedAt,
  });

  final double calories;
  final double elevation;
  final int pointsCount;
  final DateTime? startedAt;
  final DateTime? endedAt;

  String _formatTimeOfDay(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    final local = dateTime.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 5,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.82,
      children: [
        _QuickStat(
          icon: Icons.local_fire_department,
          value: calories.toStringAsFixed(0),
          unit: 'kcal',
          color: kBrandOrange,
        ),
        _QuickStat(
          icon: Icons.terrain,
          value: '+${elevation.toStringAsFixed(0)}',
          unit: 'm',
          color: Colors.green.shade400,
        ),
        _QuickStat(
          icon: Icons.location_on_outlined,
          value: '$pointsCount',
          unit: 'pts',
          color: Colors.blue.shade400,
        ),
        _QuickStat(
          icon: Icons.schedule,
          value: _formatTimeOfDay(startedAt),
          unit: 'start',
          color: Colors.purple.shade400,
        ),
        _QuickStat(
          icon: Icons.flag,
          value: _formatTimeOfDay(endedAt),
          unit: 'end',
          color: Colors.teal.shade400,
        ),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.icon,
    required this.value,
    required this.unit,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: kBrandBlack,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              unit,
              style: TextStyle(
                color: kTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Flyover card
class _FlyoverCard extends StatelessWidget {
  const _FlyoverCard({
    required this.context,
    required this.points,
    required this.elevations,
    required this.title,
    required this.durationSeconds,
    required this.distanceKm,
  });

  final BuildContext context;
  final List<LatLng> points;
  final List<double>? elevations;
  final String title;
  final int durationSeconds;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    final hasRoute = points.length >= 2;
    final hasStyle = kResolvedMapStyleUrl.isNotEmpty;
    final canFlyover = hasRoute && hasStyle;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canFlyover
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => buildFlyoverReplayPage(
                        points: points,
                        title: title,
                        elevations: elevations,
                        durationSeconds: durationSeconds,
                        distanceKm: distanceKm,
                      ),
                    ),
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                        kBrandOrange,
                        kBrandOrange.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    canFlyover ? Icons.play_arrow_rounded : Icons.lock_outline,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3D Flyover Replay',
                        style: AppTypography.headingSmall.copyWith(
                          fontWeight: FontWeight.w800,
                          color: kBrandBlack,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canFlyover
                            ? 'Watch a cinematic replay of your route'
                            : !hasRoute
                            ? 'Not enough GPS points for replay'
                            : 'Configure map style to enable 3D',
                        style: AppTypography.bodySmall.copyWith(
                          color: kTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canFlyover)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: kBrandOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: kBrandOrange,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Route map card
class _RouteMapCard extends StatefulWidget {
  const _RouteMapCard({
    required this.points,
    required this.initialCenter,
    required this.polylines,
  });

  final List<LatLng> points;
  final LatLng initialCenter;
  final List<Polyline> polylines;

  @override
  State<_RouteMapCard> createState() => _RouteMapCardState();
}

class _RouteMapCardState extends State<_RouteMapCard> {
  int _mapThemeIndex = 0;

  void _cycleMapTheme() {
    setState(() {
      _mapThemeIndex = (_mapThemeIndex + 1) % kMapThemeOptions.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: kBrandOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      color: kBrandOrange,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route Map',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: kBrandBlack,
                          ),
                        ),
                        Text(
                          'Color shows speed',
                          style: TextStyle(fontSize: 10, color: kTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      onTap: _cycleMapTheme,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers, size: 14, color: kTextSecondary),
                          const SizedBox(width: 4),
                          Text(
                            kMapThemeOptions[_mapThemeIndex].label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: kTextSecondary,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 14,
                            color: kTextSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 260,
              child: _RouteMapView(
                points: widget.points,
                initialCenter: widget.initialCenter,
                polylines: widget.polylines,
                mapThemeIndex: _mapThemeIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Embedded 2D route map
class _RouteMapView extends StatelessWidget {
  const _RouteMapView({
    required this.points,
    required this.initialCenter,
    required this.polylines,
    required this.mapThemeIndex,
  });

  final List<LatLng> points;
  final LatLng initialCenter;
  final List<Polyline> polylines;
  final int mapThemeIndex;

  LatLngBounds? _safeRouteBounds(List<LatLng> points) {
    if (points.length < 2) return null;
    final bounds = LatLngBounds.fromPoints(points);
    final latSpan = (bounds.north - bounds.south).abs();
    final lonSpan = (bounds.east - bounds.west).abs();
    if (latSpan < 1e-6 && lonSpan < 1e-6) return null;
    return bounds;
  }

  @override
  Widget build(BuildContext context) {
    final theme = kMapThemeOptions[mapThemeIndex];
    final routeBounds = _safeRouteBounds(points);

    if (points.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 40, color: kTextSecondary),
              SizedBox(height: 10),
              Text(
                'No route data',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: kTextSecondary,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'No GPS points available',
                style: TextStyle(fontSize: 11, color: kTextSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14,
        minZoom: 2,
        maxZoom: 19,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
        ),
        initialCameraFit: routeBounds != null
            ? CameraFit.bounds(
                bounds: routeBounds,
                padding: const EdgeInsets.all(28),
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: theme.urlTemplate,
          subdomains: theme.subdomains,
          userAgentPackageName: 'com.company.fakestrava',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(
          markers: [
            if (points.isNotEmpty)
              Marker(
                point: points.first,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            if (points.length >= 2)
              Marker(
                point: points.last,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.flag, color: Colors.white, size: 12),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution(theme.attribution)],
        ),
      ],
    );
  }
}

// Loading state
class _ActivityDetailLoadingState extends StatelessWidget {
  const _ActivityDetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: kBrandOrange));
  }
}

// Ran together section
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final concurrentRunners = snapshot.data!.docs;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: kBrandOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.people,
                        color: kBrandOrange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ran with you · ${concurrentRunners.length}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kBrandBlack,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                itemCount: concurrentRunners.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 52),
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
                  final durationStr = duration.inMinutes > 0
                      ? '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s'
                      : '${duration.inSeconds}s';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: kBrandOrange.withValues(alpha: 0.2),
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kBrandOrange,
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: kBrandBlack,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${overlapKm.toStringAsFixed(1)} km · $durationStr',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: kTextSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kBrandOrange.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_border,
                            size: 16,
                            color: kBrandOrange,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
