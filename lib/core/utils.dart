import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

String humanizeAuthError(Object error) {
  if (error is! FirebaseAuthException) {
    return error.toString();
  }
  switch (error.code) {
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'email-already-in-use':
      return 'This email is already registered. Try another one.';
    case 'weak-password':
      return 'Password is too weak. Use at least 6 characters.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again shortly.';
    case 'requires-recent-login':
      return 'Please re-authenticate with your current password and try again.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is disabled in Firebase Console.';
    default:
      return error.message ?? 'Authentication failed.';
  }
}

String formatSessionDuration(
  DateTime? startedAt,
  DateTime? endedAt, {
  int? durationSeconds,
}) {
  if (durationSeconds != null) {
    final Duration duration = Duration(seconds: durationSeconds);
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString()}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  if (startedAt != null && endedAt != null) {
    final Duration duration = endedAt.difference(startedAt);
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString()}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  return '0:00';
}

/// Spatio-Temporal Matching Utilities

/// Generates a geohash-like string from latitude and longitude
/// Using simple grid-based quantization (precision 6 = ~1.2 km accuracy)
/// Format: lat_grid|lon_grid for easier Firestore querying
String generateGeohash(double latitude, double longitude, {int precision = 6}) {
  // Simple quantization approach: divide into grid cells
  // precision 6 means dividing into 10^6 cells per degree
  final factor = math.pow(10, precision).toDouble();
  final latGrid = (latitude * factor).floor();
  final lonGrid = (longitude * factor).floor();
  return '${latGrid.toString().padLeft(10, '0')}_${lonGrid.toString().padLeft(10, '0')}';
}

/// Gets the parent geohash (one level less precise) for broader area matching
/// E.g., 'w0zq85' -> 'w0zq8' -> 'w0zq'
String getParentGeohash(String geohash) {
  return geohash.isEmpty ? '' : geohash.substring(0, geohash.length - 1);
}

/// Calculates bearing (direction) between two points in degrees (0-360)
/// 0° = North, 90° = East, 180° = South, 270° = West
double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = lon2 - lon1;
  final y = math.sin(dLon * math.pi / 180) * math.cos(lat2 * math.pi / 180);
  final x =
      math.cos(lat1 * math.pi / 180) * math.sin(lat2 * math.pi / 180) -
      math.sin(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.cos(dLon * math.pi / 180);
  final bearing = math.atan2(y, x) * 180 / math.pi;
  return (bearing + 360) % 360; // Normalize to 0-360
}

/// Checks if two bearings are similar (within tolerance degrees)
/// Returns true if difference is less than tolerance or greater than (360-tolerance)
bool areBearingsSimilar(
  double bearing1,
  double bearing2, {
  double tolerance = 45,
}) {
  final diff = (bearing2 - bearing1).abs();
  return diff <= tolerance || diff >= (360 - tolerance);
}

/// Calculates Haversine distance between two points in kilometers
double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371; // Earth's radius in km
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}
