import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/home/social_repository.dart';
import 'package:fake_strava/tracking/pages/activity_detail_page.dart';
import 'package:fake_strava/tracking/services/tracking_repository.dart';

Future<void> confirmAndDeleteExercise(
  BuildContext context, {
  required FirebaseFirestore firestore,
  required String sessionId,
  required String userId,
  bool popRouteAfterDelete = false,
  VoidCallback? onDeleted,
}) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete exercise?'),
          content: const Text(
            'Permanently remove this exercise and all route data?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kError,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ==
      true;
  if (!ok || !context.mounted) return;
  try {
    await TrackingRepository(firestore: firestore).deleteCompletedSessionForUser(
      sessionId: sessionId,
      userId: userId,
    );
    onDeleted?.call();
    if (!context.mounted) return;
    AppNotification.show(
      context: context,
      message: 'Exercise deleted.',
      type: NotificationType.success,
    );
    if (popRouteAfterDelete) Navigator.of(context).pop(true);
  } catch (e) {
    if (!context.mounted) return;
    AppNotification.show(
      context: context,
      message: 'Unable to delete exercise.\n$e',
      type: NotificationType.error,
    );
  }
}

/// Strava-style route thumbnail for activity feed cards (read-once, no stream).
class _ActivityRoutePreviewMap extends StatefulWidget {
  const _ActivityRoutePreviewMap({
    required this.firestore,
    required this.sessionId,
  });

  final FirebaseFirestore firestore;
  final String sessionId;

  @override
  State<_ActivityRoutePreviewMap> createState() =>
      _ActivityRoutePreviewMapState();
}

