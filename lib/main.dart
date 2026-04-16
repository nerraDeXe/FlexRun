import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'tracking/models/tracking_snapshot.dart';
import 'tracking/services/tracking_background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await Firebase.initializeApp();
    await TrackingBackgroundService().initialize();
  }
  runApp(const FakeStravaApp());
}

class FakeStravaApp extends StatelessWidget {
  const FakeStravaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake Strava',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const TrackingHomePage(),
    );
  }
}

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key});

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage> {
  static const LatLng _defaultCenter = LatLng(3.1390, 101.6869);
  final TrackingBackgroundService _service = TrackingBackgroundService();
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<TrackingSnapshot>? _snapshotSubscription;
  StreamSubscription<Position>? _foregroundPositionSubscription;
  Timer? _voiceTimer;

  bool _isTracking = false;
  bool _isAutoPaused = false;
  bool _isStarting = false;
  bool _isStopping = false;
  bool _voicePaceEnabled = true;
  bool _hasLiveLocationFix = false;
  bool _hasCenteredOnLiveLocation = false;
  bool _followUserLocation = true;
  String? _locationStatus;
  double _distanceKm = 0;
  double _elevationGainMeters = 0;
  double _caloriesKcal = 0;
  int _points = 0;
  DateTime? _startedAt;
  String? _activeRouteSessionId;
  FirebaseFirestore? _firestore;
  LatLng? _currentPosition;
  LatLng _mapCenter = _defaultCenter;
  double _mapZoom = 15.5;

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      _firestore = FirebaseFirestore.instance;
    }
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
        _distanceKm = snapshot.distanceMeters / 1000;
        _elevationGainMeters = snapshot.elevationGainMeters;
        _caloriesKcal = snapshot.caloriesKcal;
        _points = snapshot.points;
        _startedAt = snapshot.startedAt;
        if (snapshot.isTracking) {
          _capturePoint(snapshot);
        } else if (!_hasLiveLocationFix) {
          _currentPosition = null;
          _mapCenter = _defaultCenter;
          _routePoints.clear();
        }
      });
      if (!wasTracking && _isTracking) {
        _startVoiceAnnouncements();
      } else if (wasTracking && !_isTracking) {
        _stopVoiceAnnouncements();
      }
    });
  }

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _foregroundPositionSubscription?.cancel();
    _stopVoiceAnnouncements();
    _tts.stop();
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
    if (!_voicePaceEnabled ||
        !_isTracking ||
        _isAutoPaused ||
        _distanceKm <= 0) {
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
      _distanceKm = snapshot.distanceMeters / 1000;
      _elevationGainMeters = snapshot.elevationGainMeters;
      _caloriesKcal = snapshot.caloriesKcal;
      _points = snapshot.points;
      _startedAt = snapshot.startedAt;
      _activeRouteSessionId = snapshot.sessionId;
      if (snapshot.isTracking) {
        _capturePoint(snapshot);
      } else {
        _currentPosition = null;
        _mapCenter = _defaultCenter;
        _routePoints.clear();
      }
    });
    if (_isTracking) {
      _startVoiceAnnouncements();
    }
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

  Future<void> _openHistory() async {
    final firestore = _firestore;
    if (firestore == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase is not ready yet.')),
        );
      }
      return;
    }
    if (_isTracking) {
      await _service.stopTracking();
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutHistoryPage(
          firestore: firestore,
          onShareMessage: (message) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        ),
      ),
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

  double _paceMinPerKm() {
    if (_startedAt == null || _distanceKm <= 0) {
      return 0;
    }
    final elapsedMinutes =
        DateTime.now().difference(_startedAt!).inSeconds / 60;
    return elapsedMinutes / _distanceKm;
  }

  String _elapsedLabel() {
    if (_startedAt == null) {
      return '--:--:--';
    }
    final Duration elapsed = DateTime.now().difference(_startedAt!);
    final int h = elapsed.inHours;
    final int m = elapsed.inMinutes.remainder(60);
    final int s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onTap,
    required BorderRadius borderRadius,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.orange.shade700),
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
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
    final pace = _paceMinPerKm();
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
                  final center = position.center;
                  final zoom = position.zoom;
                  if (center != null) {
                    _mapCenter = center;
                  }
                  if (zoom != null) {
                    _mapZoom = zoom;
                  }
                  if (hasGesture) {
                    _followUserLocation = false;
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.company.fakestrava',
                ),
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: Colors.deepOrange,
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
                            color: Colors.blue,
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
              ],
            ),
          ),
          Positioned(
            right: 14,
            top: 84,
            child: Column(
              children: [
                _buildZoomButton(
                  icon: Icons.my_location,
                  onTap: _recenterToUser,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(height: 8),
                _buildZoomButton(
                  icon: Icons.add,
                  onTap: () => _zoomMap(1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                const SizedBox(height: 2),
                _buildZoomButton(
                  icon: Icons.remove,
                  onTap: () => _zoomMap(-1),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isTracking
                                  ? Icons.directions_run
                                  : Icons.pause_circle,
                              size: 18,
                              color: _isTracking
                                  ? Colors.green.shade700
                                  : Colors.black54,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isTracking
                                  ? (_isAutoPaused
                                        ? 'Auto-paused'
                                        : 'Tracking Active')
                                  : 'Ready to Start',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () {
                          setState(
                            () => _voicePaceEnabled = !_voicePaceEnabled,
                          );
                        },
                        icon: Icon(
                          _voicePaceEnabled
                              ? Icons.volume_up
                              : Icons.volume_off,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Distance',
                                value: '${_distanceKm.toStringAsFixed(3)} km',
                                icon: Icons.route,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Pace',
                                value: pace == 0
                                    ? '-- min/km'
                                    : '${pace.toStringAsFixed(2)} min/km',
                                icon: Icons.speed,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Calories',
                                value:
                                    '${_caloriesKcal.toStringAsFixed(0)} kcal',
                                icon: Icons.local_fire_department,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Elevation',
                                value:
                                    '${_elevationGainMeters.toStringAsFixed(0)} m',
                                icon: Icons.terrain,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Elapsed',
                                value: _elapsedLabel(),
                                icon: Icons.timer_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Points',
                                value: '$_points',
                                icon: Icons.location_on_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: kIsWeb || _isTracking || _isStarting
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() {
                                          _isStarting = true;
                                          _followUserLocation = true;
                                        });
                                        try {
                                          await _service.startTracking();
                                          await _startForegroundPointerStream();
                                        } catch (error) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isStarting = false);
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  _isStarting ? 'Starting...' : 'Start',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    !kIsWeb && _isTracking && !_isStopping
                                    ? () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() => _isStopping = true);
                                        try {
                                          await _service.stopTracking();
                                        } catch (error) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isStopping = false);
                                          }
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.stop_rounded),
                                label: Text(
                                  _isStopping ? 'Stopping...' : 'Stop',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            ),
                          ],
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

  String _formatDuration(DateTime? startedAt, DateTime? endedAt) {
    if (startedAt == null || endedAt == null) {
      return '--:--:--';
    }
    final elapsed = endedAt.difference(startedAt);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('tracking_sessions')
            .orderBy('startedAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!.docs;
          if (sessions.isEmpty) {
            return const Center(child: Text('No workouts yet.'));
          }
          return ListView.separated(
            itemCount: sessions.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = sessions[index].data();
              final sessionId = sessions[index].id;
              final startedAt = DateTime.tryParse(
                data['startedAt'] as String? ?? '',
              );
              final endedAt = DateTime.tryParse(
                data['endedAt'] as String? ?? '',
              );
              final distanceMeters =
                  (data['distanceMeters'] as num?)?.toDouble() ?? 0;
              final calories = (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
              final elevation =
                  (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
              final distanceKm = distanceMeters / 1000;
              final durationSeconds = (startedAt != null && endedAt != null)
                  ? endedAt.difference(startedAt).inSeconds
                  : 0;
              final pace = durationSeconds > 0 && distanceKm > 0
                  ? (durationSeconds / 60) / distanceKm
                  : 0.0;
              return ListTile(
                title: Text(
                  '${distanceKm.toStringAsFixed(2)} km • ${pace > 0 ? '${pace.toStringAsFixed(2)} min/km' : '-- min/km'}',
                ),
                subtitle: Text(
                  '${_formatDuration(startedAt, endedAt)} • ${calories.toStringAsFixed(0)} kcal • +${elevation.toStringAsFixed(0)} m',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () => _exportSessionGpx(sessionId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
