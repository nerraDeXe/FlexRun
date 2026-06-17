import 'package:fake_strava/profile/user_metrics.dart';

/// Utility for calculating calorie burn with personalized metrics
/// Based on ACSM (American College of Sports Medicine) guidelines
class CalorieCalculationUtil {
  /// Default BMR in kcal/day (estimated for average adult)
  static const double _defaultBMR = 1700.0;

  /// Default weight in kg (estimated for average adult)
  static const double _defaultWeight = 70.0;

  /// Default MET for moderate running
  static const double _defaultMET = 9.8;

  /// MET (Metabolic Equivalent) values for various activities
  /// Values from Compendium of Physical Activities
  static const Map<String, Map<String, double>> _activityMETs = {
    'running': {
      'slow': 8.0, // 8 km/h
      'moderate': 9.8, // 10 km/h
      'fast': 11.5, // 12 km/h
      'very_fast': 13.5, // 14+ km/h
      'walking': 4.0, // Walking
      'jogging': 7.0, // Light jogging
    },
    'cycling': {'leisure': 4.0, 'moderate': 8.0, 'vigorous': 12.0},
    'swimming': {'leisure': 6.0, 'moderate': 8.0, 'vigorous': 10.0},
  };

  /// Calculate BMR (Basal Metabolic Rate) in kcal/day using Mifflin-St Jeor formula
  /// If metrics are available, uses personalized calculation
  /// Otherwise returns default estimate
  static double calculateBMR(UserMetrics? metrics) {
    if (metrics == null) {
      return _defaultBMR;
    }
    return metrics.calculateBMR();
  }

  /// Get MET value based on activity type and speed/intensity
  static double _getMETValue({
    required String activityType,
    double speedKmh = 9.0,
    int intensity = 1, // 1 = low, 2 = moderate, 3 = high
  }) {
    final activities = _activityMETs[activityType];
    if (activities == null) return _defaultMET;

    // For running, use speed-based lookup
    if (activityType == 'running') {
      if (speedKmh < 4) return activities['walking']!;
      if (speedKmh < 7) return activities['jogging']!;
      if (speedKmh < 9) return activities['slow']!;
      if (speedKmh < 11) return activities['moderate']!;
      if (speedKmh < 13) return activities['fast']!;
      return activities['very_fast']!;
    }

    // For other activities, use intensity
    if (intensity == 1) return activities['leisure'] ?? _defaultMET;
    if (intensity == 2) return activities['moderate'] ?? _defaultMET;
    return activities['vigorous'] ?? _defaultMET;
  }

  /// Calculate calories burned during activity
  /// This is the standard ACSM formula: Calories = MET × Weight(kg) × Duration(hours)
  static double calculateCaloriesBurned({
    required double weightKg,
    required int durationMinutes,
    required double met,
  }) {
    if (weightKg <= 0 || durationMinutes <= 0 || met <= 0) {
      return 0.0;
    }

    final durationHours = durationMinutes / 60.0;
    return met * weightKg * durationHours;
  }

  /// Calculate calories with user metrics
  /// Returns calories burned in kcal
  static double calculateCaloriesWithMetrics({
    required UserMetrics? metrics,
    required double distanceMeters,
    required int durationSeconds,
    String activityType = 'running',
    double elevationGainMeters = 0.0,
  }) {
    // Validate inputs
    if (durationSeconds <= 0 || distanceMeters < 0) {
      return 0.0;
    }

    // Get user weight
    final weightKg = metrics?.weightKg ?? _defaultWeight;
    if (weightKg <= 0) return 0.0;

    // Calculate speed
    final speedKmh = calculateSpeedKmh(distanceMeters, durationSeconds);
    final durationMinutes = durationSeconds / 60.0;

    // Get MET value
    final met = _getMETValue(activityType: activityType, speedKmh: speedKmh);

    // Base calorie calculation
    var calories = calculateCaloriesBurned(
      weightKg: weightKg,
      durationMinutes: durationMinutes.toInt(),
      met: met,
    );

    // Add elevation correction (more scientifically accurate)
    if (elevationGainMeters > 0) {
      // ACSM formula for uphill running: additional 0.75 kcal per kg per km
      // Simplified: 1 MET increase per 5% grade
      final gradePercent = distanceMeters > 0
          ? (elevationGainMeters / distanceMeters) * 100
          : 0.0;

      // Additional MET for uphill (1 MET per 5% grade)
      final elevationMET = gradePercent / 5.0;
      final elevationCalories = calculateCaloriesBurned(
        weightKg: weightKg,
        durationMinutes: durationMinutes.toInt(),
        met: elevationMET,
      );
      calories += elevationCalories;
    }

    return calories;
  }

  /// Calculate average speed in km/h from distance and time
  static double calculateSpeedKmh(double distanceMeters, int durationSeconds) {
    if (durationSeconds == 0 || distanceMeters < 0) return 0.0;
    final distanceKm = distanceMeters / 1000.0;
    final durationHours = durationSeconds / 3600.0;
    return distanceKm / durationHours;
  }

  /// Calculate pace in minutes per kilometer
  static double calculatePaceMinutesPerKm(
    double distanceMeters,
    int durationSeconds,
  ) {
    if (durationSeconds == 0 || distanceMeters <= 0) return 0.0;
    final distanceKm = distanceMeters / 1000.0;
    return (durationSeconds / 60.0) / distanceKm;
  }

