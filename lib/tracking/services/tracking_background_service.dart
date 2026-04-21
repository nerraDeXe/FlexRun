import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/tracking_point.dart';
import '../models/tracking_snapshot.dart';
import 'distance_calculator.dart';
import 'tracking_repository.dart';
import 'calorie_calculation_util.dart';
import 'package:fake_strava/profile/user_metrics.dart';
import 'package:fake_strava/profile/user_metrics_repository.dart';

const String _kDistanceMeters = 'distanceMeters';
const String _kElevationGainMeters = 'elevationGainMeters';
const String _kCaloriesKcal = 'caloriesKcal';
const String _kPoints = 'points';
const String _kSessionId = 'sessionId';
const String _kStartedAtIso = 'startedAtIso';
const String _kIsTracking = 'isTracking';
const String _kIsAutoPaused = 'isAutoPaused';
const String _kIsManuallyPaused = 'isManuallyPaused';
const String _kElapsedSeconds = 'elapsedSeconds';
const String _kAccumulatedActiveSeconds = 'accumulatedActiveSeconds';
const String _kLastResumedAtIso = 'lastResumedAtIso';
const String _kLatitude = 'latitude';
const String _kLongitude = 'longitude';
const String _kUpdateEvent = 'tracking_update';
const String _kStartEvent = 'start_tracking';
const String _kStopEvent = 'stop_tracking';
const String _kPauseEvent = 'pause_tracking';
const String _kResumeEvent = 'resume_tracking';
const String _kErrorEvent = 'tracking_error';
const double _kMaxHorizontalAccuracyMeters = 25;
const double _kMinMovementMeters = 3;
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
  final StreamController<String> _errorsController =
      StreamController<String>.broadcast();

  Stream<TrackingSnapshot> get updates => _updatesController.stream;
  Stream<String> get errors => _errorsController.stream;

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
        isManuallyPaused: payload?[_kIsManuallyPaused] == true,
        distanceMeters: (payload?[_kDistanceMeters] as num?)?.toDouble() ?? 0,
        elevationGainMeters:
            (payload?[_kElevationGainMeters] as num?)?.toDouble() ?? 0,
        caloriesKcal: (payload?[_kCaloriesKcal] as num?)?.toDouble() ?? 0,
        points: (payload?[_kPoints] as num?)?.toInt() ?? 0,
        elapsedSeconds: (payload?[_kElapsedSeconds] as num?)?.toInt() ?? 0,
        sessionId: payload?[_kSessionId] as String?,
        startedAt: _parseIso(payload?[_kStartedAtIso] as String?),
        latitude: (payload?[_kLatitude] as num?)?.toDouble(),
        longitude: (payload?[_kLongitude] as num?)?.toDouble(),
      );
      _updatesController.add(snapshot);
    });

    _service.on(_kErrorEvent).listen((payload) {
      final message = payload?['message'] as String?;
      if (message != null && message.isNotEmpty) {
        _errorsController.add(message);
      }
    });
  }

  Future<void> startTracking() async {
    await _ensureLocationPermission();
    if (!await _service.isRunning()) {
      await _service.startService();
      await _waitForServiceToRun();
    }
    await _invokeStartAndWaitForResult();
  }

  Future<void> stopTracking() async {
    _service.invoke(_kStopEvent);
  }

  Future<void> pauseTracking() async {
    _service.invoke(_kPauseEvent);
  }

  Future<void> resumeTracking() async {
    _service.invoke(_kResumeEvent);
  }

  Future<TrackingSnapshot> restoreLatestSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return TrackingSnapshot(
      isTracking: prefs.getBool(_kIsTracking) ?? false,
      isAutoPaused: prefs.getBool(_kIsAutoPaused) ?? false,
      isManuallyPaused: prefs.getBool(_kIsManuallyPaused) ?? false,
      distanceMeters: prefs.getDouble(_kDistanceMeters) ?? 0,
      elevationGainMeters: prefs.getDouble(_kElevationGainMeters) ?? 0,
      caloriesKcal: prefs.getDouble(_kCaloriesKcal) ?? 0,
      points: prefs.getInt(_kPoints) ?? 0,
      elapsedSeconds: prefs.getInt(_kElapsedSeconds) ?? 0,
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

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        permission == LocationPermission.whileInUse) {
      throw StateError(
        'Background tracking requires Location permission set to "Allow all the time" in Android app settings.',
      );
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

  Future<void> _invokeStartAndWaitForResult() async {
    final completer = Completer<void>();
    late final StreamSubscription<TrackingSnapshot> updatesSubscription;
    late final StreamSubscription<String> errorsSubscription;
    Timer? timeout;
    Timer? retryTimer;

    void completeError(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    updatesSubscription = updates.listen((snapshot) {
      if (snapshot.isTracking && !completer.isCompleted) {
        completer.complete();
      }
    });

    errorsSubscription = errors.listen((message) {
      completeError(StateError(message));
    });

    timeout = Timer(const Duration(seconds: 8), () {
      completeError(
        StateError(
          'Tracking failed to start. Check Android permission (Allow all the time) and device logs for a service error.',
        ),
      );
    });

    retryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!completer.isCompleted) {
        _service.invoke(_kStartEvent);
      }
    });

    try {
      _service.invoke(_kStartEvent);
      await completer.future;
    } finally {
      timeout.cancel();
      retryTimer.cancel();
      await updatesSubscription.cancel();
      await errorsSubscription.cancel();
    }
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
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  return true;
}

