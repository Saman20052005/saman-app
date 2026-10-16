import 'onboarding_activity_choice.dart';
import 'profile_entity.dart';
import 'profile_snapshot.dart';

/// Six raw biometric values of the confirmed backend snapshot a draft was
/// created from. Only RAW getters are used, never the fallback getters.
class OnboardingDraftBase {
  final int? age;
  final double? height;
  final double? weight;
  final Gender? gender;
  final ActivityLevel? activityLevel;
  final Goal? goal;

  const OnboardingDraftBase({
    this.age,
    this.height,
    this.weight,
    this.gender,
    this.activityLevel,
    this.goal,
  });

  factory OnboardingDraftBase.fromProfile(ProfileEntity profile) {
    return OnboardingDraftBase(
      age: profile.age,
      height: profile.height,
      weight: profile.weight,
      gender: profile.rawGender,
      activityLevel: profile.rawActivityLevel,
      goal: profile.rawGoal,
    );
  }

  /// True when [profile] still holds exactly the values this base captured.
  bool matches(ProfileEntity profile) {
    return age == profile.age &&
        height == profile.height &&
        weight == profile.weight &&
        gender == profile.rawGender &&
        activityLevel == profile.rawActivityLevel &&
        goal == profile.rawGoal;
  }

  Map<String, dynamic> toJson() => {
        'age': age,
        'height': height,
        'weight': weight,
        'gender': gender?.name,
        'activity_level': activityLevel?.name,
        'goal': goal?.name,
      };

  /// Strict parse; throws [FormatException] on any malformed value.
  factory OnboardingDraftBase.parse(Map<String, dynamic> json) {
    return OnboardingDraftBase(
      age: OnboardingDraft.readInt(json, 'age'),
      height: OnboardingDraft.readDouble(json, 'height'),
      weight: OnboardingDraft.readDouble(json, 'weight'),
      gender: OnboardingDraft.readEnum(json, 'gender', Gender.values),
      activityLevel: OnboardingDraft.readEnum(
          json, 'activity_level', ActivityLevel.values),
      goal: OnboardingDraft.readEnum(json, 'goal', Goal.values),
    );
  }
}

/// Represents a local uncommitted draft for onboarding profile creation.
///
/// Holds the biometric input values, resume step, schema version, the 5-tier
/// [activityChoice], raw input text for uncommitted decimals, and the [base]
/// values of the confirmed snapshot the draft was created from.
/// Encapsulates owner validation, compatibility checks, and serialization.
///
/// NOTE:
/// - Draft data NEVER determines completeness by itself.
/// - Draft data is NEVER sent directly to the backend.
/// - Does not provide hardcoded default samples or automatic completion values.
/// - A draft is only auto-resumable against a confirmed snapshot of the same
///   owner that is still incomplete and still equals [base].
class OnboardingDraft {
  static const int supportedSchemaVersion = 1;
  static const int minStep = 1;
  static const int maxStep = 5;

  final String userId;
  final int? age;
  final double? height;
  final double? weight;
  final String? rawHeightText;
  final String? rawWeightText;
  final Gender? gender;
  final ActivityLevel? activityLevel;
  final OnboardingActivityChoice? activityChoice;
  final Goal? goal;
  final int step;
  final int schemaVersion;
  final OnboardingDraftBase? base;

  const OnboardingDraft({
    required this.userId,
    this.age,
    this.height,
    this.weight,
    this.rawHeightText,
    this.rawWeightText,
    this.gender,
    this.activityLevel,
    this.activityChoice,
    this.goal,
    this.step = 1,
    this.schemaVersion = supportedSchemaVersion,
    this.base,
  });

  /// Creates a draft bound to a confirmed [snapshot], capturing its six raw
  /// values as [base]. The snapshot is only read, never mutated.
  factory OnboardingDraft.forSnapshot(
    ProfileSnapshot snapshot, {
    int? age,
    double? height,
    double? weight,
    String? rawHeightText,
    String? rawWeightText,
    Gender? gender,
    ActivityLevel? activityLevel,
    OnboardingActivityChoice? activityChoice,
    Goal? goal,
    int step = minStep,
  }) {
    final owner = snapshot.userId;
    if (snapshot.isFromCache || owner == null || owner.isEmpty) {
      throw ArgumentError(
          'A draft can only be based on a network-confirmed snapshot');
    }

    final resolvedChoice = activityChoice ??
        OnboardingActivityChoice.fromLegacy(
            activityLevel ?? snapshot.profile.rawActivityLevel);

    return OnboardingDraft(
      userId: owner,
      age: age,
      height: height,
      weight: weight,
      rawHeightText: rawHeightText,
      rawWeightText: rawWeightText,
      gender: gender,
      activityLevel: activityLevel ?? snapshot.profile.rawActivityLevel,
      activityChoice: resolvedChoice,
      goal: goal,
      step: step,
      base: OnboardingDraftBase.fromProfile(snapshot.profile),
    );
  }

  /// Schema and resume step are within what this build can interpret.
  bool get isSupported =>
      schemaVersion == supportedSchemaVersion &&
      step >= minStep &&
      step <= maxStep;

