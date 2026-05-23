import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'package:fake_strava/core/maplibre_config.dart';
import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';

Widget buildFlyoverReplayPage({
  required List<geo.LatLng> points,
  required String title,
  List<double>? elevations,
  int durationSeconds = 0,
  double distanceKm = 0.0,
}) {
  return _FlyoverReplayPage(
    points: points,
    title: title,
    elevations: elevations,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
  );
}

class _FlyoverReplayPage extends StatefulWidget {
  const _FlyoverReplayPage({
    required this.points,
    required this.title,
    this.elevations,
    this.durationSeconds = 0,
    this.distanceKm = 0.0,
  });

  final List<geo.LatLng> points;
  final String title;
  final List<double>? elevations;
  final int durationSeconds;
  final double distanceKm;

  @override
  State<_FlyoverReplayPage> createState() => _FlyoverReplayPageState();
}

class _FlyoverReplayPageState extends State<_FlyoverReplayPage> {
  static const int _maxReplayPoints = 320;
  static const int _stepDurationMs = 650;
  static const double _tilt = 60;
  static const double _zoom = 16.3;
  static const double _metersPerKm = 1000;
  static const double _earthRadiusMeters = 6371000;

  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _routeLine;
  Timer? _timer;
  late final List<geo.LatLng> _replayPoints = _downsample(widget.points);
  late final List<double> _replayElevations = _downsampleElevations();
  late final List<maplibre.LatLng> _mapPoints = _replayPoints
      .map((point) => maplibre.LatLng(point.latitude, point.longitude))
      .toList(growable: false);
  late final List<double> _cumulativeDistances =
      _calculateCumulativeDistances();
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _styleReady = false;

  @override
  void dispose() {
    _timer?.cancel();
    if (_routeLine != null) {
      _controller?.removeLine(_routeLine!);
    }
    super.dispose();
  }

  List<double> _downsampleElevations() {
    if (widget.elevations == null || widget.elevations!.isEmpty) {
      return List<double>.filled(_replayPoints.length, 0.0);
    }
    if (widget.elevations!.length == widget.points.length) {
      if (widget.points.length <= _maxReplayPoints) {
        return widget.elevations!;
      }
      final stride = (widget.points.length / _maxReplayPoints).ceil();
      final sampled = <double>[];
      for (int i = 0; i < widget.elevations!.length; i += stride) {
        sampled.add(widget.elevations![i]);
      }
      if (sampled.isEmpty || sampled.length < _replayPoints.length) {
        sampled.add(widget.elevations!.last);
      }
      return sampled.take(_replayPoints.length).toList();
    }
    return List<double>.filled(_replayPoints.length, 0.0);
  }

  List<double> _calculateCumulativeDistances() {
    final distances = <double>[0.0];
    for (int i = 1; i < _replayPoints.length; i++) {
      final distance = _haversineDistance(
        _replayPoints[i - 1],
        _replayPoints[i],
      );
      distances.add(distances.last + distance);
    }
    return distances;
  }

  double _haversineDistance(geo.LatLng start, geo.LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final dLat = (end.latitude - start.latitude) * math.pi / 180;
    final dLon = (end.longitude - start.longitude) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (_earthRadiusMeters * c) / _metersPerKm;
  }

  String _formatDistance(double km) {
    return km.toStringAsFixed(2);
  }

  String _formatElevation(double meters) {
    return meters.toStringAsFixed(0);
  }

  String _formatPace() {
    if (widget.distanceKm <= 0 || widget.durationSeconds <= 0) {
      return '--:--';
    }
    final paceMinutesPerKm =
        (widget.durationSeconds / 60.0) / widget.distanceKm;
    final minutes = paceMinutesPerKm.toInt();
    final seconds = ((paceMinutesPerKm - minutes) * 60).toInt();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  List<geo.LatLng> _downsample(List<geo.LatLng> points) {
    if (points.length <= _maxReplayPoints) {
      return points;
    }
    final stride = (points.length / _maxReplayPoints).ceil();
    final sampled = <geo.LatLng>[];
    for (int i = 0; i < points.length; i += stride) {
      sampled.add(points[i]);
    }
    if (sampled.isEmpty || sampled.last != points.last) {
      sampled.add(points.last);
    }
    return sampled;
  }

  void _onMapCreated(maplibre.MapLibreMapController controller) {
    _controller = controller;
  }

  Future<void> _loadRouteStyle() async {
    if (_styleReady || _controller == null || _mapPoints.length < 2) {
      return;
    }
    _styleReady = true;
    await _applyTerrain();
    _routeLine = await _controller!.addLine(
      maplibre.LineOptions(
        geometry: _mapPoints,
        lineColor: _colorHex(kBrandOrange),
        lineWidth: 5.5,
        lineJoin: 'round',
      ),
    );
    await _controller!.animateCamera(
      maplibre.CameraUpdate.newCameraPosition(
        maplibre.CameraPosition(
          target: _mapPoints.first,
          zoom: _zoom,
          tilt: _tilt,
          bearing: 0,
        ),
      ),
      duration: const Duration(milliseconds: 600),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyTerrain() async {
    final terrainUrl = kResolvedMapTerrainUrl;
    if (terrainUrl.isEmpty) {
      return;
    }
    await _controller!.addSource(
      'terrain-source',
      maplibre.RasterDemSourceProperties(
        url: terrainUrl,
        encoding: kMapTerrainEncoding,
        tileSize: 512,
      ),
    );
    await _controller!.addHillshadeLayer(
      'terrain-source',
      'terrain-hillshade',
      maplibre.HillshadeLayerProperties(hillshadeExaggeration: 0.6),
    );
  }

  String _colorHex(Color color) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2)}';
  }

