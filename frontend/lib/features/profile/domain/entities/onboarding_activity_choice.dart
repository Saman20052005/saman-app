import 'profile_entity.dart';

/// Five distinct activity choices for the onboarding UI (CP3).
///
/// Distinct from the legacy 3-tier [ActivityLevel] enum (low, medium, high).
enum OnboardingActivityChoice {
  sedentary,
  light,
  moderate,
  active,
  // ignore: constant_identifier_names
  very_active;

  String get title {
    switch (this) {
      case OnboardingActivityChoice.sedentary:
        return 'Mostly sitting';
      case OnboardingActivityChoice.light:
        return 'Lightly active';
      case OnboardingActivityChoice.moderate:
        return 'Moderately active';
      case OnboardingActivityChoice.active:
        return 'Very active';
      case OnboardingActivityChoice.very_active:
        return 'Extremely active';
    }
  }

  String get subtitle {
    switch (this) {
      case OnboardingActivityChoice.sedentary:
        return 'Most of my day is seated, with little exercise.';
      case OnboardingActivityChoice.light:
        return 'Some walking and occasional light exercise.';
      case OnboardingActivityChoice.moderate:
        return 'Regular exercise and some movement during the day.';
      case OnboardingActivityChoice.active:
        return 'Frequent exercise and plenty of daily movement.';
      case OnboardingActivityChoice.very_active:
        return 'Demanding physical work or intensive daily training.';
    }
  }

  /// Canonical API string representation: sedentary, light, moderate, active, very_active.
  String get apiValue => name;

  /// Legacy 3-tier ActivityLevel projection for external legacy consumers.
  ActivityLevel toLegacy() {
    switch (this) {
      case OnboardingActivityChoice.sedentary:
      case OnboardingActivityChoice.light:
        return ActivityLevel.low;
      case OnboardingActivityChoice.moderate:
        return ActivityLevel.medium;
      case OnboardingActivityChoice.active:
      case OnboardingActivityChoice.very_active:
        return ActivityLevel.high;
    }
  }

  /// Parses canonical 5-tier string (or legacy string) into choice without loss.
  static OnboardingActivityChoice? fromApi(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'sedentary':
        return OnboardingActivityChoice.sedentary;
      case 'light':
        return OnboardingActivityChoice.light;
      case 'moderate':
        return OnboardingActivityChoice.moderate;
      case 'active':
        return OnboardingActivityChoice.active;
      case 'very_active':
        return OnboardingActivityChoice.very_active;
      // Legacy compatibility mappings
      case 'low':
        return OnboardingActivityChoice.sedentary;
      case 'medium':
        return OnboardingActivityChoice.moderate;
      case 'high':
        return OnboardingActivityChoice.active;
      default:
        return null;
    }
  }

  /// Maps legacy 3-tier ActivityLevel to 5-tier choice for prefill.
  /// low -> sedentary, medium -> moderate, high -> active.
  static OnboardingActivityChoice? fromLegacy(ActivityLevel? level) {
    if (level == null) return null;
    switch (level) {
      case ActivityLevel.low:
        return OnboardingActivityChoice.sedentary;
      case ActivityLevel.medium:
        return OnboardingActivityChoice.moderate;
      case ActivityLevel.high:
        return OnboardingActivityChoice.active;
    }
  }
}
