import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fake_strava/tracking/models/tracking_snapshot.dart';
import 'package:fake_strava/tracking/services/tracking_background_service.dart';
import 'package:fake_strava/tracking/services/concurrent_runner_service.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/core/utils.dart';

const double _kTrackingPanelHandleExtent = 44.0;

class _TrackingPanelDragHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TrackingPanelDragHeaderDelegate({
    required this.collapsed,
    required this.onToggle,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  double get minExtent => _kTrackingPanelHandleExtent;

  @override
  double get maxExtent => _kTrackingPanelHandleExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: const Color(0xFFFDFDFE),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kBrandOrange.withValues(alpha: 0.35),
                        kBrandOrange.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  collapsed
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: kBrandOrange.withValues(alpha: 0.65),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TrackingPanelDragHeaderDelegate oldDelegate) {
    return oldDelegate.collapsed != collapsed;
  }
}

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage>
    with SingleTickerProviderStateMixin {
  static const LatLng _defaultCenter = LatLng(3.1390, 101.6869);
  final TrackingBackgroundService _service = TrackingBackgroundService();
  late final ConcurrentRunnerService _concurrentRunnerService;
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<TrackingSnapshot>? _snapshotSubscription;
  StreamSubscription<Position>? _foregroundPositionSubscription;
  Timer? _voiceTimer;
  Timer? _liveMetricsTimer;
  Timer? _finishHoldTimer;
  Timer? _concurrentRunnerDiscoveryTimer;

  bool _isTracking = false;
  bool _isAutoPaused = false;
  bool _isManuallyPaused = false;
  bool _isStarting = false;
  bool _isPausing = false;
  bool _isResuming = false;
  bool _isFinishing = false;
  late final AnimationController _panelController;
  double _finishHoldProgress = 0;
  bool _voicePaceEnabled = true;
  bool _hasLiveLocationFix = false;
  bool _hasCenteredOnLiveLocation = false;
  bool _followUserLocation = true;
  String? _locationStatus;
  double _distanceKm = 0;
  double _previewDistanceKm = 0;
  double _elevationGainMeters = 0;
  double _caloriesKcal = 0;
  int _points = 0;
  int _elapsedSeconds = 0;
  DateTime? _elapsedSnapshotCapturedAt;
  DateTime? _startedAt;
  String? _activeRouteSessionId;
  LatLng? _currentPosition;
  LatLng? _lastTrackedPoint;
  LatLng _mapCenter = _defaultCenter;
  double _mapZoom = 15.5;
  BoxConstraints? _panelLayoutConstraints;
  double _panelLayoutTopInset = 0;
  double _panelLayoutBottomInset = 0;
  int _mapThemeIndex = 0;
  bool _ghostMode = false; // Privacy mode - don't show location to others
  double _currentBearing = 0; // Direction of travel

  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.detached && _isTracking) {
          _service.cancelTracking();
        }
      },
    );
    _concurrentRunnerService = ConcurrentRunnerService(
      firestore: FirebaseFirestore.instance,
    );
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _hydrateState();
    _startForegroundPointerStream();
    _setupVoicePace();
    _snapshotSubscription = _service.updates.listen((
      TrackingSnapshot snapshot,
    ) {
      if (!mounted) {
        return;
      }
      final wasTracking = _isTracking;
      setState(() {
        if (snapshot.sessionId != null &&
            snapshot.sessionId != _activeRouteSessionId &&
            snapshot.isTracking) {
          _activeRouteSessionId = snapshot.sessionId;
          _routePoints.clear();
        }
        _isTracking = snapshot.isTracking;
        _isAutoPaused = snapshot.isAutoPaused;
        _isManuallyPaused = snapshot.isManuallyPaused;
        _distanceKm = snapshot.distanceMeters / 1000;
        _previewDistanceKm = _distanceKm;
        _elevationGainMeters = snapshot.elevationGainMeters;
        _caloriesKcal = snapshot.caloriesKcal;
        _points = snapshot.points;
        _elapsedSeconds = snapshot.elapsedSeconds;
        _elapsedSnapshotCapturedAt = DateTime.now();
        _startedAt = snapshot.startedAt;
        if (snapshot.isTracking) {
          _capturePoint(snapshot);
        } else {
          _activeRouteSessionId = null;
          _lastTrackedPoint = null;
          _routePoints.clear();
          if (!_hasLiveLocationFix) {
            _currentPosition = null;
            _mapCenter = _defaultCenter;
          }
        }
      });
      if (!wasTracking && _isTracking) {
        _startVoiceAnnouncements();
        _startConcurrentRunnerDiscovery();
      } else if (wasTracking && !_isTracking) {
        _cancelFinishHold();
        _stopVoiceAnnouncements();
        _stopConcurrentRunnerDiscovery();
      }
      _syncLiveMetricsTimer();
    });
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _snapshotSubscription?.cancel();
    _foregroundPositionSubscription?.cancel();
    _finishHoldTimer?.cancel();
    _concurrentRunnerDiscoveryTimer?.cancel();
    _stopVoiceAnnouncements();
    _stopLiveMetricsTimer();
    _stopConcurrentRunnerDiscovery();
    _tts.stop();
    _panelController.dispose();
    super.dispose();
  }

  Future<void> _setupVoicePace() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
  }

  void _startVoiceAnnouncements() {
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _announcePace();
    });
  }

  void _stopVoiceAnnouncements() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
  }

  Future<void> _announcePace() async {
    final distanceKm = _displayDistanceKm();
    if (!_voicePaceEnabled || !_isTracking || _isPaused || distanceKm <= 0) {
      return;
    }
    final pace = _paceMinPerKm();
    if (pace <= 0) {
      return;
    }
    final wholeMinutes = pace.floor();
    final seconds = ((pace - wholeMinutes) * 60).round();
    await _tts.speak(
      'Current pace $wholeMinutes minutes ${seconds.clamp(0, 59)} seconds per kilometer',
    );
  }

  Future<void> _hydrateState() async {
    final snapshot = await _service.restoreLatestSnapshot();
    final prefs = await SharedPreferences.getInstance();
    _ghostMode = prefs.getBool('ghost_mode') ?? false;

    if (!mounted) {
      return;
    }
    setState(() {
      _isTracking = snapshot.isTracking;
      _isAutoPaused = snapshot.isAutoPaused;
      _isManuallyPaused = snapshot.isManuallyPaused;
      _distanceKm = snapshot.distanceMeters / 1000;
      _previewDistanceKm = _distanceKm;
      _elevationGainMeters = snapshot.elevationGainMeters;
      _caloriesKcal = snapshot.caloriesKcal;
      _points = snapshot.points;
      _elapsedSeconds = snapshot.elapsedSeconds;
      _elapsedSnapshotCapturedAt = DateTime.now();
      _startedAt = snapshot.startedAt;
      _activeRouteSessionId = snapshot.sessionId;
      if (snapshot.isTracking) {
        _capturePoint(snapshot);
      } else {
        _activeRouteSessionId = null;
        _lastTrackedPoint = null;
        _currentPosition = null;
        _mapCenter = _defaultCenter;
        _routePoints.clear();
      }
    });
    if (_isTracking) {
      _startVoiceAnnouncements();
    }
    _syncLiveMetricsTimer();
  }

  void _capturePoint(TrackingSnapshot snapshot) {
    final latitude = sanitizeLatitude(snapshot.latitude);
    final longitude = sanitizeLongitude(snapshot.longitude);
    if (latitude == null || longitude == null) {
      return;
    }
    final point = LatLng(latitude, longitude);

    // Calculate bearing from last tracked point
    if (_lastTrackedPoint != null &&
        (_lastTrackedPoint!.latitude != point.latitude ||
         _lastTrackedPoint!.longitude != point.longitude)) {
      _currentBearing = calculateBearing(
        _lastTrackedPoint!.latitude,
        _lastTrackedPoint!.longitude,
        point.latitude,
        point.longitude,
      );
    }

    if (!_hasLiveLocationFix) {
      _currentPosition = point;
    }
    _lastTrackedPoint = point;
    if (_routePoints.length <= 1) {
      _mapCenter = point;
    }
    if (_routePoints.isEmpty ||
        _routePoints.last.latitude != point.latitude ||
        _routePoints.last.longitude != point.longitude) {
      _routePoints.add(point);
    }
  }

  Future<void> _startForegroundPointerStream() async {
    if (kIsWeb) {
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _locationStatus = 'Turn on location services');
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _locationStatus = 'Location permission required');
      }
      return;
    }

    await _foregroundPositionSubscription?.cancel();
    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      );
      _applyLivePosition(initial);
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _applyLivePosition(lastKnown);
        }
      } catch (_) {}
    }

    _foregroundPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _buildLocationSettings(),
        ).listen(
          (Position position) => _applyLivePosition(position),
          onError: (_) {
            if (mounted) {
              setState(() => _locationStatus = 'Waiting for GPS signal...');
            }
          },
        );
  }

  void _applyLivePosition(Position position) {
    if (!mounted) {
      return;
    }
    if (!isValidWgs84(position.latitude, position.longitude)) {
      return;
    }
    final point = LatLng(position.latitude, position.longitude);
    final shouldCenterNow = !_hasCenteredOnLiveLocation;
    setState(() {
      _hasLiveLocationFix = true;
      _currentPosition = point;
      _locationStatus = position.isMocked
          ? 'Mock location detected on device'
          : null;
      if (shouldCenterNow) {
        _hasCenteredOnLiveLocation = true;
        _mapCenter = point;
      }
    });
    if (_followUserLocation || shouldCenterNow) {
      _mapCenter = point;
      _mapController.move(point, _mapZoom, offset: _userFollowMapOffset());
    }
    _updatePreviewDistance(point, position.accuracy);
  }

  /// Nudge the focused location upward so it sits nearer the middle of the map
  /// visible above the run sheet (see [MapController.move] `offset`).
  Offset _userFollowMapOffset() {
    var obscured = _obscuredMapBottomLogicalPx;
    if (obscured <= 0 && mounted) {
      const collapsedPanelHeight = 248.0;
      final bottomInset = MediaQuery.paddingOf(context).bottom;
      const actionBarVerticalPadding = 10.0;
      const actionBarButtonHeight = 52.0;
      obscured =
          collapsedPanelHeight +
          bottomInset +
          actionBarVerticalPadding * 2 +
          actionBarButtonHeight;
    }
    if (obscured <= 0) {
      return Offset.zero;
    }
    return Offset(0, -obscured * 0.5);
  }

  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
  }

  void _zoomMap(double delta) {
    final nextZoom = (_mapZoom + delta).clamp(3.0, 18.0).toDouble();
    if (_followUserLocation && _currentPosition != null) {
      _mapController.move(
        _currentPosition!,
        nextZoom,
        offset: _userFollowMapOffset(),
      );
    } else {
      _mapController.move(_mapCenter, nextZoom);
    }
  }

  void _recenterToUser() {
    final point = _currentPosition;
    if (point == null) {
      return;
    }
    setState(() {
      _followUserLocation = true;
      _mapCenter = point;
    });
    _mapController.move(point, _mapZoom, offset: _userFollowMapOffset());
  }

  void _updatePreviewDistance(LatLng current, double accuracyMeters) {
    if (!_isTracking || _isPaused || accuracyMeters > 30) {
      return;
    }
    final anchor = _lastTrackedPoint;
    if (anchor == null) {
      return;
    }
    final previewMeters = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      current.latitude,
      current.longitude,
    );
    if (previewMeters < 0.5 || previewMeters > 150) {
      return;
    }
    final nextDistanceKm = _distanceKm + (previewMeters / 1000);
    if (nextDistanceKm <= _previewDistanceKm + 0.0001) {
      return;
    }
    setState(() {
      _previewDistanceKm = nextDistanceKm;
    });
  }

  void _syncLiveMetricsTimer() {
    _stopLiveMetricsTimer();
    if (!_isTracking) {
      return;
    }
    _liveMetricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _stopLiveMetricsTimer() {
    _liveMetricsTimer?.cancel();
    _liveMetricsTimer = null;
  }

  double _displayDistanceKm() => math.max(_distanceKm, _previewDistanceKm);

  bool get _isPaused => _isAutoPaused || _isManuallyPaused;

  int _activeElapsedSeconds() {
    if (!_isTracking || _isPaused) {
      return _elapsedSeconds;
    }
    final capturedAt = _elapsedSnapshotCapturedAt;
    if (capturedAt == null) {
      return _elapsedSeconds;
    }
    final extra = DateTime.now().difference(capturedAt).inSeconds;
    return _elapsedSeconds + (extra > 0 ? extra : 0);
  }

  double _paceMinPerKm() {
    final distanceKm = _displayDistanceKm();
    if (distanceKm <= 0) {
      return 0;
    }
    final elapsedMinutes = _activeElapsedSeconds() / 60;
    if (elapsedMinutes <= 0) {
      return 0;
    }
    return elapsedMinutes / distanceKm;
  }

  void _cycleMapTheme() {
    setState(() {
      _mapThemeIndex = (_mapThemeIndex + 1) % kMapThemeOptions.length;
    });
  }

  Future<void> _toggleGhostMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ghostMode = !_ghostMode;
    });
    await prefs.setBool('ghost_mode', _ghostMode);
    if (mounted) {
      AppNotification.show(
        context: context,
        message: _ghostMode ? 'Ghost mode enabled' : 'Ghost mode disabled',
        type: NotificationType.info,
      );
    }
  }

  /// Calculates speed in km/h for a given segment
  double _calculateSpeed(LatLng start, LatLng end, int durationMs) {
    if (durationMs <= 0) return 0;
    // Approximate distance in km using Haversine formula simplified
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
    // Normalize speed: 15 km/h = fast (green), 5 km/h = slow (red)
    final normalized = ((speedKmh - 5) / 10).clamp(0.0, 1.0);

    if (normalized > 0.5) {
      // Green to yellow
      final t = (normalized - 0.5) * 2;
      return Color.lerp(
        const Color(0xFF4CAF50), // Green
        const Color(0xFFFDD835), // Yellow
        1 - t,
      )!;
    } else {
      // Yellow to red
      final t = normalized * 2;
      return Color.lerp(
        const Color(0xFFF44336), // Red
        const Color(0xFFFDD835), // Yellow
        1 - t,
      )!;
    }
  }

  List<Polyline> _buildSpeedGradientPolylines(
    List<LatLng> points,
    int totalDurationSeconds,
  ) {
    final usable = points
        .where((p) => isValidWgs84(p.latitude, p.longitude))
        .toList(growable: false);
    if (usable.length < 2) return [];

    final polylines = <Polyline>[];
    final segmentDurationMs = totalDurationSeconds > 0
        ? (totalDurationSeconds * 1000) ~/ (usable.length - 1)
        : 1000; // Default 1 second per segment if no time elapsed

    for (int i = 0; i < usable.length - 1; i++) {
      final start = usable[i];
      final end = usable[i + 1];
      final speed = _calculateSpeed(start, end, segmentDurationMs);
      final color = _getSpeedColor(speed);

      polylines.add(
        Polyline(points: [start, end], strokeWidth: 6, color: color),
      );
    }

    return polylines;
  }

  /// Starts broadcasting this user's location and discovering nearby runners
  void _startConcurrentRunnerDiscovery() {
    _concurrentRunnerDiscoveryTimer?.cancel();
    _concurrentRunnerDiscoveryTimer = Timer.periodic(
      const Duration(seconds: 75), // 60-90 seconds as recommended
      (_) => _broadcastAndDiscoverConcurrentRunners(),
    );
  }

  /// Stops broadcasting and discovery
  void _stopConcurrentRunnerDiscovery() {
    _concurrentRunnerDiscoveryTimer?.cancel();
    _concurrentRunnerDiscoveryTimer = null;
    if (_activeRouteSessionId != null) {
      _concurrentRunnerService.stopBroadcasting(_activeRouteSessionId!);
    }
  }

  /// Broadcasts current location and discovers nearby runners
  Future<void> _broadcastAndDiscoverConcurrentRunners() async {
    if (!_isTracking ||
        _currentPosition == null ||
        _activeRouteSessionId == null ||
        _startedAt == null) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final pace = _paceMinPerKm();

    // Broadcast current location
    await _concurrentRunnerService.broadcastLiveLocation(
      userId: currentUser.uid,
      displayName: widget.displayName,
      sessionId: _activeRouteSessionId!,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      distanceKm: _displayDistanceKm(),
      elapsedSeconds: _activeElapsedSeconds(),
      currentPaceMinPerKm: pace,
      isGhostMode: _ghostMode,
    );

    // Query for nearby runners
    final nearbyRunners = await _concurrentRunnerService.findNearbyRunners(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );

    if (nearbyRunners.isEmpty) return;

    // Filter relevant runners
    final relevantRunners = _concurrentRunnerService.filterRelevantRunners(
      candidates: nearbyRunners,
      userLatitude: _currentPosition!.latitude,
      userLongitude: _currentPosition!.longitude,
      userBearing: _currentBearing,
      userStartTime: _startedAt!,
    );

    if (relevantRunners.isEmpty) return;

    // Show notifications for new runners
    for (final runner in relevantRunners) {
      _showConcurrentRunnerNotification(runner);
    }
  }

  /// Shows a toast notification when a concurrent runner is nearby
  void _showConcurrentRunnerNotification(
    dynamic runner, // Using dynamic to avoid import issues
  ) {
    AppNotification.show(
      context: context,
      message: '${runner.displayName} is nearby on this route!',
      type: NotificationType.info,
      duration: const Duration(seconds: 5),
    );
  }

  bool get _canHoldToFinish =>
      !kIsWeb && _isTracking && !_isStarting && !_isPausing && !_isResuming;

  void _startFinishHold() {
    if (!_canHoldToFinish || _isFinishing) {
      return;
    }
    HapticFeedback.mediumImpact();
    _finishHoldTimer?.cancel();
    final startedAt = DateTime.now();
    setState(() {
      _finishHoldProgress = 0;
    });
    _finishHoldTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final nextProgress = (elapsedMs / 3000).clamp(0.0, 1.0);
      if (nextProgress >= 1.0) {
        timer.cancel();
        _finishHoldTimer = null;
        HapticFeedback.heavyImpact();
        _finishWorkout();
        return;
      }
      setState(() {
        _finishHoldProgress = nextProgress;
      });
    });
  }

  void _cancelFinishHold() {
    if (_isFinishing) {
      return;
    }
    _finishHoldTimer?.cancel();
    _finishHoldTimer = null;
    if (_finishHoldProgress > 0) {
      setState(() {
        _finishHoldProgress = 0;
      });
    }
  }

  void _resetTrackingPanelState() {
    _finishHoldTimer?.cancel();
    _finishHoldTimer = null;
    _stopVoiceAnnouncements();
    _stopLiveMetricsTimer();
    _isTracking = false;
    _isAutoPaused = false;
    _isManuallyPaused = false;
    _distanceKm = 0;
    _previewDistanceKm = 0;
    _elevationGainMeters = 0;
    _caloriesKcal = 0;
    _points = 0;
    _elapsedSeconds = 0;
    _elapsedSnapshotCapturedAt = null;
    _startedAt = null;
    _activeRouteSessionId = null;
    _lastTrackedPoint = null;
    _routePoints.clear();
    _finishHoldProgress = 0;
  }

  Future<void> _finishWorkout() async {
    if (_isFinishing) {
      return;
    }
    setState(() {
      _isFinishing = true;
      _finishHoldProgress = 1;
    });
    try {
      await _service.stopTracking();
      
      // Wait for the background service to process the stop and broadcast the update.
      // This prevents the user from closing the app prematurely while it's still saving.
      try {
        await _service.updates
            .firstWhere((snapshot) => !snapshot.isTracking)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Timeout occurred, proceed with UI reset anyway
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _resetTrackingPanelState();
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      AppNotification.show(
        context: context,
        message: 'Workout saved. Great effort!',
        type: NotificationType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      AppNotification.show(
        context: context,
        message: error.toString(),
        type: NotificationType.error,
      );
    }
  }

  String _elapsedLabel() {
    if (_startedAt == null && _elapsedSeconds == 0) {
      return '--:--:--';
    }
    final elapsed = Duration(seconds: _activeElapsedSeconds());
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _trackingStatusLabel {
    if (!_isTracking) {
      return 'Ready';
    }
    if (_isManuallyPaused) {
      return 'Paused';
    }
    if (_isAutoPaused) {
      return 'Auto-paused';
    }
    return 'Recording';
  }

  Color get _trackingStatusColor {
    if (!_isTracking) {
      return const Color(0xFF607D8B);
    }
    if (_isPaused) {
      return const Color(0xFFFFA726);
    }
    return const Color(0xFF2E7D32);
  }

  Widget _buildIconGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool active = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? [
                  kBrandOrange.withValues(alpha: 0.95),
                  kBrandOrange.withValues(alpha: 0.75),
                ]
              : [
                  Colors.black.withValues(alpha: 0.48),
                  Colors.black.withValues(alpha: 0.36),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.3 : 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? kBrandOrange : Colors.black).withValues(
              alpha: 0.22,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Tooltip(
            message: tooltip ?? '',
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusInfoChip({
    required IconData icon,
    required String label,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone.withValues(alpha: 0.14), tone.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStart() async {
    setState(() {
      _isStarting = true;
      _followUserLocation = true;
    });
    try {
      HapticFeedback.lightImpact();
      await _service.startTracking();
      await _startForegroundPointerStream();
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context: context,
          message: error.toString(),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _handlePauseResume() async {
    setState(() {
      if (_isPaused) {
        _isResuming = true;
      } else {
        _isPausing = true;
      }
    });
    try {
      HapticFeedback.lightImpact();
      if (_isPaused) {
        await _service.resumeTracking();
      } else {
        await _service.pauseTracking();
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context: context,
          message: error.toString(),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPausing = false;
          _isResuming = false;
        });
      }
    }
  }

  bool get _isPanelCollapsed => _panelController.value < 0.5;

  void _togglePanelCollapse() {
    if (_panelController.value > 0.5) {
      _panelController.reverse();
    } else {
      _panelController.forward();
    }
  }

  void _onPanelDragStart(DragStartDetails details) {
    _panelController.stop();
  }

  void _onPanelDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta;
    if (delta == null) return;
    // Delta > 0 means dragging down (shrinking)
    _panelController.value -= delta / 180.0;
  }

  void _onPanelDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) {
      _panelController.reverse(); // Fling down
    } else if (velocity < -300) {
      _panelController.forward(); // Fling up
    } else if (_panelController.value > 0.5) {
      _panelController.forward();
    } else {
      _panelController.reverse();
    }
  }

  void _syncPanelLayoutFrom(BoxConstraints constraints, BuildContext context) {
    _panelLayoutConstraints = constraints;
    _panelLayoutTopInset = MediaQuery.paddingOf(context).top;
    _panelLayoutBottomInset = MediaQuery.paddingOf(context).bottom;
  }

  /// Panel height and bottom chrome height for the tracking action bar.
  (double panelHeight, double trackingBottomChromeHeight)
  _resolvePanelGeometry() {
    const collapsedPanelHeight = 248.0;
    const actionBarVerticalPadding = 10.0;
    const actionBarButtonHeight = 52.0;
    final constraints = _panelLayoutConstraints;
    final topInset = _panelLayoutTopInset;
    final bottomInset = _panelLayoutBottomInset;
    final trackingBottomChromeHeight =
        bottomInset + actionBarVerticalPadding * 2 + actionBarButtonHeight;
    if (constraints == null) {
      return (collapsedPanelHeight, trackingBottomChromeHeight);
    }
    final expandedPanelHeight = math.max(
      collapsedPanelHeight,
      constraints.maxHeight - topInset - 16 - trackingBottomChromeHeight,
    );
    final panelHeight = lerpDouble(
      collapsedPanelHeight,
      expandedPanelHeight,
      _panelController.value,
    )!;
    return (panelHeight, trackingBottomChromeHeight);
  }

  /// Run card + bottom controls (logical px); uses live [_panelController] value.
  double get _obscuredMapBottomLogicalPx {
    final (panelHeight, chrome) = _resolvePanelGeometry();
    return panelHeight + chrome;
  }


  /// Start / Pause / Finish — used in a floating bar above the stats sheet.
  Widget _buildFloatingTrackingControls() {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: !(kIsWeb || _isTracking || _isStarting),
            label: 'Start workout',
            hint: 'Starts recording your workout',
            child: Tooltip(
              message: kIsWeb || _isTracking || _isStarting
                  ? 'Start unavailable'
                  : 'Start workout',
              child: FilledButton.icon(
                onPressed: kIsWeb || _isTracking || _isStarting
                    ? null
                    : _handleStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_isStarting ? 'Starting...' : 'Start'),
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            enabled: !kIsWeb && _isTracking && !_isPausing && !_isResuming,
            label: _isPaused ? 'Resume workout' : 'Pause workout',
            hint: _isPaused
                ? 'Resumes a paused workout'
                : 'Pauses the current workout',
            child: Tooltip(
              message: _isPaused ? 'Resume' : 'Pause',
              child: OutlinedButton.icon(
                onPressed: !kIsWeb && _isTracking && !_isPausing && !_isResuming
                    ? _handlePauseResume
                    : null,
                icon: Icon(
                  _isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                label: Text(
                  _isPaused
                      ? (_isResuming ? 'Resuming...' : 'Resume')
                      : (_isPausing ? 'Pausing...' : 'Pause'),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: kBrandBlack,
                  elevation: 0,
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            enabled: _canHoldToFinish,
            label: 'Finish workout',
            hint: 'Press and hold for three seconds to save workout',
            child: Tooltip(
              message: 'Press and hold to finish',
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _canHoldToFinish
                    ? (_) => _startFinishHold()
                    : null,
                onPointerUp: (_) => _cancelFinishHold(),
                onPointerCancel: (_) => _cancelFinishHold(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20242E),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _finishHoldProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kBrandOrange.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isFinishing
                              ? Icons.check_circle
                              : Icons.stop_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isFinishing
                              ? 'Saving...'
                              : _finishHoldProgress > 0
                              ? 'Hold ${(3 - (_finishHoldProgress * 3)).ceil().clamp(1, 3)}s'
                              : 'Finish',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pace = _paceMinPerKm();
    final displayedDistanceKm = _displayDistanceKm();
    final activeMapTheme = kMapThemeOptions[_mapThemeIndex];
    final avgSpeedKmh = pace > 0 ? 60 / pace : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        _syncPanelLayoutFrom(constraints, context);

        return Scaffold(
          body: AnimatedBuilder(
            animation: _panelController,
            builder: (context, mapLayer) {
              final (panelHeight, trackingBottomChromeHeight) =
                  _resolvePanelGeometry();
              final mapControlsBottom =
                  panelHeight + trackingBottomChromeHeight + 12;
              return Stack(
                children: [
                  mapLayer!,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.06),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.62),
                                  Colors.black.withValues(alpha: 0.48),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _trackingStatusColor,
                                    borderRadius: BorderRadius.circular(99),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _trackingStatusColor.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _trackingStatusLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.48),
                                  Colors.black.withValues(alpha: 0.36),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildIconGlassButton(
                                  icon: _voicePaceEnabled
                                      ? Icons.volume_up
                                      : Icons.volume_off,
                                  onTap: () {
                                    setState(
                                      () => _voicePaceEnabled =
                                          !_voicePaceEnabled,
                                    );
                                  },
                                  active: _voicePaceEnabled,
                                  tooltip: _voicePaceEnabled
                                      ? 'Disable voice pace'
                                      : 'Enable voice pace',
                                ),
                                const SizedBox(width: 4),
                                _buildIconGlassButton(
                                  icon: Icons.layers_outlined,
                                  onTap: _cycleMapTheme,
                                  tooltip: 'Map style: ${activeMapTheme.label}',
                                ),
                                const SizedBox(width: 4),
                                _buildIconGlassButton(
                                  icon: _ghostMode
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  onTap: _toggleGhostMode,
                                  tooltip: _ghostMode
                                      ? 'Ghost mode on'
                                      : 'Ghost mode off',
                                  active: _ghostMode,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: mapControlsBottom,
                    child: IgnorePointer(
                      ignoring: _panelController.value > 0.5,
                      child: FadeTransition(
                        opacity: ReverseAnimation(_panelController),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.40),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildIconGlassButton(
                                icon: Icons.my_location,
                                onTap: _recenterToUser,
                                active: _followUserLocation,
                                tooltip: 'Center on location',
                              ),
                              const SizedBox(height: 8),
                              _buildIconGlassButton(
                                icon: Icons.add,
                                onTap: () => _zoomMap(1),
                                tooltip: 'Zoom in',
                              ),
                              const SizedBox(height: 8),
                              _buildIconGlassButton(
                                icon: Icons.remove,
                                onTap: () => _zoomMap(-1),
                                tooltip: 'Zoom out',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: panelHeight,
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFFDFDFE),
                                const Color(0xFFF5F7FC),
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(36),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 32,
                                offset: const Offset(0, -8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: CustomScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  slivers: [
                                    SliverPersistentHeader(
                                      pinned: true,
                                      delegate:
                                          _TrackingPanelDragHeaderDelegate(
                                            collapsed: _isPanelCollapsed,
                                            onToggle: _togglePanelCollapse,
                                            onDragStart: _onPanelDragStart,
                                            onDragUpdate: _onPanelDragUpdate,
                                            onDragEnd: _onPanelDragEnd,
                                          ),
                                    ),
                                    SliverToBoxAdapter(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _elapsedLabel(),
                                                  style: const TextStyle(
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.w900,
                                                    color: kBrandBlack,
                                                    fontFeatures: [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                    letterSpacing: -0.8,
                                                  ),
                                                ),
                                              ),
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 220,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 9,
                                                    ),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      _trackingStatusColor
                                                          .withValues(
                                                            alpha: 0.18,
                                                          ),
                                                      _trackingStatusColor
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                    ],
                                                  ),
                                                  border: Border.all(
                                                    color: _trackingStatusColor
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    width: 1.2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color:
                                                          _trackingStatusColor
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  _trackingStatusLabel,
                                                  style: TextStyle(
                                                    color: _trackingStatusColor,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: MetricCard(
                                                  label: 'Distance',
                                                  value: displayedDistanceKm > 0
                                                      ? displayedDistanceKm
                                                            .toStringAsFixed(2)
                                                      : '--',
                                                  unit: 'km',
                                                  icon: Icons.route,
                                                  highlighted: true,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: MetricCard(
                                                  label: 'Pace',
                                                  value: pace > 0
                                                      ? pace.toStringAsFixed(2)
                                                      : '--',
                                                  unit: 'min/km',
                                                  icon: Icons.speed,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizeTransition(
                                            sizeFactor: ReverseAnimation(
                                              _panelController,
                                            ),
                                            axisAlignment: -1.0,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 10,
                                              ),
                                              child: Text(
                                                'Swipe up for detailed stats',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.black
                                                      .withValues(alpha: 0.5),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizeTransition(
                                            sizeFactor: _panelController,
                                            axisAlignment: -1.0,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: MetricCard(
                                                        label: 'Calories',
                                                        value: _caloriesKcal > 0
                                                            ? _caloriesKcal
                                                                  .toStringAsFixed(
                                                                    0,
                                                                  )
                                                            : '--',
                                                        unit: 'kcal',
                                                        icon: Icons
                                                            .local_fire_department,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: MetricCard(
                                                        label: 'Elevation',
                                                        value:
                                                            _elevationGainMeters >
                                                                0
                                                            ? _elevationGainMeters
                                                                  .toStringAsFixed(
                                                                    0,
                                                                  )
                                                            : '0',
                                                        unit: 'm',
                                                        icon: Icons.terrain,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: MetricCard(
                                                        label: 'Points',
                                                        value: '$_points',
                                                        icon: Icons
                                                            .location_on_outlined,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: MetricCard(
                                                        label: 'Avg Speed',
                                                        value: avgSpeedKmh > 0
                                                            ? avgSpeedKmh
                                                                  .toStringAsFixed(
                                                                    2,
                                                                  )
                                                            : '--',
                                                        unit: 'km/h',
                                                        icon: Icons.flash_on,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Wrap(
                                                  spacing: 10,
                                                  runSpacing: 8,
                                                  children: [
                                                    _buildStatusInfoChip(
                                                      icon: _hasLiveLocationFix
                                                          ? Icons.gps_fixed
                                                          : Icons.gps_not_fixed,
                                                      label: _hasLiveLocationFix
                                                          ? 'GPS locked'
                                                          : 'Searching GPS',
                                                      tone: _hasLiveLocationFix
                                                          ? const Color(
                                                              0xFF2E7D32,
                                                            )
                                                          : const Color(
                                                              0xFFE65100,
                                                            ),
                                                    ),
                                                    _buildStatusInfoChip(
                                                      icon: _ghostMode
                                                          ? Icons.visibility_off
                                                          : Icons.visibility,
                                                      label: _ghostMode
                                                          ? 'Ghost On'
                                                          : 'Ghost Off',
                                                      tone: _ghostMode
                                                          ? const Color(
                                                              0xFF7B1FA2,
                                                            )
                                                          : const Color(
                                                              0xFF607D8B,
                                                            ),
                                                    ),
                                                    _buildStatusInfoChip(
                                                      icon: Icons.map_outlined,
                                                      label:
                                                          activeMapTheme.label,
                                                      tone: const Color(
                                                        0xFF5C6BC0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  _canHoldToFinish
                                                      ? 'Press and hold Finish for 3 seconds to save workout'
                                                      : 'Start a workout to enable pause and finish',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black
                                                        .withValues(alpha: 0.5),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (kIsWeb) ...[
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Tracking is disabled on web. Use Android/iOS for live GPS.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ] else if (_locationStatus !=
                                              null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              _locationStatus!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 20,
                                offset: const Offset(0, -6),
                              ),
                            ],
                            border: Border(
                              top: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                10,
                              ),
                              child: _buildFloatingTrackingControls(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            child: Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: _mapZoom,
                  // Constrain zoom to the range standard raster tiles
                  // support. Without these, pinch-zooming past ~zoom 22 or
                  // below ~zoom 1 can push flutter_map's projection math
                  // into NaN territory mid-gesture and crash the map with
                  // "LatLng is not finite".
                  minZoom: 2,
                  maxZoom: 19,
                  // Keep the camera inside the WGS84 world so users can't
                  // pan into the projection's singular regions near the
                  // poles (web mercator diverges past ±85.0511°).
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      const LatLng(-85, -180),
                      const LatLng(85, 180),
                    ),
                  ),
                  onPositionChanged: (position, hasGesture) {
                    _mapCenter = position.center;
                    _mapZoom = position.zoom;
                    if (hasGesture) {
                      _followUserLocation = false;
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: activeMapTheme.urlTemplate,
                    subdomains: activeMapTheme.subdomains,
                    userAgentPackageName: 'com.company.fakestrava',
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),
                  if (_routePoints.length >= 2)
                    PolylineLayer(
                      polylines: _buildSpeedGradientPolylines(
                        _routePoints,
                        _activeElapsedSeconds(),
                      ),
                    ),
                  if (_currentPosition != null &&
                      isValidWgs84(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ))
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition!,
                          width: 34,
                          height: 34,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kBrandOrange,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(activeMapTheme.attribution),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