  /// Advanced calorie calculation with multiple factors
  /// Provides a more accurate estimate considering:
  /// - User metrics (age, gender, height, weight)
  /// - Activity type and intensity
  /// - Elevation gain
  /// - Fitness level (via HR data if available)
  static double calculateAdvancedCalories({
    required UserMetrics? metrics,
    required double distanceMeters,
    required int durationSeconds,
    required double elevationGainMeters,
    String activityType = 'running',
    int? averageHeartRate,
    int? maxHeartRate,
  }) {
    if (durationSeconds <= 0 || distanceMeters < 0) {
      return 0.0;
    }

    // Base calculation with metrics
    var calories = calculateCaloriesWithMetrics(
      metrics: metrics,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      activityType: activityType,
      elevationGainMeters: elevationGainMeters,
    );

    // Heart rate correction (if available)
    if (averageHeartRate != null && maxHeartRate != null && maxHeartRate > 0) {
      final hrIntensity = averageHeartRate / maxHeartRate;
      // HR-based correction factor (0.8-1.5 based on intensity)
      final hrCorrection = 0.8 + (hrIntensity * 0.7);
      calories *= hrCorrection;
    }

    // Fitness level adjustment (if metrics have age)
    if (metrics != null && metrics.age > 0) {
      // Younger people generally have higher metabolism
      final ageFactor = 1.0 - ((metrics.age - 20) / 100).clamp(0.0, 0.3);
      calories *= (1.0 + (1.0 - ageFactor) * 0.2);
    }

    return calories;
  }

  /// Calculate calories per kilometer
  /// Useful for comparing effort across different distances
  static double calculateCaloriesPerKm({
    required UserMetrics? metrics,
    required double distanceMeters,
    required int durationSeconds,
    String activityType = 'running',
  }) {
    if (distanceMeters <= 0) return 0.0;

    final totalCalories = calculateCaloriesWithMetrics(
      metrics: metrics,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      activityType: activityType,
    );

    final distanceKm = distanceMeters / 1000.0;
    return totalCalories / distanceKm;
  }

  /// Calculate estimated weight loss from calories burned
  /// Returns weight loss in grams
  static double calculateWeightLossGrams(double caloriesBurned) {
    // 1 kg of body fat ≈ 7700 kcal
    return caloriesBurned / 7.7;
  }

  /// Validate input parameters and return a clear error message
  static String? validateInputs({
    required double distanceMeters,
    required int durationSeconds,
    required double weightKg,
  }) {
    if (distanceMeters < 0) {
      return 'Distance cannot be negative';
    }
    if (durationSeconds < 0) {
      return 'Duration cannot be negative';
    }
    if (weightKg <= 0) {
      return 'Weight must be greater than 0';
    }
    if (weightKg > 300) {
      return 'Weight seems unrealistic (maximum 300 kg)';
    }
    if (distanceMeters > 1000000) {
      return 'Distance seems unrealistic (maximum 1000 km)';
    }
    if (durationSeconds > 86400 * 7) {
      return 'Duration seems unrealistic (maximum 7 days)';
    }
    return null;
  }

  /// Get descriptive intensity level based on MET value
  static String getIntensityDescription(double met) {
    if (met < 3.0) return 'Light activity';
    if (met < 6.0) return 'Moderate activity';
    if (met < 9.0) return 'Vigorous activity';
    if (met < 12.0) return 'High intensity activity';
    return 'Maximum effort activity';
  }

  /// Get estimated heart rate zone based on intensity
  static int getEstimatedHeartRateZone(double met, int maxHeartRate) {
    // MET to HR percentage: 1 MET ≈ 25% of HR reserve
    final hrPercentage = (met / 12.0).clamp(0.0, 1.0);
    return (maxHeartRate * hrPercentage).toInt();
  }
}

/// Extension methods for UserMetrics to provide calorie-related calculations
extension UserMetricsCalorieExtension on UserMetrics {
  /// Calculate calories burned for a specific activity
  double calculateActivityCalories({
    required double distanceMeters,
    required int durationSeconds,
    required double elevationGainMeters,
    String activityType = 'running',
  }) {
    return CalorieCalculationUtil.calculateAdvancedCalories(
      metrics: this,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      elevationGainMeters: elevationGainMeters,
      activityType: activityType,
    );
  }

  /// Get estimated weight in kg (uses stored weight)
  double get weightKg => this.weightKg;

  /// Get estimated BMR
  double get bmr => calculateBMR();

  /// Get daily calorie expenditure based on activity level
  double getDailyCalorieExpenditure({required ActivityLevel activityLevel}) {
    // Total Daily Energy Expenditure (TDEE)
    final bmr = calculateBMR();
    final multiplier = activityLevel.multiplier;
    return bmr * multiplier;
  }
}

/// Activity level enum for TDEE calculation
enum ActivityLevel {
  sedentary(1.2, 'Sedentary (little or no exercise)'),
  light(1.375, 'Lightly active (1-3 days/week)'),
  moderate(1.55, 'Moderately active (3-5 days/week)'),
  active(1.725, 'Very active (6-7 days/week)'),
  extreme(1.9, 'Extremely active (athlete, intense daily)');

  const ActivityLevel(this.multiplier, this.description);

  final double multiplier;
  final String description;
}