  /// Evaluates whether this draft can be auto-restored against [snapshot].
  ///
  /// False for: unsupported schema/step, owner mismatch, unconfirmed (cache)
  /// snapshot, backend-complete profile, legacy draft without [base], and
  /// drafts whose [base] no longer equals the snapshot's raw six fields.
  bool isCompatibleWith(ProfileSnapshot snapshot) {
    if (!isSupported) return false;
    if (userId.isEmpty || snapshot.userId != userId) return false;
    if (snapshot.isFromCache) return false;
    // Backend-complete users MUST ignore/skip stale onboarding drafts.
    if (snapshot.profile.isComplete) return false;
    final capturedBase = base;
    if (capturedBase == null) return false;
    return capturedBase.matches(snapshot.profile);
  }

  OnboardingDraft copyWith({
    String? userId,
    int? age,
    bool clearAge = false,
    double? height,
    bool clearHeight = false,
    double? weight,
    bool clearWeight = false,
    String? rawHeightText,
    bool clearRawHeightText = false,
    String? rawWeightText,
    bool clearRawWeightText = false,
    Gender? gender,
    bool clearGender = false,
    ActivityLevel? activityLevel,
    bool clearActivityLevel = false,
    OnboardingActivityChoice? activityChoice,
    bool clearActivityChoice = false,
    Goal? goal,
    bool clearGoal = false,
    int? step,
    int? schemaVersion,
    OnboardingDraftBase? base,
  }) {
    return OnboardingDraft(
      userId: userId ?? this.userId,
      age: clearAge ? null : (age ?? this.age),
      height: clearHeight ? null : (height ?? this.height),
      weight: clearWeight ? null : (weight ?? this.weight),
      rawHeightText: clearRawHeightText
          ? null
          : (rawHeightText ?? this.rawHeightText),
      rawWeightText: clearRawWeightText
          ? null
          : (rawWeightText ?? this.rawWeightText),
      gender: clearGender ? null : (gender ?? this.gender),
      activityLevel: clearActivityLevel
          ? null
          : (activityLevel ?? this.activityLevel),
      activityChoice: clearActivityChoice
          ? null
          : (activityChoice ?? this.activityChoice),
      goal: clearGoal ? null : (goal ?? this.goal),
      step: step ?? this.step,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      base: base ?? this.base,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'age': age,
      'height': height,
      'weight': weight,
      'raw_height_text': rawHeightText,
      'raw_weight_text': rawWeightText,
      'gender': gender?.name,
      'activity_level': activityLevel?.name,
      'activity_choice': activityChoice?.name,
      'goal': goal?.name,
      'step': step,
      'schema_version': schemaVersion,
      'base': base?.toJson(),
    };
  }

  /// Strict parse. Returns null (never throws, never guesses) when the JSON is
  /// malformed, has an unsupported schema, or an out-of-range step.
  static OnboardingDraft? tryParse(Map<String, dynamic> json) {
    try {
      final rawUser = json['user_id'];
      if (rawUser is! String || rawUser.trim().isEmpty) {
        throw const FormatException('draft user_id');
      }
      final schema = json['schema_version'];
      if (schema is! int || schema != supportedSchemaVersion) {
        throw const FormatException('draft schema_version');
      }
      final step = json['step'];
      if (step is! int || step < minStep || step > maxStep) {
        throw const FormatException('draft step');
      }
      final rawBase = json['base'];
      OnboardingDraftBase? base;
      if (rawBase != null) {
        if (rawBase is! Map<String, dynamic>) {
          throw const FormatException('draft base');
        }
        base = OnboardingDraftBase.parse(rawBase);
      }

      final legacyLevel =
          readEnum(json, 'activity_level', ActivityLevel.values);
      final choice =
          readEnum(json, 'activity_choice', OnboardingActivityChoice.values) ??
              OnboardingActivityChoice.fromLegacy(legacyLevel);

      return OnboardingDraft(
        userId: rawUser,
        age: readInt(json, 'age'),
        height: readDouble(json, 'height'),
        weight: readDouble(json, 'weight'),
        rawHeightText: readString(json, 'raw_height_text'),
        rawWeightText: readString(json, 'raw_weight_text'),
        gender: readEnum(json, 'gender', Gender.values),
        activityLevel: legacyLevel,
        activityChoice: choice,
        goal: readEnum(json, 'goal', Goal.values),
        step: step,
        schemaVersion: schema,
        base: base,
      );
    } on FormatException {
      return null;
    }
  }

  // --- Strict field readers (null allowed, wrong type/unknown value throws) ---

  static int? readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    throw FormatException('draft field $key');
  }

  static double? readDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw FormatException('draft field $key');
  }

  static String? readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('draft field $key');
  }

  static T? readEnum<T extends Enum>(
      Map<String, dynamic> json, String key, List<T> values) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) {
      for (final candidate in values) {
        if (candidate.name == value) return candidate;
      }
    }
    throw FormatException('draft field $key');
  }
}
