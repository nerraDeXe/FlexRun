import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/tracking_point.dart';
import '../models/tracking_snapshot.dart';
import 'distance_calculator.dart';
import 'tracking_repository.dart';

const String _kDistanceMeters = 'distanceMeters';
const String _kElevationGainMeters = 'elevationGainMeters';
const String _kCaloriesKcal = 'caloriesKcal';
const String _kPoints = 'points';
const String _kSessionId = 'sessionId';
const String _kStartedAtIso = 'startedAtIso';
const String _kIsTracking = 'isTracking';
const String _kIsAutoPaused = 'isAutoPaused';
const String _kLatitude = 'latitude';
const String _kLongitude = 'longitude';
const String _kUpdateEvent = 'tracking_update';
const String _kStartEvent = 'start_tracking';
const String _kStopEvent = 'stop_tracking';
const double _kMaxHorizontalAccuracyMeters = 25;
const double _kMinMovementMeters = 3;
const double _kCaloriesPerKm = 62;
const Duration _kAutoPauseDelay = Duration(seconds: 20);
const double _kAutoPauseSpeedThresholdMps = 0.8;
const double _kAutoResumeSpeedThresholdMps = 1.2;
const Uuid _kUuid = Uuid();

class TrackingBackgroundService {
  factory TrackingBackgroundService() => _instance;

  TrackingBackgroundService._();

  static final TrackingBackgroundService _instance =
      TrackingBackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  final StreamController<TrackingSnapshot> _updatesController =
      StreamController<TrackingSnapshot>.broadcast();

