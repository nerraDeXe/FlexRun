import 'package:fake_strava/profile/user_metrics.dart';

/// Utility for calculating calorie burn with personalized metrics
class CalorieCalculationUtil {
  /// Default BMR in kcal/day (estimated for average adult)
  static const double _defaultBMR = 1700.0;

  /// MET (Metabolic Equivalent) values for running at different speeds (km/h)
  static const Map<String, double> _runningMETs = {
    'slow': 8.3, // < 8 km/h (slow jog)
    'moderate': 9.8, // 8-10 km/h (moderate pace)
    'fast': 11.0, // 10-12 km/h (fast pace)
    'very_fast': 13.0, // > 12 km/h (very fast)
  };

  /// Calculate BMR (Basal Metabolic Rate) in kcal/day
  /// If metrics are available, uses Mifflin-St Jeor formula
  /// Otherwise returns default estimate
  static double calculateBMR(UserMetrics? metrics) {
    if (metrics == null) {
      return _defaultBMR;
    }
    return metrics.calculateBMR();
  }

  /// Calculate calories burned during activity
  /// [bmr] - Basal Metabolic Rate in kcal/day
  /// [durationMinutes] - Activity duration in minutes
  /// [speedKmh] - Average speed in km/h (optional, defaults to moderate running)
  /// Returns estimated calories burned in kcal
  static double calculateCaloriesBurned({
    required double bmr,
    required int durationMinutes,
    double speedKmh = 9.0,
  }) {
    final met = _getMETValue(speedKmh);

    // Formula: Calories = (MET × weight_kg × duration_hours)
    // We need to estimate weight from BMR for default case
    // BMR ≈ 10 × weight + adjustment_factors
    // For simplicity: weight_estimate ≈ (BMR - adjustment) / 10

    // Better approach: use BMR directly with activity factor
    // Calories = BMR × (duration_minutes / 1440) × (MET / 1.0)
    final durationHours = durationMinutes / 60.0;

    // Estimate weight from BMR (rough approximation)
    // Average person: BMR ≈ 1500-1700, weight ≈ 70kg
    // Use linear approximation: weight ≈ BMR / 24
    final estimatedWeight = bmr / 24.0;

    return met * estimatedWeight * durationHours;
  }

  /// Get MET value based on running speed
  static double _getMETValue(double speedKmh) {
    if (speedKmh < 8) return _runningMETs['slow']!;
    if (speedKmh < 10) return _runningMETs['moderate']!;
    if (speedKmh < 12) return _runningMETs['fast']!;
    return _runningMETs['very_fast']!;
  }

  /// Calculate average speed in km/h from distance and time
  static double calculateSpeedKmh(double distanceMeters, int durationSeconds) {
    if (durationSeconds == 0) return 0.0;
    final distanceKm = distanceMeters / 1000.0;
    final durationHours = durationSeconds / 3600.0;
    return distanceKm / durationHours;
  }

  /// Advanced calorie calculation combining multiple factors
  /// This provides a more accurate estimate considering:
  /// - User metrics (BMR)
  /// - Elevation gain (additional effort)
  /// - Individual metrics like heart rate if available
  static double calculateAdvancedCalories({
    required UserMetrics? metrics,
    required double distanceMeters,
    required int durationSeconds,
    required double elevationGainMeters,
    int? averageHeartRate,
  }) {
    if (durationSeconds == 0) return 0.0;

    final bmr = calculateBMR(metrics);
    final speedKmh = calculateSpeedKmh(distanceMeters, durationSeconds);

    // Base calories from running
    var calories = calculateCaloriesBurned(
      bmr: bmr,
      durationMinutes: durationSeconds ~/ 60,
      speedKmh: speedKmh,
    );

    // Add elevation bonus (approximate 0.5 kcal per meter of elevation)
    calories += elevationGainMeters * 0.5;

    // If heart rate data is available, adjust based on intensity
    if (averageHeartRate != null && averageHeartRate > 0) {
      // Rough heart rate adjustment factor
      // Assuming max HR ≈ 220 - age
      final estimatedMaxHR = metrics != null ? 220 - metrics.age : 180;
      final intensityFactor = averageHeartRate / estimatedMaxHR;

      // Apply intensity multiplier (0.8 to 1.3 range)
      final adjustedIntensity = 0.8 + (intensityFactor * 0.5);
      calories *= adjustedIntensity.clamp(0.8, 1.3);
    }

    return calories;
  }
}
