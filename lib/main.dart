import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  final TrackingBackgroundService _service = TrackingBackgroundService();
  final MapController _mapController = MapController();
  static const LatLng _defaultCenter = LatLng(37.7749, -122.4194);
  bool _isTracking = false;
  bool _isStarting = false;
  bool _isStopping = false;
  double _distanceKm = 0;
  int _points = 0;
  DateTime? _startedAt;
  String? _activeRouteSessionId;
  LatLng? _currentPosition;
  LatLng _mapCenter = _defaultCenter;
  double _mapZoom = 15.5;
  final List<LatLng> _routePoints = <LatLng>[];

  @override
  void initState() {
    super.initState();
    _hydrateState();
    _service.updates.listen((TrackingSnapshot snapshot) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (snapshot.sessionId != null &&
            snapshot.sessionId != _activeRouteSessionId &&
            snapshot.isTracking) {
          _activeRouteSessionId = snapshot.sessionId;
          _routePoints.clear();
        }
        _isTracking = snapshot.isTracking;
        _distanceKm = snapshot.distanceMeters / 1000;
        _points = snapshot.points;
        _startedAt = snapshot.startedAt;
        _capturePoint(snapshot);
      });
    });
  }

  Future<void> _hydrateState() async {
    final snapshot = await _service.restoreLatestSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _isTracking = snapshot.isTracking;
      _distanceKm = snapshot.distanceMeters / 1000;
      _points = snapshot.points;
      _startedAt = snapshot.startedAt;
      _activeRouteSessionId = snapshot.sessionId;
      _capturePoint(snapshot);
    });
  }

  void _capturePoint(TrackingSnapshot snapshot) {
    final latitude = snapshot.latitude;
    final longitude = snapshot.longitude;
    if (latitude == null || longitude == null) {
      return;
    }
    final point = LatLng(latitude, longitude);
    _currentPosition = point;
    if (_routePoints.length <= 1) {
      _mapCenter = point;
    }
    if (_routePoints.isEmpty ||
        _routePoints.last.latitude != point.latitude ||
        _routePoints.last.longitude != point.longitude) {
      _routePoints.add(point);
    }
  }

  void _zoomMap(double delta) {
    final nextZoom = (_mapZoom + delta).clamp(3.0, 18.0).toDouble();
    _mapController.move(_mapCenter, nextZoom);
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

  double _paceMinPerKm() {
    if (_startedAt == null || _distanceKm <= 0) {
      return 0;
    }
    final elapsedMinutes =
        DateTime.now().difference(_startedAt!).inSeconds / 60;
    return elapsedMinutes / _distanceKm;
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
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.30),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 84,
            child: Column(
              children: [
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
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
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
                            _isTracking ? 'Tracking Active' : 'Ready to Start',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                                        setState(() => _isStarting = true);
                                        try {
                                          await _service.startTracking();
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
