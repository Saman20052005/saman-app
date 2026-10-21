// [File: lib/features/profile/domain/entities/profile_entity.dart]
// Nếu chưa có, hãy thêm equatable vào pubspec.yaml hoặc bỏ extend
// Nếu không muốn cài thêm package, chỉ cần class thường:

enum Gender { male, female, other }

enum ActivityLevel { low, medium, high }

// ignore: constant_identifier_names
enum Goal { lose_weight, maintain_weight, gain_muscle }

class ProfileEntity {
  final String? userId;
  final int? age;
  final double? height; // cm
  final double? weight; // kg
  final Gender? _gender;
  final ActivityLevel? _activityLevel;
  final String? _activityCanonical;
  final Goal? _goal;
  final List<String> allergies;

  const ProfileEntity({
    this.userId,
    this.age,
    this.height,
    this.weight,
    Gender? gender,
    ActivityLevel? activityLevel,
    String? activityCanonical,
    Goal? goal,
    this.allergies = const [],
  })  : _gender = gender,
        _activityLevel = activityLevel,
        _activityCanonical = activityCanonical,
        _goal = goal;

  Gender get gender => _gender ?? Gender.male;
  ActivityLevel get activityLevel => _activityLevel ?? ActivityLevel.medium;
  Goal get goal => _goal ?? Goal.maintain_weight;

  Gender? get rawGender => _gender;
  ActivityLevel? get rawActivityLevel => _activityLevel;
  String? get rawActivityCanonical => _activityCanonical;
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

  /// Checks if all six mandatory raw profile fields are present and valid.
  /// Does NOT rely on fallback defaults (_gender ?? Gender.male, etc.).
  bool get isComplete {
    return (age != null && age! >= 13 && age! <= 120) &&
        (height != null && height!.isFinite && height! > 0) &&
        (weight != null && weight!.isFinite && weight! > 0) &&
        _gender != null &&
        (_activityCanonical != null || _activityLevel != null) &&
        _goal != null;
  }

  factory ProfileEntity.empty({String? userId}) {
    return ProfileEntity(userId: userId);
  }
}
