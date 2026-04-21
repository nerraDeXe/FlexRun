/// Represents user biometric data for calorie calculation
class UserMetrics {
  const UserMetrics({
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.gender,
  });

  /// Height in centimeters
  final double heightCm;

  /// Weight in kilograms
  final double weightKg;

  /// Age in years
  final int age;

  /// Gender: 'M' for male, 'F' for female
  final String gender;

  /// Calculate Basal Metabolic Rate (BMR) using Mifflin-St Jeor formula
  /// Returns BMR in kcal/day
  double calculateBMR() {
    const maleGenderFactor = 5.0;
    const femaleGenderFactor = -161.0;

    final genderFactor = gender.toUpperCase() == 'M'
        ? maleGenderFactor
        : femaleGenderFactor;

    return (10 * weightKg) + (6.25 * heightCm) - (5 * age) + genderFactor;
  }

  /// Convert from Firestore data
  factory UserMetrics.fromMap(Map<String, dynamic> map) {
    return UserMetrics(
      heightCm: (map['heightCm'] as num).toDouble(),
      weightKg: (map['weightKg'] as num).toDouble(),
      age: map['age'] as int,
      gender: map['gender'] as String,
    );
  }

  /// Convert to Firestore data
  Map<String, dynamic> toMap() {
    return {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'age': age,
      'gender': gender,
    };
  }

  /// Create a copy with optional field replacements
  UserMetrics copyWith({
    double? heightCm,
    double? weightKg,
    int? age,
    String? gender,
  }) {
    return UserMetrics(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      age: age ?? this.age,
      gender: gender ?? this.gender,
    );
  }

  @override
  String toString() {
    return 'UserMetrics(heightCm: $heightCm, weightKg: $weightKg, age: $age, gender: $gender)';
  }
}
