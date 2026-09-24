// File: lib/features/profile/data/models/profile_model.dart
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

class ProfileModel extends ProfileEntity {
  const ProfileModel({
    required super.age,
    required super.height,
    required super.weight,
    required super.gender,
    required super.activityLevel,
    required super.goal,
    required super.allergies,
  });

  // --- FACTORY: TỪ ENTITY SANG MODEL ---
  factory ProfileModel.fromEntity(ProfileEntity entity) {
    return ProfileModel(
      age: entity.age,
      height: entity.height,
      weight: entity.weight,
      gender: entity.gender,
      activityLevel: entity.activityLevel,
      goal: entity.goal,
      allergies: entity.allergies,
    );
  }

  // --- MAPPER: TỪ JSON (BACKEND/LOCAL) SANG MODEL ---
  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      age: json['age'] as int?,
      // Backend trả về float, cần parse an toàn
      height: (json['height'] as num?)?.toDouble(),
      weight: (json['weight'] as num?)?.toDouble(),
      // Parse Enum từ String
      gender: Gender.values.firstWhere(
        (e) => e.name == (json['gender'] as String? ?? 'male'),
        orElse: () => Gender.male,
      ),
      // Lưu ý: Backend dùng 'activity_level' (snake_case)
      activityLevel: ActivityLevel.values.firstWhere(
        (e) =>
            e.name ==
            (json['activity_level'] ?? json['activityLevel'] ?? 'medium'),
        orElse: () => ActivityLevel.medium,
      ),
      goal: Goal.values.firstWhere(
        (e) => e.name == (json['goal'] as String? ?? 'maintain_weight'),
        orElse: () => Goal.maintain_weight,
      ),
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
      'gender': gender.name, // Enum -> String
      // QUAN TRỌNG: Map đúng key 'activity_level' của UserProfileInput (Python)
      'activity_level': activityLevel.name,
      'goal': goalApiMap[goal.name] ?? 'maintain_weight',
      'allergies': allergies,
    };
  }
}