  void _togglePlay() {
    if (_isPlaying) {
      _pauseFlyover();
    } else {
      _startFlyover();
    }
  }

  void _startFlyover() {
    if (_controller == null || _mapPoints.length < 2) {
      return;
    }
    if (_currentIndex >= _replayPoints.length - 1) {
      _currentIndex = 0;
    }
    setState(() {
      _isPlaying = true;
    });
    _scheduleNextStep();
  }

  void _pauseFlyover() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _restartFlyover() {
    _timer?.cancel();
    setState(() {
      _currentIndex = 0;
      _isPlaying = false;
    });
    _startFlyover();
  }

  void _scheduleNextStep() {
    if (!_isPlaying || _controller == null) {
      return;
    }
    if (_currentIndex >= _replayPoints.length - 1) {
      _pauseFlyover();
      return;
    }
    final current = _replayPoints[_currentIndex];
    final next = _replayPoints[_currentIndex + 1];
    final bearing = _bearingBetween(current, next);
    _controller!.animateCamera(
      maplibre.CameraUpdate.newCameraPosition(
        maplibre.CameraPosition(
          target: maplibre.LatLng(next.latitude, next.longitude),
          zoom: _zoom,
          tilt: _tilt,
          bearing: bearing,
        ),
      ),
      duration: const Duration(milliseconds: _stepDurationMs),
    );
    setState(() {
      _currentIndex += 1;
    });
    _timer = Timer(
      const Duration(milliseconds: _stepDurationMs),
      _scheduleNextStep,
    );
  }

  double _bearingBetween(geo.LatLng start, geo.LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final dLon = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = kResolvedMapStyleUrl;
    if (styleUrl.isEmpty) {
      return Scaffold(
        backgroundColor: kSurface,
        appBar: AppBar(
          title: Text(widget.title, style: AppTypography.headingMedium),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Map style URL or MapTiler key is missing.'),
        ),
      );
    }

    if (_mapPoints.length < 2) {
      return Scaffold(
        backgroundColor: kSurface,
        appBar: AppBar(
          title: Text(widget.title, style: AppTypography.headingMedium),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Not enough route data for a flyover replay.'),
        ),
      );
    }

    final progress = _replayPoints.length <= 1
        ? 0.0
        : (_currentIndex / (_replayPoints.length - 1)).clamp(0.0, 1.0);

    final currentDistance = _currentIndex < _cumulativeDistances.length
        ? _cumulativeDistances[_currentIndex]
        : 0.0;
    final currentElevation = _currentIndex < _replayElevations.length
        ? _replayElevations[_currentIndex]
        : 0.0;
    final pace = _formatPace();

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        title: Text('3D Flyover', style: AppTypography.headingMedium),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: styleUrl,
            initialCameraPosition: maplibre.CameraPosition(
              target: _mapPoints.first,
              zoom: _zoom,
              tilt: _tilt,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: () {
              _loadRouteStyle();
            },
            myLocationEnabled: false,
            compassEnabled: false,
          ),
          // Top stats overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      'Distance',
                      '${_formatDistance(currentDistance)} km',
                    ),
                    _buildStatColumn(
                      'Elevation',
                      '${_formatElevation(currentElevation)} m',
                    ),
                    _buildStatColumn('Pace', '$pace /km'),
                  ],
                ),
              ),
            ),
          ),
          // Bottom controls
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlay,
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(
                      onPressed: _restartFlyover,
                      icon: const Icon(Icons.replay),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flyover progress',
                            style: AppTypography.labelSmall,
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: kDivider,
                            color: kBrandOrange,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_currentIndex + 1}/${_replayPoints.length}',
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_styleReady)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: kBrandOrange,
          ),
        ),
      ],
    );
  }
}