@pragma('vm:entry-point')
Future<void> _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error) {
    service.invoke(_kErrorEvent, {
      'message': 'Background Firebase initialization failed: $error',
    });
    return;
  }

  final repository = TrackingRepository();
  final metricsRepository = UserMetricsRepository();
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
  var isManuallyPaused = prefs.getBool(_kIsManuallyPaused) ?? false;
  var accumulatedActiveSeconds = prefs.getInt(_kAccumulatedActiveSeconds) ?? 0;
  var lastResumedAt = DateTime.tryParse(
    prefs.getString(_kLastResumedAtIso) ?? '',
  );
  DateTime? stationarySince;
  UserMetrics? userMetrics;

  int currentElapsedSeconds() {
    if (!isTracking) {
      return accumulatedActiveSeconds;
    }
    if (lastResumedAt == null) {
      return accumulatedActiveSeconds;
    }
    final extra = DateTime.now().toUtc().difference(lastResumedAt!).inSeconds;
    return accumulatedActiveSeconds + (extra > 0 ? extra : 0);
  }

  Future<void> broadcastSnapshot() async {
    final payload = <String, dynamic>{
      _kIsTracking: isTracking,
      _kIsAutoPaused: isAutoPaused,
      _kIsManuallyPaused: isManuallyPaused,
      _kDistanceMeters: distanceMeters,
      _kElevationGainMeters: elevationGainMeters,
      _kCaloriesKcal: caloriesKcal,
      _kPoints: points,
      _kElapsedSeconds: currentElapsedSeconds(),
      _kSessionId: sessionId,
      _kStartedAtIso: startedAt?.toIso8601String(),
      _kLatitude: lastPoint?.latitude,
      _kLongitude: lastPoint?.longitude,
    };
    service.invoke(_kUpdateEvent, payload);
    await prefs.setBool(_kIsTracking, isTracking);
    await prefs.setBool(_kIsAutoPaused, isAutoPaused);
    await prefs.setBool(_kIsManuallyPaused, isManuallyPaused);
    await prefs.setDouble(_kDistanceMeters, distanceMeters);
    await prefs.setDouble(_kElevationGainMeters, elevationGainMeters);
    await prefs.setDouble(_kCaloriesKcal, caloriesKcal);
    await prefs.setInt(_kPoints, points);
    await prefs.setInt(_kElapsedSeconds, currentElapsedSeconds());
    await prefs.setInt(_kAccumulatedActiveSeconds, accumulatedActiveSeconds);
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
    if (lastResumedAt != null) {
      await prefs.setString(
        _kLastResumedAtIso,
        lastResumedAt!.toIso8601String(),
      );
    } else {
      await prefs.remove(_kLastResumedAtIso);
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
    isManuallyPaused = false;
    accumulatedActiveSeconds = 0;
    lastResumedAt = DateTime.now().toUtc();
    stationarySince = null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final user = FirebaseAuth.instance.currentUser;
    final userDisplayName =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : (user?.email?.split('@').first ?? 'Runner');
    final username = userDisplayName.toLowerCase().replaceAll(' ', '_');

    // Load user metrics for personalized calorie calculation
    if (userId != null) {
      try {
        userMetrics = await metricsRepository.getUserMetrics(userId);
      } catch (e) {
        debugPrint('Failed to load user metrics: $e');
        userMetrics = null;
      }
    }

    await repository.createSession(
      sessionId: sessionId!,
      startedAt: startedAt!,
      userId: userId,
      userDisplayName: userDisplayName,
      username: username,
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

          if (isManuallyPaused) {
            lastPoint = point;
            await broadcastSnapshot();
            return;
          }

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

            if (!isAutoPaused && !isManuallyPaused) {
              distanceMeters += segmentMeters;
              // Use personalized calorie calculation if user metrics are available
              final elapsedSeconds = currentElapsedSeconds();
              caloriesKcal = CalorieCalculationUtil.calculateAdvancedCalories(
                metrics: userMetrics,
                distanceMeters: distanceMeters,
                durationSeconds: elapsedSeconds,
                elevationGainMeters: elevationGainMeters,
              );
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
            isManuallyPaused: isManuallyPaused,
            elapsedSeconds: currentElapsedSeconds(),
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
    if (lastResumedAt != null) {
      final extra = DateTime.now().toUtc().difference(lastResumedAt!).inSeconds;
      accumulatedActiveSeconds += extra > 0 ? extra : 0;
      lastResumedAt = null;
    }

    if (sessionId != null) {
      await repository.closeSession(
        sessionId: sessionId!,
        endedAt: DateTime.now().toUtc(),
        distanceMeters: distanceMeters,
        elevationGainMeters: elevationGainMeters,
        caloriesKcal: caloriesKcal,
        elapsedSeconds: accumulatedActiveSeconds,
        points: points,
      );
    }

    sessionId = null;
    startedAt = null;
    lastPoint = null;
    distanceMeters = 0;
    elevationGainMeters = 0;
    caloriesKcal = 0;
    points = 0;
    isAutoPaused = false;
    isManuallyPaused = false;
    accumulatedActiveSeconds = 0;
    lastResumedAt = null;
    stationarySince = null;
    await broadcastSnapshot();
  }

  Future<void> pause() async {
    if (!isTracking || isManuallyPaused) {
      return;
    }
    if (lastResumedAt != null) {
      final extra = DateTime.now().toUtc().difference(lastResumedAt!).inSeconds;
      accumulatedActiveSeconds += extra > 0 ? extra : 0;
      lastResumedAt = null;
    }
    isManuallyPaused = true;
    isAutoPaused = false;
    stationarySince = null;
    if (sessionId != null) {
      await repository.updatePauseState(
        sessionId: sessionId!,
        isManuallyPaused: true,
        elapsedSeconds: accumulatedActiveSeconds,
      );
    }
    await broadcastSnapshot();
  }

  Future<void> resume() async {
    if (!isTracking || !isManuallyPaused) {
      return;
    }
    isManuallyPaused = false;
    isAutoPaused = false;
    stationarySince = null;
    lastResumedAt = DateTime.now().toUtc();
    if (sessionId != null) {
      await repository.updatePauseState(
        sessionId: sessionId!,
        isManuallyPaused: false,
        elapsedSeconds: accumulatedActiveSeconds,
      );
    }
    await broadcastSnapshot();
  }

  service.on(_kStartEvent).listen((_) async {
    try {
      await start();
    } catch (error) {
      service.invoke(_kErrorEvent, {'message': 'Start failed: $error'});
    }
  });

  service.on(_kStopEvent).listen((_) async {
    try {
      await stop();
    } catch (error) {
      service.invoke(_kErrorEvent, {'message': 'Stop failed: $error'});
    }
  });
  service.on(_kPauseEvent).listen((_) async {
    try {
      await pause();
    } catch (error) {
      service.invoke(_kErrorEvent, {'message': 'Pause failed: $error'});
    }
  });
  service.on(_kResumeEvent).listen((_) async {
    try {
      await resume();
    } catch (error) {
      service.invoke(_kErrorEvent, {'message': 'Resume failed: $error'});
    }
  });
  await broadcastSnapshot();
}
