// File: lib/features/profile/data/models/profile_model.dart
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

class ProfileModel extends ProfileEntity {
  const ProfileModel({
    super.age,
    super.height,
    super.weight,
    super.gender,
    super.activityLevel,
    super.goal,
    super.allergies = const [],
  });

  // --- FACTORY: TỪ ENTITY SANG MODEL ---
  factory ProfileModel.fromEntity(ProfileEntity entity) {
    return ProfileModel(
      age: entity.age,
      height: entity.height,
      weight: entity.weight,
      gender: entity.rawGender,
      activityLevel: entity.rawActivityLevel,
      goal: entity.rawGoal,
      allergies: entity.allergies,
    );
  }

  static Gender? _parseGender(dynamic val) {
    if (val == null) return null;
    final str = val.toString().toLowerCase();
    switch (str) {
      case 'female':
        return Gender.female;
      case 'other':
        return Gender.other;
      case 'male':
        return Gender.male;
      default:
        return null;
    }
  }

  static ActivityLevel? _parseActivityLevel(dynamic val) {
    if (val == null) return null;
    final str = val.toString().toLowerCase();
    switch (str) {
      case 'low':
      case 'sedentary':
      case 'light':
        return ActivityLevel.low;
      case 'high':
      case 'active':
      case 'very_active':
        return ActivityLevel.high;
      case 'medium':
      case 'moderate':
        return ActivityLevel.medium;
      default:
        return null;
    }
  }

  static Goal? _parseGoal(dynamic val) {
    if (val == null) return null;
    final str = val.toString().toLowerCase();
    switch (str) {
      case 'lose_weight':
      case 'weight_loss':
      case 'lose':
        return Goal.lose_weight;
      case 'gain_muscle':
      case 'muscle_gain':
      case 'gain':
        return Goal.gain_muscle;
      case 'maintain_weight':
      case 'maintain':
        return Goal.maintain_weight;
      default:
        return null;
    }
  }

  // --- MAPPER: TỪ JSON (BACKEND/LOCAL) SANG MODEL ---
  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      age: json['age'] as int?,
      // Backend trả về float, cần parse an toàn
      height: (json['height'] as num?)?.toDouble(),
      weight: (json['weight'] as num?)?.toDouble(),
      // Parse Enum từ String có hỗ trợ alias (null nếu backend không có)
      gender: _parseGender(json['gender']),
      activityLevel: _parseActivityLevel(
        json['activity_level'] ?? json['activityLevel'],
      ),
      goal: _parseGoal(json['goal']),
      allergies: (json['allergies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  // --- MAPPER: TỪ MODEL SANG JSON (GỬI LÊN BACKEND) ---
  Map<String, dynamic> toJson() {
    // Map goal enum to backend expected values
    const goalApiMap = {
      'gain': 'gain_muscle',
      'gain_muscle': 'gain_muscle',
      'lose': 'lose_weight',
      'lose_weight': 'lose_weight',
      'maintain': 'maintain_weight',
      'maintain_weight': 'maintain_weight',
    };

    return {
      'age': age,
      'height': height,
      'weight': weight,
      'gender': rawGender?.name, // Enum -> String
      // QUAN TRỌNG: Map đúng key 'activity_level' của UserProfileInput (Python)
      'activity_level': rawActivityLevel?.name,
      'goal': rawGoal != null ? (goalApiMap[rawGoal!.name] ?? rawGoal!.name) : null,
      'allergies': allergies,
    };
  }

  /// Request payload mapper strictly matching backend UserProfileInput (Python)
  /// Backend does not store or declare 'allergies' in UserProfileInput.
  Map<String, dynamic> toUpdateJson() {
    const goalApiMap = {
      'gain': 'gain_muscle',
      'gain_muscle': 'gain_muscle',
      'lose': 'lose_weight',
      'lose_weight': 'lose_weight',
      'maintain': 'maintain_weight',
      'maintain_weight': 'maintain_weight',
    };

    return {
      'age': age,
      'height': height,
      'weight': weight,
      'gender': rawGender?.name,
      'activity_level': rawActivityLevel?.name,
      'goal': rawGoal != null ? (goalApiMap[rawGoal!.name] ?? rawGoal!.name) : null,
    };
  }
}
