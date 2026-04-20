import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:fake_strava/tracking/models/tracking_snapshot.dart';
import 'package:fake_strava/tracking/services/tracking_background_service.dart';
import 'package:fake_strava/tracking/services/bluetooth_hr_service.dart';
import 'package:fake_strava/core/theme.dart';

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
  final BluetoothHRService _hrService = BluetoothHRService();
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<TrackingSnapshot>? _snapshotSubscription;
  StreamSubscription<Position>? _foregroundPositionSubscription;
  StreamSubscription<int>? _hrSubscription;
  Timer? _voiceTimer;
  Timer? _liveMetricsTimer;
  Timer? _finishHoldTimer;

  bool _isTracking = false;
  bool _isAutoPaused = false;
  bool _isManuallyPaused = false;
  bool _isStarting = false;
  bool _isPausing = false;
  bool _isResuming = false;
  bool _isFinishing = false;
  late final AnimationController _panelController;
  bool _isMapFullscreen = false;
  double _finishHoldProgress = 0;
  double _panelDragAccumulator = 0;
  double _statsScale = 1.0;
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
  int _mapThemeIndex = 0;
  int _currentHeartRate = 0;
  final List<int> _heartRateReadings = <int>[];

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _panelController.addListener(() => setState(() {}));
    _hydrateState();
    _startForegroundPointerStream();
    _setupVoicePace();
    _setupHRMonitoring();
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
          _currentHeartRate = 0;
          _heartRateReadings.clear();
          if (!_hasLiveLocationFix) {
            _currentPosition = null;
            _mapCenter = _defaultCenter;
          }
        }
      });
      if (!wasTracking && _isTracking) {
        _startVoiceAnnouncements();
      } else if (wasTracking && !_isTracking) {
        _cancelFinishHold();
        _stopVoiceAnnouncements();
      }
      _syncLiveMetricsTimer();
    });
  }

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _foregroundPositionSubscription?.cancel();
    _hrSubscription?.cancel();
    _finishHoldTimer?.cancel();
    _stopVoiceAnnouncements();
    _stopLiveMetricsTimer();
    _tts.stop();
    _hrService.dispose();
    _panelController.dispose();
    super.dispose();
  }

  Future<void> _setupVoicePace() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
  }

  void _setupHRMonitoring() {
    _hrSubscription?.cancel();
    _hrSubscription = _hrService.hrValueStream.listen((heartRate) {
      if (mounted && _isTracking) {
        setState(() {
          _currentHeartRate = heartRate;
          _heartRateReadings.add(heartRate);
        });
      }
    });
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
    final latitude = snapshot.latitude;
    final longitude = snapshot.longitude;
    if (latitude == null || longitude == null) {
      return;
    }
    final point = LatLng(latitude, longitude);
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
      _mapController.move(_mapCenter, _mapZoom);
    }
    _updatePreviewDistance(point, position.accuracy);
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
    _mapController.move(_mapCenter, nextZoom);
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
    _mapController.move(_mapCenter, _mapZoom);
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isFinishing = true;
      _finishHoldProgress = 1;
    });
    try {
      await _service.stopTracking();
      if (!mounted) {
        return;
      }
      setState(() {
        _resetTrackingPanelState();
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Workout saved. Great effort!')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
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
        color: active
            ? kBrandOrange.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _buildPrimaryMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scale = _statsScale;
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 34 * scale,
            height: 34 * scale,
            decoration: BoxDecoration(
              color: kBrandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kBrandOrange, size: 18 * scale),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    value,
                    key: ValueKey<String>('primary_${label}_$value'),
                    style: TextStyle(
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w800,
                      color: kBrandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scale = _statsScale;
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16 * scale, color: kBrandOrange),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    value,
                    key: ValueKey<String>('secondary_${label}_$value'),
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                      color: kBrandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStart() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isStarting = true;
      _followUserLocation = true;
    });
    try {
      HapticFeedback.lightImpact();
      await _service.startTracking();
      await _startForegroundPointerStream();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _handlePauseResume() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      if (_isManuallyPaused) {
        _isResuming = true;
      } else {
        _isPausing = true;
      }
    });
    try {
      HapticFeedback.lightImpact();
      if (_isManuallyPaused) {
        await _service.resumeTracking();
      } else {
        await _service.pauseTracking();
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
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
    if (_isMapFullscreen) return;
    if (_panelController.value > 0.5) {
      _panelController.reverse();
    } else {
      _panelController.forward();
    }
  }

  void _onPanelDragStart(DragStartDetails details) {
    if (_isMapFullscreen) return;
    _panelController.stop();
  }

  void _onPanelDragUpdate(DragUpdateDetails details) {
    if (_isMapFullscreen) return;
    final delta = details.primaryDelta;
    if (delta == null) return;
    // Delta > 0 means dragging down (shrinking)
    _panelController.value -= delta / 180.0;
  }

  void _onPanelDragEnd(DragEndDetails details) {
    if (_isMapFullscreen) return;
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

  void _toggleMapFullscreen() {
    setState(() {
      _isMapFullscreen = !_isMapFullscreen;
    });
  }

  void _cycleStatsScale() {
    setState(() {
      if (_statsScale < 1.0) {
        _statsScale = 1.0;
      } else if (_statsScale < 1.1) {
        _statsScale = 1.2;
      } else {
        _statsScale = 0.9;
      }
    });
  }

  Future<void> _showHRDeviceSelector() async {
    final permitted = await _hrService.requestPermissions();
    if (!permitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permissions required')),
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildHRDevicePicker(),
    );
  }

  Widget _buildHRDevicePicker() {
    return StatefulBuilder(
      builder: (context, setState) {
        return StreamBuilder<List<ScanResult>>(
          stream: _hrService.scanForDevices().asBroadcastStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No Bluetooth devices found',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_hrService.isConnected)
                      ElevatedButton(
                        onPressed: () async {
                          await _hrService.disconnect();
                          if (mounted) {
                            setState(() {});
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final isConnected =
                    _hrService.connectedDevice?.remoteId ==
                    device.device.remoteId;

                return ListTile(
                  title: Text(
                    device.device.platformName.isEmpty
                        ? 'Unknown Device'
                        : device.device.platformName,
                  ),
                  subtitle: Text(device.device.remoteId.str),
                  trailing: isConnected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: isConnected
                      ? null
                      : () async {
                          final success = await _hrService.connectToDevice(
                            device.device,
                          );
                          if (mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Connected to HR monitor'),
                                ),
                              );
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to connect to device'),
                                ),
                              );
                            }
                          }
                        },
                );
              },
            );
          },
        );
      },
    );
  }

  String get _statsScaleLabel {
    if (_statsScale < 1.0) {
      return 'S';
    }
    if (_statsScale > 1.1) {
      return 'L';
    }
    return 'M';
  }

  @override
  Widget build(BuildContext context) {
    final pace = _paceMinPerKm();
    final displayedDistanceKm = _displayDistanceKm();
    final activeMapTheme = kMapThemeOptions[_mapThemeIndex];
    final avgSpeedKmh = pace > 0 ? 60 / pace : 0.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final mapControlsBottom = _isMapFullscreen
        ? 20.0 + bottomInset
        : (340.0 + (30.0 * _panelController.value)) + bottomInset;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
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
                ),
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: kBrandOrange,
                      ),
                    ],
                  ),
                if (_currentPosition != null)
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
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.28),
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.36),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _trackingStatusColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _trackingStatusLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildIconGlassButton(
                            icon: _voicePaceEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            onTap: () {
                              setState(() => _voicePaceEnabled = !_voicePaceEnabled);
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
                            icon: Icons.text_fields_rounded,
                            onTap: _cycleStatsScale,
                            tooltip: 'Stats size: $_statsScaleLabel',
                            active: _statsScale > 1.0,
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: Icons.favorite,
                            onTap: _showHRDeviceSelector,
                            tooltip: _hrService.isConnected
                                ? 'HR Monitor Connected'
                                : 'Connect HR Monitor',
                            active: _hrService.isConnected,
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: _isMapFullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            onTap: _toggleMapFullscreen,
                            tooltip: _isMapFullscreen
                                ? 'Exit full screen map'
                                : 'Full screen map',
                            active: _isMapFullscreen,
                          ),
                        ],
                      ),
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
          if (!_isMapFullscreen)
            Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onPanelDragStart,
                onVerticalDragUpdate: _onPanelDragUpdate,
                onVerticalDragEnd: _onPanelDragEnd,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottomInset),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2F000000),
                        blurRadius: 24,
                        offset: Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      GestureDetector(
                        onTap: _togglePanelCollapse,
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(
                                _isPanelCollapsed
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: Colors.black45,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _elapsedLabel(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: kBrandBlack,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _trackingStatusColor.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _trackingStatusLabel,
                              style: TextStyle(
                                color: _trackingStatusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildPrimaryMetric(
                              label: 'Distance',
                              value:
                                  '${displayedDistanceKm.toStringAsFixed(3)} km',
                              icon: Icons.route,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildPrimaryMetric(
                              label: 'Pace',
                              value: pace > 0
                                  ? '${pace.toStringAsFixed(2)} min/km'
                                  : '-- min/km',
                              icon: Icons.speed,
                            ),
                          ),
                        ],
                      ),
                      SizeTransition(
                        sizeFactor: ReverseAnimation(_panelController),
                        axisAlignment: -1.0,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Summary mode. Swipe up for full details.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
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
                            const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Calories',
                                value:
                                    '${_caloriesKcal.toStringAsFixed(0)} kcal',
                                icon: Icons.local_fire_department,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Elevation',
                                value:
                                    '${_elevationGainMeters.toStringAsFixed(0)} m',
                                icon: Icons.terrain,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Points',
                                value: '$_points',
                                icon: Icons.location_on_outlined,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Avg Speed',
                                value: avgSpeedKmh > 0
                                    ? '${avgSpeedKmh.toStringAsFixed(2)} km/h'
                                    : '-- km/h',
                                icon: Icons.flash_on,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Current HR',
                                value: _currentHeartRate > 0
                                    ? '$_currentHeartRate bpm'
                                    : '-- bpm',
                                icon: Icons.favorite,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Avg HR',
                                value: _heartRateReadings.isNotEmpty
                                    ? '${((_heartRateReadings.fold<int>(0, (a, b) => a + b) / _heartRateReadings.length)).round()} bpm'
                                    : '-- bpm',
                                icon: Icons.favorite_outline,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: Icon(
                                _hasLiveLocationFix
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                                color: _hasLiveLocationFix
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE65100),
                                size: 16,
                              ),
                              label: Text(
                                _hasLiveLocationFix
                                    ? 'GPS locked'
                                    : 'Searching GPS',
                              ),
                            ),
                            Chip(
                              avatar: const Icon(Icons.map_outlined, size: 16),
                              label: Text(activeMapTheme.label),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _canHoldToFinish
                              ? 'Press and hold Finish for 3 seconds to save workout'
                              : 'Start a workout to enable pause and finish',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: kIsWeb || _isTracking || _isStarting
                                  ? null
                                  : _handleStart,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _isStarting ? 'Starting...' : 'Start',
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  !kIsWeb &&
                                      _isTracking &&
                                      !_isPausing &&
                                      !_isResuming
                                  ? _handlePauseResume
                                  : null,
                              icon: Icon(
                                _isManuallyPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              label: Text(
                                _isManuallyPaused
                                    ? (_isResuming ? 'Resuming...' : 'Resume')
                                    : (_isPausing ? 'Pausing...' : 'Pause'),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: kBrandBlack,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: _canHoldToFinish
                                  ? (_) => _startFinishHold()
                                  : null,
                              onTapUp: (_) => _cancelFinishHold(),
                              onTapCancel: _cancelFinishHold,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF20242E),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: _finishHoldProgress,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: kBrandOrange.withValues(
                                              alpha: 0.9,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
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
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isFinishing
                                            ? 'Saving...'
                                            : _finishHoldProgress > 0
                                            ? 'Hold ${(3 - (_finishHoldProgress * 3)).ceil().clamp(1, 3)}s'
                                            : 'Finish',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (kIsWeb) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Tracking is disabled on web. Use Android/iOS for live GPS.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ] else if (_locationStatus != null) ...[
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
              ),
            ),
        ],
      ),
    );
  }
}