class _ActivityRoutePreviewMapState extends State<_ActivityRoutePreviewMap> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _pointsFuture;

  @override
  void initState() {
    super.initState();
    _pointsFuture = widget.firestore
        .collection('tracking_sessions')
        .doc(widget.sessionId)
        .collection('points')
        .orderBy('timestamp')
        .limit(1200)
        .get();
  }

  static List<LatLng> _parsePoints(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs
        .map((doc) {
          final data = doc.data();
          final lat = (data['latitude'] as num?)?.toDouble();
          final lon = (data['longitude'] as num?)?.toDouble();
          if (lat == null || lon == null) {
            return null;
          }
          return LatLng(lat, lon);
        })
        .whereType<LatLng>()
        .toList(growable: false);
  }

  /// Keeps polyline light for small previews.
  static List<LatLng> _decimate(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) {
      return points;
    }
    final step = points.length / maxPoints;
    final out = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      final idx = (i * step).floor().clamp(0, points.length - 1);
      out.add(points[idx]);
    }
    if (out.last != points.last) {
      out.add(points.last);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final polyStroke =
        (3.25 * math.sqrt(dpr)).clamp(2.75, 5.5);
    final polyBorder =
        (1.1 * math.sqrt(dpr)).clamp(0.85, 2.0);

    return AspectRatio(
      aspectRatio: 1.5,
      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _pointsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ColoredBox(
              color: const Color(0xFFE8E8E8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kBrandOrange.withValues(alpha: 0.85),
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ColoredBox(
              color: const Color(0xFFEDEDED),
              child: Icon(
                Icons.route_outlined,
                color: Colors.black.withValues(alpha: 0.22),
                size: 28,
              ),
            );
          }

          var points = _parsePoints(snapshot.data!);
          if (points.length < 2) {
            return ColoredBox(
              color: const Color(0xFFEDEDED),
              child: Center(
                child: Text(
                  'No route',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.black.withValues(alpha: 0.38),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          points = _decimate(points, 140);
          final bounds = LatLngBounds.fromPoints(points);

          return Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  ),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: kMapThemeRasterHdPreview.urlTemplate,
                    subdomains: kMapThemeRasterHdPreview.subdomains,
                    userAgentPackageName: 'com.company.fakestrava',
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: polyStroke,
                        color: kBrandOrange,
                        borderStrokeWidth: polyBorder,
                        borderColor: Colors.white.withValues(alpha: 0.92),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 6,
                bottom: 4,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '© OSM',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.black.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ActivityFeedCard extends StatelessWidget {
  const ActivityFeedCard({
    super.key,
    required this.sessionId,
    required this.data,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.firestore,
    required this.socialRepository,
    required this.durationLabel,
    this.onExerciseListChanged,
  });

  final String sessionId;
  final Map<String, dynamic> data;
  final String currentUserId;
  final String currentDisplayName;
  final FirebaseFirestore firestore;
  final SocialRepository socialRepository;
  final String Function(int seconds) durationLabel;

  /// When set (e.g. on Workout History), called after a session is deleted or
  /// when returning from detail after a delete, so the parent can refresh.
  final VoidCallback? onExerciseListChanged;

  @override
  Widget build(BuildContext context) {
    final actorId = data['userId'] as String?;
    final isMine = actorId == currentUserId;
    final distanceKm =
        ((data['distanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
    final calories = (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
    final elevation = (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (data['activeDurationSeconds'] as num?)?.toInt() ?? 0;

    final startedAt = DateTime.tryParse(data['startedAt'] as String? ?? '');
    final startedLabel = startedAt == null
        ? 'Unknown time'
        : '${startedAt.toLocal().year}-${startedAt.toLocal().month.toString().padLeft(2, '0')}-${startedAt.toLocal().day.toString().padLeft(2, '0')} ${startedAt.toLocal().hour.toString().padLeft(2, '0')}:${startedAt.toLocal().minute.toString().padLeft(2, '0')}';

    final likesCollection = firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('likes');

    final fallbackUsername =
        (data['username'] as String?)?.trim().isNotEmpty == true
        ? (data['username'] as String)
        : (actorId != null && actorId.length >= 6
              ? actorId.substring(0, 6)
              : 'runner');
    final fallbackDisplayName =
        (data['userDisplayName'] as String?)?.trim().isNotEmpty == true
        ? (data['userDisplayName'] as String)
        : null;

    if (actorId == null) {
      return _buildFeedCard(
        context: context,
        actorUsername: fallbackUsername,
        actorDisplayName: fallbackDisplayName,
        isMine: isMine,
        startedLabel: startedLabel,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        calories: calories,
        elevation: elevation,
        likesCollection: likesCollection,
        onExerciseListChanged: onExerciseListChanged,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('users').doc(actorId).snapshots(),
      builder: (context, userSnapshot) {
        final profileData = userSnapshot.data?.data();
        final profileUsername =
            (profileData?['username'] as String?)?.trim().isNotEmpty == true
            ? (profileData?['username'] as String)
            : fallbackUsername;
        final profileDisplayName =
            (profileData?['displayName'] as String?)?.trim().isNotEmpty == true
            ? (profileData?['displayName'] as String)
            : fallbackDisplayName;

        return _buildFeedCard(
          context: context,
          actorUsername: profileUsername,
          actorDisplayName: profileDisplayName,
          isMine: isMine,
          startedLabel: startedLabel,
          distanceKm: distanceKm,
          durationSeconds: durationSeconds,
          calories: calories,
          elevation: elevation,
          likesCollection: likesCollection,
          onExerciseListChanged: onExerciseListChanged,
        );
      },
    );
  }

  Widget _buildFeedCard({
    required BuildContext context,
    required String actorUsername,
    required String? actorDisplayName,
    required bool isMine,
    required String startedLabel,
    required double distanceKm,
    required int durationSeconds,
    required double calories,
    required double elevation,
    required CollectionReference<Map<String, dynamic>> likesCollection,
    VoidCallback? onExerciseListChanged,
  }) {
    final title = isMine ? 'You' : '@$actorUsername';
    final subtitle = actorDisplayName != null && actorDisplayName.isNotEmpty
        ? '$actorDisplayName · $startedLabel'
        : startedLabel;

    final paceLabel = durationSeconds > 0 && distanceKm > 0
        ? () {
            final secondsPerKm = durationSeconds / distanceKm;
            final pm = (secondsPerKm / 60).floor();
            final ps = (secondsPerKm % 60).round();
            return '$pm:${ps.toString().padLeft(2, '0')} /km';
          }()
        : '—';

    Widget metricTile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
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
          mainAxisSize: MainAxisSize.min,
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
                      fontSize: 10,
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
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () async {
        final deleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ActivityDetailPage(
              firestore: firestore,
              sessionId: sessionId,
              sessionData: data,
              actorTitle: title,
            ),
          ),
        );
        if (deleted == true) onExerciseListChanged?.call();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          kBrandOrange,
                          kBrandOrange.withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        (actorUsername.isNotEmpty ? actorUsername[0] : 'R')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.black.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isMine)
                    IconButton(
                      tooltip: 'Delete exercise',
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.black.withValues(alpha: 0.45),
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      onPressed: currentUserId.isEmpty
                          ? null
                          : () => confirmAndDeleteExercise(
                                context,
                                firestore: firestore,
                                sessionId: sessionId,
                                userId: currentUserId,
                                onDeleted: onExerciseListChanged,
                              ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black.withValues(alpha: 0.28),
                    size: 22,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _ActivityRoutePreviewMap(
              firestore: firestore,
              sessionId: sessionId,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: metricTile(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: '${distanceKm.toStringAsFixed(2)} km',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: metricTile(
                      icon: Icons.timer_outlined,
                      label: 'Duration',
                      value: durationLabel(durationSeconds),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: metricTile(
                      icon: Icons.speed,
                      label: 'Pace',
                      value: paceLabel,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 12,
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${calories.toStringAsFixed(0)} kcal',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.black.withValues(alpha: 0.42),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.terrain,
                    size: 12,
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '+${elevation.toStringAsFixed(0)} m',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.black.withValues(alpha: 0.42),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.06),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: likesCollection.snapshots(),
              builder: (context, likeSnapshot) {
                final likes =
                    likeSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final likeCount = likes.length;
                final liked = likes.any((doc) => doc.id == currentUserId);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isMine
                                ? null
                                : () async {
                                    await socialRepository.toggleLike(
                                      sessionId: sessionId,
                                      currentUserId: currentUserId,
                                      like: !liked,
                                      displayName: currentDisplayName,
                                    );
                                  },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: liked
                                        ? Colors.redAccent
                                        : Colors.black.withValues(alpha: 0.5),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$likeCount ${likeCount == 1 ? 'like' : 'likes'}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: liked
                                          ? Colors.redAccent
                                          : Colors.black.withValues(alpha: 0.55),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isMine)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            'Your activity',
                            style: AppTypography.labelSmall.copyWith(
                              color: kBrandOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
