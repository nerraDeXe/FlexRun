import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  bool _isTracking = false;
  double _distanceKm = 0;
  int _points = 0;
  DateTime? _startedAt;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _hydrateState();
    _service.updates.listen((TrackingSnapshot snapshot) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isTracking = snapshot.isTracking;
        _distanceKm = snapshot.distanceMeters / 1000;
        _points = snapshot.points;
        _startedAt = snapshot.startedAt;
        _sessionId = snapshot.sessionId;
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
    });
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
                    onPressed: kIsWeb || _isTracking
                        ? null
                        : () async {
                            await _service.startTracking();
                          },
                    child: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: !kIsWeb && _isTracking
                        ? () async {
                            await _service.stopTracking();
                          }
                        : null,
                    child: const Text('Stop'),
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