  Stream<TrackingSnapshot> get updates => _updatesController.stream;

  Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: 7341,
        autoStartOnBoot: false,
        initialNotificationTitle: 'Fake Strava',
        initialNotificationContent: 'GPS tracking ready',
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onServiceStart,
        onBackground: _onIosBackground,
      ),
    );

    _service.on(_kUpdateEvent).listen((payload) {
      final snapshot = TrackingSnapshot(
        isTracking: payload?[_kIsTracking] == true,
        isAutoPaused: payload?[_kIsAutoPaused] == true,
        distanceMeters: (payload?[_kDistanceMeters] as num?)?.toDouble() ?? 0,
        elevationGainMeters:
            (payload?[_kElevationGainMeters] as num?)?.toDouble() ?? 0,
        caloriesKcal: (payload?[_kCaloriesKcal] as num?)?.toDouble() ?? 0,
        points: (payload?[_kPoints] as num?)?.toInt() ?? 0,
        sessionId: payload?[_kSessionId] as String?,
        startedAt: _parseIso(payload?[_kStartedAtIso] as String?),
        latitude: (payload?[_kLatitude] as num?)?.toDouble(),
        longitude: (payload?[_kLongitude] as num?)?.toDouble(),
      );
      _updatesController.add(snapshot);
    });
  }

  Future<void> startTracking() async {
    await _ensureLocationPermission();
    if (!await _service.isRunning()) {
      await _service.startService();
      await _waitForServiceToRun();
    }
    _service.invoke(_kStartEvent);
  }

  Future<void> stopTracking() async {
    _service.invoke(_kStopEvent);
  }

  Future<TrackingSnapshot> restoreLatestSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return TrackingSnapshot(
      isTracking: prefs.getBool(_kIsTracking) ?? false,
      isAutoPaused: prefs.getBool(_kIsAutoPaused) ?? false,
      distanceMeters: prefs.getDouble(_kDistanceMeters) ?? 0,
      elevationGainMeters: prefs.getDouble(_kElevationGainMeters) ?? 0,
      caloriesKcal: prefs.getDouble(_kCaloriesKcal) ?? 0,
      points: prefs.getInt(_kPoints) ?? 0,
      sessionId: prefs.getString(_kSessionId),
      startedAt: _parseIso(prefs.getString(_kStartedAtIso)),
      latitude: prefs.getDouble(_kLatitude),
      longitude: prefs.getDouble(_kLongitude),
    );
  }

  Future<void> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for tracking.');
    }
  }

  Future<void> _waitForServiceToRun() async {
    const maxAttempts = 20;
    for (var i = 0; i < maxAttempts; i++) {
      if (await _service.isRunning()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Background service failed to start.');
  }

  static DateTime? _parseIso(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  return true;
}

@pragma('vm:entry-point')
Future<void> _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  final repository = TrackingRepository();
  final prefs = await SharedPreferences.getInstance();
  StreamSubscription<Position>? positionSubscription;
  TrackingPoint? lastPoint;
  var distanceMeters = prefs.getDouble(_kDistanceMeters) ?? 0.0;
  var elevationGainMeters = prefs.getDouble(_kElevationGainMeters) ?? 0.0;
  var caloriesKcal = prefs.getDouble(_kCaloriesKcal) ?? 0.0;
  var points = prefs.getInt(_kPoints) ?? 0;
  var sessionId = prefs.getString(_kSessionId);
  var startedAt = DateTime.tryParse(prefs.getString(_kStartedAtIso) ?? '');
  var isTracking = prefs.getBool(_kIsTracking) ?? false;
  var isAutoPaused = prefs.getBool(_kIsAutoPaused) ?? false;
  DateTime? stationarySince;

  Future<void> broadcastSnapshot() async {
    final payload = <String, dynamic>{
      _kIsTracking: isTracking,
      _kIsAutoPaused: isAutoPaused,
      _kDistanceMeters: distanceMeters,
      _kElevationGainMeters: elevationGainMeters,
      _kCaloriesKcal: caloriesKcal,
      _kPoints: points,
      _kSessionId: sessionId,
      _kStartedAtIso: startedAt?.toIso8601String(),
      _kLatitude: lastPoint?.latitude,
      _kLongitude: lastPoint?.longitude,
    };
    service.invoke(_kUpdateEvent, payload);
    await prefs.setBool(_kIsTracking, isTracking);
    await prefs.setBool(_kIsAutoPaused, isAutoPaused);
    await prefs.setDouble(_kDistanceMeters, distanceMeters);
    await prefs.setDouble(_kElevationGainMeters, elevationGainMeters);
    await prefs.setDouble(_kCaloriesKcal, caloriesKcal);
    await prefs.setInt(_kPoints, points);
    if (sessionId != null) {
      await prefs.setString(_kSessionId, sessionId!);
    } else {
      await prefs.remove(_kSessionId);
    }
    if (startedAt != null) {
      await prefs.setString(_kStartedAtIso, startedAt!.toIso8601String());
    } else {
      await prefs.remove(_kStartedAtIso);
    }
    if (lastPoint != null) {
      await prefs.setDouble(_kLatitude, lastPoint!.latitude);
      await prefs.setDouble(_kLongitude, lastPoint!.longitude);
    } else {
      await prefs.remove(_kLatitude);
      await prefs.remove(_kLongitude);
    }
  }

  Future<void> start() async {
    if (isTracking) {
      return;
    }
    sessionId = _kUuid.v4();
    startedAt = DateTime.now().toUtc();
    distanceMeters = 0;
    elevationGainMeters = 0;
    caloriesKcal = 0;
    points = 0;
    lastPoint = null;
    isTracking = true;
    isAutoPaused = false;
    stationarySince = null;

    await repository.createSession(
      sessionId: sessionId!,
      startedAt: startedAt!,
    );
    await broadcastSnapshot();

    positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen((Position position) async {
          if (!isTracking || sessionId == null || startedAt == null) {
            return;
          }
          if (position.accuracy > _kMaxHorizontalAccuracyMeters) {
            return;
          }

          final point = TrackingPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            timestamp: position.timestamp.toUtc(),
            speedMps: position.speed >= 0 ? position.speed : null,
            altitudeMeters: position.altitude,
          );

          final previousAutoPaused = isAutoPaused;
          final nowUtc = DateTime.now().toUtc();
          var segmentMeters = 0.0;
          if (lastPoint != null) {
            segmentMeters = DistanceCalculator.haversineMeters(
              lastPoint!,
              point,
            );
            final speed = position.speed >= 0 ? position.speed : 0.0;
            final hasMeaningfulMovement =
                speed >= _kAutoResumeSpeedThresholdMps ||
                segmentMeters >= _kMinMovementMeters;

            if (hasMeaningfulMovement) {
              stationarySince = null;
              isAutoPaused = false;
            } else {
              stationarySince ??= nowUtc;
              final stationaryFor = nowUtc.difference(stationarySince!);
              if (stationaryFor >= _kAutoPauseDelay &&
                  speed <= _kAutoPauseSpeedThresholdMps) {
                isAutoPaused = true;
              }
            }

            final previousAltitude = lastPoint!.altitudeMeters;
            final currentAltitude = point.altitudeMeters;
            if (previousAltitude != null && currentAltitude != null) {
              final climb = currentAltitude - previousAltitude;
              if (climb > 0.5) {
                elevationGainMeters += climb;
              }
            }

            if (segmentMeters < _kMinMovementMeters) {
              if (previousAutoPaused != isAutoPaused) {
                await broadcastSnapshot();
              }
              return;
            }

            if (!isAutoPaused) {
              distanceMeters += segmentMeters;
              caloriesKcal = (distanceMeters / 1000) * _kCaloriesPerKm;
            }
          }

          lastPoint = point;
          points += 1;

          await repository.appendPoint(
            sessionId: sessionId!,
            point: point,
            totalDistanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            caloriesKcal: caloriesKcal,
            isAutoPaused: isAutoPaused,
            points: points,
          );
          await broadcastSnapshot();
        });

    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();
      await service.setForegroundNotificationInfo(
        title: 'Fake Strava',
        content: 'Tracking in background',
      );
    }
  }

  Future<void> stop() async {
    if (!isTracking) {
      return;
    }
    isTracking = false;
    await positionSubscription?.cancel();
    positionSubscription = null;

    if (sessionId != null) {
      await repository.closeSession(
        sessionId: sessionId!,
        endedAt: DateTime.now().toUtc(),
        distanceMeters: distanceMeters,
        elevationGainMeters: elevationGainMeters,
        caloriesKcal: caloriesKcal,
        points: points,
      );
    }

    sessionId = null;
    startedAt = null;
    lastPoint = null;
    isAutoPaused = false;
    stationarySince = null;
    await broadcastSnapshot();
  }

  service.on(_kStartEvent).listen((_) async => start());
  service.on(_kStopEvent).listen((_) async => stop());
  await broadcastSnapshot();
}
