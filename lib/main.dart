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
  static const LatLng _defaultCenter = LatLng(37.7749, -122.4194);
  bool _isTracking = false;
  bool _isStarting = false;
  bool _isStopping = false;
  double _distanceKm = 0;
  int _points = 0;
  DateTime? _startedAt;
  String? _sessionId;
  String? _activeRouteSessionId;
  LatLng? _currentPosition;
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
        _sessionId = snapshot.sessionId;
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
      _sessionId = snapshot.sessionId;
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
    if (_routePoints.isEmpty ||
        _routePoints.last.latitude != point.latitude ||
        _routePoints.last.longitude != point.longitude) {
      _routePoints.add(point);
    }
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

  @override
  Widget build(BuildContext context) {
    final pace = _paceMinPerKm();
    return Scaffold(
      appBar: AppBar(title: const Text('Fake Strava Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  key: ValueKey(
                    '${_currentPosition?.latitude}_${_currentPosition?.longitude}_${_routePoints.length}',
                  ),
                  options: MapOptions(
                    initialCenter:
                        _currentPosition ??
                        (_routePoints.isNotEmpty
                            ? _routePoints.last
                            : _defaultCenter),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.company.fakestrava',
                    ),
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 5,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    if (_currentPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPosition!,
                            width: 26,
                            height: 26,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isTracking ? 'Tracking Active' : 'Tracking Stopped',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Session: ${_sessionId ?? '-'}'),
            Text('Elapsed: ${_elapsedLabel()}'),
            Text('Distance: ${_distanceKm.toStringAsFixed(3)} km'),
            Text('Points saved: $_points'),
            Text('Pace: ${pace == 0 ? '--' : pace.toStringAsFixed(2)} min/km'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: kIsWeb || _isTracking || _isStarting
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _isStarting = true);
                            try {
                              await _service.startTracking();
                            } catch (error) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _isStarting = false);
                              }
                            }
                          },
                    child: Text(_isStarting ? 'Starting...' : 'Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: !kIsWeb && _isTracking && !_isStopping
                        ? () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _isStopping = true);
                            try {
                              await _service.stopTracking();
                            } catch (error) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _isStopping = false);
                              }
                            }
                          }
                        : null,
                    child: Text(_isStopping ? 'Stopping...' : 'Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              kIsWeb
                  ? 'Tracking controls are disabled on web. Run on Android/iOS for GPS background tracking.'
                  : 'Background tracking keeps running with screen locked while the service is active.',
            ),
          ],
        ),
      ),
    );
  }
}
