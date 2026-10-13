import '../models/profile_model.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/profile_snapshot.dart';

class ProfileSnapshotModel extends ProfileSnapshot {
  const ProfileSnapshotModel({
    required super.profile,
    super.targetCalories = 0,
    super.targetProtein = 0,
    super.targetCarbs = 0,
    super.targetFat = 0,
    super.targetBurned = 300,
    super.waterTargetMl = 2000,
    super.email,
    super.fullName,
    super.avatar,
    super.isFromCache = false,
  });

  factory ProfileSnapshotModel.fromSnapshot(ProfileSnapshot snapshot) {
    if (snapshot is ProfileSnapshotModel) return snapshot;
    return ProfileSnapshotModel(
      profile: snapshot.profile,
      targetCalories: snapshot.targetCalories,
      targetProtein: snapshot.targetProtein,
      targetCarbs: snapshot.targetCarbs,
      targetFat: snapshot.targetFat,
      targetBurned: snapshot.targetBurned,
      waterTargetMl: snapshot.waterTargetMl,
      email: snapshot.email,
      fullName: snapshot.fullName,
      avatar: snapshot.avatar,
      isFromCache: snapshot.isFromCache,
    );
  }

  factory ProfileSnapshotModel.fromJson(
    Map<String, dynamic> json, {
    bool isFromCache = false,
  }) {
    ProfileEntity profileEntity = ProfileEntity.empty();

    // 1. Parse Profile
    if (json['profile'] is Map<String, dynamic>) {
      profileEntity =
          ProfileModel.fromJson(json['profile'] as Map<String, dynamic>);
    } else if (json.containsKey('height') ||
        json.containsKey('weight') ||
        json.containsKey('age')) {
      // Legacy flat profile support
      profileEntity = ProfileModel.fromJson(json);
    }

    // 2. Parse Health Stats
    final healthStats = json['health_stats'] as Map<String, dynamic>? ?? {};
    final calories = _toInt(
      healthStats['daily_calories'] ??
          healthStats['target_calories'] ??
          healthStats['daily_calorie_needs'] ??
          json['targetCalories'],
    );
    final protein =
        _toInt(healthStats['target_protein'] ?? json['targetProtein']);
    final carbs = _toInt(healthStats['target_carbs'] ?? json['targetCarbs']);
    final fat = _toInt(healthStats['target_fat'] ?? json['targetFat']);
    final water =
        _toInt(healthStats['water_target_ml'] ?? json['waterTargetMl']);
    final burned = _toInt(healthStats['target_burned'] ?? json['targetBurned']);

    return ProfileSnapshotModel(
      profile: profileEntity,
      targetCalories: calories,
      targetProtein: protein,
      targetCarbs: carbs,
      targetFat: fat,
      targetBurned: burned > 0 ? burned : 300,
      waterTargetMl: water > 0 ? water : 2000,
      email: json['email'] as String?,
      fullName: json['full_name'] as String? ?? json['fullName'] as String?,
      avatar: json['avatar'] as String?,
      isFromCache: isFromCache,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': (profile is ProfileModel)
          ? (profile as ProfileModel).toJson()
          : ProfileModel.fromEntity(profile).toJson(),
      'health_stats': {
        'daily_calories': targetCalories,
        'target_protein': targetProtein,
        'target_carbs': targetCarbs,
        'target_fat': targetFat,
        'water_target_ml': waterTargetMl,
        'target_burned': targetBurned,
      },
      'email': email,
      'full_name': fullName,
      'avatar': avatar,
    };
  }

  static int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.round();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}
