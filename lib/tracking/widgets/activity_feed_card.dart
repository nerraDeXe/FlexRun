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
  final ok =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Delete exercise?',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          content: const Text(
            'Permanently remove this exercise and all route data?',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
    await TrackingRepository(
      firestore: firestore,
    ).deleteCompletedSessionForUser(sessionId: sessionId, userId: userId);
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

/// Premium route thumbnail with glass morphism effect
class _PremiumRoutePreviewMap extends StatefulWidget {
  const _PremiumRoutePreviewMap({
    required this.firestore,
    required this.sessionId,
  });

  final FirebaseFirestore firestore;
  final String sessionId;

  @override
  State<_PremiumRoutePreviewMap> createState() =>
      _PremiumRoutePreviewMapState();
}

class _PremiumRoutePreviewMapState extends State<_PremiumRoutePreviewMap> {
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
          if (lat == null || lon == null) return null;
          return LatLng(lat, lon);
        })
        .whereType<LatLng>()
        .toList(growable: false);
  }

  static List<LatLng> _decimate(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = points.length / maxPoints;
    final out = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      final idx = (i * step).floor().clamp(0, points.length - 1);
      out.add(points[idx]);
    }
    if (out.last != points.last) out.add(points.last);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final polyStroke = (3.5 * math.sqrt(dpr)).clamp(3.0, 6.0);
    final polyBorder = (1.2 * math.sqrt(dpr)).clamp(1.0, 2.2);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: AspectRatio(
        aspectRatio: 1.8,
        child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _pointsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                  ),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFF97316),
                      ),
                    ),
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: 32,
                        color: const Color(0xFF94A3B8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No route data',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            var points = _parsePoints(snapshot.data!);
            if (points.length < 2) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 32,
                        color: const Color(0xFF94A3B8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Route not available',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
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
                      padding: const EdgeInsets.all(12),
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
                          color: const Color(0xFFF97316),
                          borderStrokeWidth: polyBorder,
                          borderColor: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '© OSM',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
    final maxSpeed = (data['maxSpeedMps'] as num?)?.toDouble();

    final startedAt = DateTime.tryParse(data['startedAt'] as String? ?? '');
    final startedLabel = startedAt == null
        ? 'Unknown time'
        : _formatRelativeTime(startedAt.toLocal());

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
      return _buildPremiumCard(
        context: context,
        actorUsername: fallbackUsername,
        actorDisplayName: fallbackDisplayName,
        isMine: isMine,
        startedLabel: startedLabel,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        calories: calories,
        elevation: elevation,
        maxSpeed: maxSpeed,
        likesCollection: likesCollection,
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

        return _buildPremiumCard(
          context: context,
          actorUsername: profileUsername,
          actorDisplayName: profileDisplayName,
          isMine: isMine,
          startedLabel: startedLabel,
          distanceKm: distanceKm,
          durationSeconds: durationSeconds,
          calories: calories,
          elevation: elevation,
          maxSpeed: maxSpeed,
          likesCollection: likesCollection,
        );
      },
    );
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  String _formatPace(int durationSeconds, double distanceKm) {
    if (durationSeconds <= 0 || distanceKm <= 0) return '—';
    final secondsPerKm = durationSeconds / distanceKm;
    final pm = (secondsPerKm / 60).floor();
    final ps = (secondsPerKm % 60).round();
    return '$pm:${ps.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(double? maxSpeedMps) {
    if (maxSpeedMps == null || maxSpeedMps <= 0) return '—';
    final speedKmh = maxSpeedMps * 3.6;
    return '${speedKmh.toStringAsFixed(1)} km/h';
  }

  String _cleanDuration(String raw) {
    final parts = raw.split(':');
    if (parts.length == 3) {
      if (parts[0] == '00') {
        return '${parts[1]}:${parts[2]}'; // mm:ss
      } else {
        final h = int.tryParse(parts[0])?.toString() ?? parts[0];
        return '$h:${parts[1]}:${parts[2]}'; // h:mm:ss
      }
    }
    return raw;
  }

  Widget _buildPremiumCard({
    required BuildContext context,
    required String actorUsername,
    required String? actorDisplayName,
    required bool isMine,
    required String startedLabel,
    required double distanceKm,
    required int durationSeconds,
    required double calories,
    required double elevation,
    required double? maxSpeed,
    required CollectionReference<Map<String, dynamic>> likesCollection,
  }) {
    final paceLabel = _formatPace(durationSeconds, distanceKm);
    final speedLabel = _formatSpeed(maxSpeed);

    final String title;
    final String subtitle;
    if (isMine) {
      title = 'You';
      subtitle = '@$actorUsername · $startedLabel';
    } else if (actorDisplayName != null && actorDisplayName.isNotEmpty) {
      title = actorDisplayName;
      subtitle = '@$actorUsername · $startedLabel';
    } else {
      title = '@$actorUsername';
      subtitle = startedLabel;
    }

    return GestureDetector(
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top section with avatar and action buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    // Premium avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFF97316,
                            ).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (actorUsername.isNotEmpty ? actorUsername[0] : 'R')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // User info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action buttons
                    if (isMine)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: const Color(0xFF94A3B8),
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
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
                      ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
              // Route map preview
              _PremiumRoutePreviewMap(
                firestore: firestore,
                sessionId: sessionId,
              ),
              // Stats grid
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  children: [
                    _buildStatItem(
                      icon: Icons.straighten_rounded,
                      label: 'DISTANCE',
                      value: '${distanceKm.toStringAsFixed(2)}',
                      unit: 'km',
                    ),
                    const SizedBox(width: 8),
                    _buildStatItem(
                      icon: Icons.timer_rounded,
                      label: 'TIME',
                      value: _cleanDuration(durationLabel(durationSeconds)),
                      unit: durationLabel(durationSeconds).startsWith('00:') ? 'min' : 'hr',
                    ),
                    const SizedBox(width: 8),
                    _buildStatItem(
                      icon: Icons.speed_rounded,
                      label: 'PACE',
                      value: paceLabel,
                      unit: '/km',
                    ),
                  ],
                ),
              ),
              // Secondary metrics row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _buildMiniMetric(
                      icon: Icons.local_fire_department_rounded,
                      value: '${calories.toStringAsFixed(0)}',
                      unit: 'kcal',
                    ),
                    const SizedBox(width: 12),
                    _buildMiniMetric(
                      icon: Icons.terrain_rounded,
                      value: '+${elevation.toStringAsFixed(0)}',
                      unit: 'm',
                    ),

                    if (maxSpeed != null && maxSpeed > 0) ...[
                      const SizedBox(width: 12),
                      _buildMiniMetric(
                        icon: Icons.flash_on_rounded,
                        value: speedLabel.split(' ').first,
                        unit: 'max',
                      ),
                    ],
                  ],
                ),
              ),
              // Like and engagement section
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: likesCollection.snapshots(),
                builder: (context, likeSnapshot) {
                  final likes = likeSnapshot.data?.docs ?? const [];
                  final likeCount = likes.length;
                  final liked = likes.any((doc) => doc.id == currentUserId);

                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: const Color(0xFFE2E8F0),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Like button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isMine
                                  ? null
                                  : () async {
                                      await socialRepository.toggleLike(
                                        sessionId: sessionId,
                                        userId:
                                            currentUserId, // Changed from 'currentUserId' to 'userId'
                                        like: !liked,
                                        displayName: currentDisplayName,
                                        currentUserId: '',
                                      );
                                    },
                              borderRadius: BorderRadius.circular(30),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: liked
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      liked
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 18,
                                      color: liked
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      likeCount.toString(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: liked
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                    if (likeCount != 1)
                                      Text(
                                        ' likes',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: liked
                                              ? const Color(
                                                  0xFFEF4444,
                                                ).withValues(alpha: 0.8)
                                              : const Color(0xFF94A3B8),
                                        ),
                                      )
                                    else
                                      Text(
                                        ' like',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: liked
                                              ? const Color(
                                                  0xFFEF4444,
                                                ).withValues(alpha: 0.8)
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (isMine)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(
                                      0xFFF97316,
                                    ).withValues(alpha: 0.1),
                                    const Color(
                                      0xFFEA580C,
                                    ).withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 12,
                                    color: const Color(0xFFF97316),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Your activity',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF97316),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    bool compact = false,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 10,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFF8FAFC), Colors.white],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: const Color(0xFFF97316)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric({
    required IconData icon,
    required String value,
    required String unit,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          unit,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}
