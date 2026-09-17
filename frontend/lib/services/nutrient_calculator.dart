// [File: lib/services/nutrient_calculator.dart]
// ✅ Đổi import sang file Entity mới
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';

class NutrientCalculator {
  // Đổi tham số từ ProfileModel -> ProfileEntity
  static Map<String, int> calculateMacros(ProfileEntity profile, int tdee) {
    double pRatio = 0.25;
    double cRatio = 0.50;
    double fRatio = 0.25;

    // Goal enum lấy từ ProfileEntity
    switch (profile.goal) {
      case Goal.gain_muscle:
        pRatio = 0.30;
        cRatio = 0.45;
        fRatio = 0.25;
        break;
      case Goal.lose_weight:
        pRatio = 0.40;
        cRatio = 0.30;
        fRatio = 0.30;
        break;
      case Goal.maintain_weight:
      default:
        pRatio = 0.25;
        cRatio = 0.50;
        fRatio = 0.25;
        break;
    }

    return {
      'protein': ((tdee * pRatio) / 4).round(),
      'carbs': ((tdee * cRatio) / 4).round(),
      'fat': ((tdee * fRatio) / 9).round(),
    };
  }
}
