// [File: lib/features/profile/domain/entities/profile_entity.dart]
// Nếu chưa có, hãy thêm equatable vào pubspec.yaml hoặc bỏ extend
// Nếu không muốn cài thêm package, chỉ cần class thường:

enum Gender { male, female, other }

enum ActivityLevel { low, medium, high }

enum Goal { lose_weight, maintain_weight, gain_muscle }

class ProfileEntity {
  final int? age;
  final double? height; // cm
  final double? weight; // kg
  final Gender gender;
  final ActivityLevel activityLevel;
  final Goal goal;
  final List<String> allergies;

  const ProfileEntity({
    this.age,
    this.height,
    this.weight,
    this.gender = Gender.male,
    this.activityLevel = ActivityLevel.medium,
    this.goal = Goal.maintain_weight,
    this.allergies = const [],
  });

  // Logic nghiệp vụ: Kiểm tra profile hợp lệ
  bool get isValid {
    return (age != null && age! >= 10 && age! <= 100) &&
        (height != null && height! >= 50 && height! <= 250) &&
        (weight != null && weight! > 0);
  }

  factory ProfileEntity.empty() {
    return const ProfileEntity();
  }
}
