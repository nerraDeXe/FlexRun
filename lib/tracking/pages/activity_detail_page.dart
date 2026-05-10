/// Activity detail page.
///
/// This is the screen that opens when the user taps a run card from the
/// Home feed, the Progress page, or the Workout History page. It is shared
/// between viewing your own activities and viewing someone else's activity,
/// and shows:
///
///   * The activity summary (distance, duration, pace, avg speed)
///   * A 3D flyover replay launcher
///   * A 2D route map with a speed-gradient polyline
///   * Detailed stats (started/ended, calories, elevation, tracking points)
///   * The "Ran with you" section listing concurrent runners
///
/// For the current user's own activities, the AppBar also exposes an
/// "Export GPX" action that copies a GPX representation of the route to the
/// clipboard.
///
/// Liking stays on feed cards; for your own activities you can export GPX or
/// delete the exercise (with confirmation).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/maplibre_config.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/tracking/widgets/activity_feed_card.dart';
import 'package:fake_strava/home/flyover_replay_page_stub.dart'
    if (dart.library.io) 'package:fake_strava/home/flyover_replay_page.dart';

/// Detail view for a single tracking session / activity.
///
/// Used by both the Home feed and the Progress page when the user taps an
/// activity card (their own or someone they follow).
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

  /// Title shown in the AppBar and as the flyover replay heading.
  ///
  /// `actorTitle` arrives as `'You'` for the current user's own activities and
  /// as `'@username'` for someone else's. We turn the former into the
  /// possessive `'Your Activity'` so the AppBar reads naturally instead of
  /// the ungrammatical `'You Activity'`.
  String get _pageTitle =>
      actorTitle == 'You' ? 'Your Activity' : '$actorTitle Activity';

  /// True when this activity belongs to the currently signed-in user.
  bool _isOwnActivity() {
    final ownerId = sessionData['userId'] as String?;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return ownerId != null &&
        currentUserId != null &&
        ownerId == currentUserId;
  }

  /// Builds a GPX track from this session's recorded points and copies it to
  /// the clipboard. Shows a notification with the result.
  Future<void> _exportSessionGpx(BuildContext context) async {
    try {
      final pointSnapshots = await firestore
          .collection('tracking_sessions')
          .doc(sessionId)
          .collection('points')
          .orderBy('timestamp')
          .get();

      if (pointSnapshots.docs.isEmpty) {
        if (!context.mounted) return;
        AppNotification.show(
          context: context,
          message: 'No points found for this workout.',
          type: NotificationType.warning,
        );
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

      final gpx = utf8.decode(utf8.encode(buffer.toString()));
      await Clipboard.setData(ClipboardData(text: gpx));

      if (!context.mounted) return;
      AppNotification.show(
        context: context,
        message: 'GPX copied to clipboard. Paste it into a .gpx file.',
        type: NotificationType.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      AppNotification.show(
        context: context,
        message: 'Unable to export GPX.\n$error',
        type: NotificationType.error,
      );
    }
  }

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
    final secondsPerKm = durationSeconds / distanceKm;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Calculates speed in km/h for a given segment
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

  /// Returns color based on speed: green (fast) → yellow → red (slow)
  /// Assumes average running speed around 10 km/h
  Color _getSpeedColor(double speedKmh) {
    final normalized = ((speedKmh - 5) / 10).clamp(0.0, 1.0);

    if (normalized > 0.5) {
      final t = (normalized - 0.5) * 2;
      return Color.lerp(
        const Color(0xFF4CAF50), // Green
        const Color(0xFFFDD835), // Yellow
        1 - t,
      )!;
    } else {
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
    final averageSpeedLabel = averageSpeed > 0
        ? '${averageSpeed.toStringAsFixed(1)} km/h'
        : '-- km/h';

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
        elevation: 8,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        actions: [
          if (isMine) ...[
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
            IconButton(
              tooltip: 'Export GPX',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _exportSessionGpx(context),
            ),
          ],
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

          // A "valid" tracking point has finite, in-range lat/lon. Stored
          // documents occasionally contain NaN/infinity (e.g. from a bad GPS
          // fix or division by zero in upstream calculations), and those
          // would crash FlutterMap (`LatLng is not finite`) downstream.
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
                if (!isValidLatLon(lat, lon)) {
                  return null;
                }
                return LatLng(lat!, lon!);
              })
              .whereType<LatLng>()
              .toList(growable: false);

          final elevations = snapshot.data!.docs
              .map((doc) {
                final data = doc.data();
                final lat = (data['latitude'] as num?)?.toDouble();
                final lon = (data['longitude'] as num?)?.toDouble();
                if (!isValidLatLon(lat, lon)) {
                  return null;
                }
                final raw = (data['elevation'] as num?)?.toDouble();
                return (raw != null && raw.isFinite) ? raw : 0.0;
              })
              .whereType<double>()
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
                elevations: elevations,
                title: _pageTitle,
                durationSeconds: durationSeconds,
                distanceKm: distanceKm,
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: EdgeInsets.zero,
                child: _RouteMapView(
                  points: points,
                  initialCenter: center,
                  polylines: points.length >= 2
                      ? _buildSpeedGradientPolylines(points, durationSeconds)
                      : const <Polyline>[],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Details',
                      style: AppTypography.headingSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: kBrandBlack,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            icon: Icons.schedule,
                            label: 'Started',
                            value: _formatDateTime(startedAt),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _detailTile(
                            icon: Icons.flag,
                            label: 'Ended',
                            value: _formatDateTime(endedAt),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            icon: Icons.local_fire_department,
                            label: 'Calories',
                            value: '${calories.toStringAsFixed(0)} kcal',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _detailTile(
                            icon: Icons.terrain,
                            label: 'Elevation',
                            value: '+${elevation.toStringAsFixed(0)} m',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _detailTile(
                      icon: Icons.location_on_outlined,
                      label: 'Tracking points',
                      value: '$pointsCount',
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity summary',
                style: AppTypography.labelSmall.copyWith(
                  color: kTextSecondary,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  dateLabel,
                  style: AppTypography.labelSmall.copyWith(
                    color: kBrandOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                distanceKm.toStringAsFixed(2),
                style: AppTypography.displayMedium.copyWith(
                  color: kBrandBlack,
                  fontWeight: FontWeight.w900,
                  fontSize: 52,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'km',
                style: AppTypography.headingSmall.copyWith(
                  color: kTextSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total distance',
            style: AppTypography.bodySmall.copyWith(
              color: kTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: durationLabel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStat(
                  icon: Icons.speed,
                  label: 'Pace',
                  value: paceLabel,
                ),
              ),
              const SizedBox(width: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kBrandOrange.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: kBrandOrange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: kTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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
                color: kBrandBlack,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flyoverCard({
    required BuildContext context,
    required List<LatLng> points,
    required List<double>? elevations,
    required String title,
    required int durationSeconds,
    required double distanceKm,
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.threed_rotation_rounded,
                  color: kBrandOrange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3D flyover replay',
                      style: AppTypography.headingSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: kBrandBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: kTextSecondary,
                        height: 1.3,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                            elevations: elevations,
                            durationSeconds: durationSeconds,
                            distanceKm: distanceKm,
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
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
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
              Icon(icon, size: 14, color: kBrandOrange),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: kTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: kBrandBlack,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

}

/// Embedded 2D route map with overlay pills for the route label and a
/// tappable map-style switcher.
///
/// Owns its own `_mapThemeIndex` state so the user can cycle through
/// [kMapThemeOptions] (the same set used by the live tracking page).
/// Polylines and the initial camera center are pre-built by the parent so
/// the speed-gradient calculations stay co-located with the rest of the
/// activity detail logic.
class _RouteMapView extends StatefulWidget {
  const _RouteMapView({
    required this.points,
    required this.initialCenter,
    required this.polylines,
  });

  final List<LatLng> points;
  final LatLng initialCenter;
  final List<Polyline> polylines;

  @override
  State<_RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<_RouteMapView> {
  int _mapThemeIndex = 0;

  void _cycleMapTheme() {
    setState(() {
      _mapThemeIndex = (_mapThemeIndex + 1) % kMapThemeOptions.length;
    });
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

  /// Glass-styled overlay pill matching the rest of the map chrome.
  Widget _glassPill({required Widget child, VoidCallback? onTap}) {
    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) {
      return pill;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: pill,
      ),
    );
  }

  /// Builds an [LatLngBounds] only when the supplied points span a
  /// non-trivial area. Identical or near-identical points produce a
  /// degenerate (zero-area) bounds, and asking [CameraFit.bounds] to fit
  /// zero area requires infinite zoom — which the projection then turns
  /// into `NaN`, crashing the map with `LatLng is not finite`.
  LatLngBounds? _safeRouteBounds(List<LatLng> points) {
    if (points.length < 2) return null;
    final bounds = LatLngBounds.fromPoints(points);
    final latSpan = (bounds.north - bounds.south).abs();
    final lonSpan = (bounds.east - bounds.west).abs();
    // ~1e-6 degrees is roughly 0.1 m — anything smaller than this and the
    // user effectively didn't move, so we'd rather just center on the start
    // point at a sane fixed zoom.
    if (latSpan < 1e-6 && lonSpan < 1e-6) return null;
    return bounds;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final theme = kMapThemeOptions[_mapThemeIndex];
    final routeBounds = _safeRouteBounds(points);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppBorderRadius.lg),
      child: SizedBox(
        height: 320,
        child: points.isEmpty
            ? const EmptyStateWidget(
                icon: Icons.route_outlined,
                title: 'No route points',
                subtitle:
                    'This activity does not have enough location data to draw a route.',
              )
            : Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: widget.initialCenter,
                      initialZoom: 15,
                      // Constrain zoom to the range standard raster tiles
                      // support. Without these, pinch-zooming past ~zoom 22
                      // or below ~zoom 1 can push flutter_map's projection
                      // math into NaN territory mid-gesture and crash the
                      // map with "LatLng is not finite".
                      minZoom: 2,
                      maxZoom: 19,
                      // Keep the camera inside the WGS84 world so users
                      // can't pan into the projection's singular regions.
                      cameraConstraint: CameraConstraint.contain(
                        bounds: LatLngBounds(
                          const LatLng(-85, -180),
                          const LatLng(85, 180),
                        ),
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
                      if (widget.polylines.isNotEmpty)
                        PolylineLayer(polylines: widget.polylines),
                      MarkerLayer(
                        markers: [
                          if (points.isNotEmpty)
                            Marker(
                              point: points.first,
                              width: 40,
                              height: 40,
                              child: _routeMarker(
                                color: const Color(0xFF2E7D32),
                                icon: Icons.play_arrow,
                                iconSize: 18,
                              ),
                            ),
                          if (points.length >= 2)
                            Marker(
                              point: points.last,
                              width: 40,
                              height: 40,
                              child: _routeMarker(
                                color: const Color(0xFFC62828),
                                icon: Icons.flag,
                                iconSize: 16,
                              ),
                            ),
                        ],
                      ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(theme.attribution),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _glassPill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.route,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Route map',
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Tooltip(
                      message: 'Map style: ${theme.label}',
                      child: _glassPill(
                        onTap: _cycleMapTheme,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.layers_outlined,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              theme.label,
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Skeleton placeholder shown while the activity detail page is loading.
class _ActivityDetailLoadingState extends StatelessWidget {
  const _ActivityDetailLoadingState();

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
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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
