// [File: lib/services/calorie_calculator.dart]
// ✅ Đổi import sang file Entity mới
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

class CalorieCalculator {
  // Đổi tham số đầu vào từ ProfileModel -> ProfileEntity
  static int calculateTDEE(ProfileEntity profile) {
    if (!profile.isValid) return 0; // isValid getter có sẵn trong Entity

    double bmr;
    // Gender enum lấy từ ProfileEntity
    if (profile.gender == Gender.male) {
      bmr = (10 * profile.weight!) +
          (6.25 * profile.height!) -
          (5 * profile.age!) +
          5;
    } else {
      bmr = (10 * profile.weight!) +
          (6.25 * profile.height!) -
          (5 * profile.age!) -
          161;
    }

    double multiplier = 1.2;
    // ActivityLevel enum lấy từ ProfileEntity
    switch (profile.activityLevel) {
      case ActivityLevel.low:
        multiplier = 1.2;
        break;
      case ActivityLevel.medium:
        multiplier = 1.55;
        break;
      case ActivityLevel.high:
        multiplier = 1.9;
        break;
    }

    double tdee = bmr * multiplier;

    // Goal enum lấy từ ProfileEntity
    switch (profile.goal) {
      case Goal.lose_weight:
        return (tdee - 500).round();
      case Goal.gain_muscle:
        return (tdee + 300).round();
      case Goal.maintain_weight:
        return tdee.round();
    }
  }
}
