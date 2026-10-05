// [File: lib/features/profile/domain/entities/profile_entity.dart]
// Nếu chưa có, hãy thêm equatable vào pubspec.yaml hoặc bỏ extend
// Nếu không muốn cài thêm package, chỉ cần class thường:

enum Gender { male, female, other }

enum ActivityLevel { low, medium, high }

// ignore: constant_identifier_names
enum Goal { lose_weight, maintain_weight, gain_muscle }

class ProfileEntity {
  final int? age;
  final double? height; // cm
  final double? weight; // kg
  final Gender? _gender;
  final ActivityLevel? _activityLevel;
  final Goal? _goal;
  final List<String> allergies;

  const ProfileEntity({
    this.age,
    this.height,
    this.weight,
    Gender? gender,
    ActivityLevel? activityLevel,
    Goal? goal,
    this.allergies = const [],
  })  : _gender = gender,
        _activityLevel = activityLevel,
        _goal = goal;

  Gender get gender => _gender ?? Gender.male;
  ActivityLevel get activityLevel => _activityLevel ?? ActivityLevel.medium;
  Goal get goal => _goal ?? Goal.maintain_weight;

  Gender? get rawGender => _gender;
  ActivityLevel? get rawActivityLevel => _activityLevel;
  Goal? get rawGoal => _goal;

  bool get hasGender => _gender != null;
  bool get hasActivityLevel => _activityLevel != null;
  bool get hasGoal => _goal != null;

  // Logic nghiệp vụ: Đồng bộ hoàn toàn với UserProfileInput của backend (age: 13-120, height > 0, weight > 0)
  bool get isValid {
    return (age != null && age! >= 13 && age! <= 120) &&
        (height != null && height! > 0) &&
        (weight != null && weight! > 0);
  }

  factory ProfileEntity.empty() {
    return const ProfileEntity();
  }
}
