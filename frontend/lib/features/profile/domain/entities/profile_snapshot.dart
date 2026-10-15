import 'profile_entity.dart';

/// Unified domain entity aggregating athlete health profile,
/// calculated targets, and identity fields from a single response.
class ProfileSnapshot {
  final String? userId;
  final ProfileEntity profile;
  final int targetCalories;
  final int targetProtein;
  final int targetCarbs;
  final int targetFat;
  final int targetBurned;
  final int waterTargetMl;
  final String? email;
  final String? fullName;
  final String? avatar;
  final bool isFromCache;

  const ProfileSnapshot({
    this.userId,
    required this.profile,
    this.targetCalories = 0,
    this.targetProtein = 0,
    this.targetCarbs = 0,
    this.targetFat = 0,
    this.targetBurned = 300,
    this.waterTargetMl = 2000,
    this.email,
    this.fullName,
    this.avatar,
    this.isFromCache = false,
  });

  factory ProfileSnapshot.empty({String? userId}) =>
      ProfileSnapshot(userId: userId, profile: ProfileEntity.empty(userId: userId));

  ProfileSnapshot copyWith({
    String? userId,
    ProfileEntity? profile,
    int? targetCalories,
    int? targetProtein,
    int? targetCarbs,
    int? targetFat,
    int? targetBurned,
    int? waterTargetMl,
    String? email,
    String? fullName,
    String? avatar,
    bool? isFromCache,
  }) {
    return ProfileSnapshot(
      userId: userId ?? this.userId,
      profile: profile ?? this.profile,
      targetCalories: targetCalories ?? this.targetCalories,
      targetProtein: targetProtein ?? this.targetProtein,
      targetCarbs: targetCarbs ?? this.targetCarbs,
      targetFat: targetFat ?? this.targetFat,
      targetBurned: targetBurned ?? this.targetBurned,
      waterTargetMl: waterTargetMl ?? this.waterTargetMl,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatar: avatar ?? this.avatar,
      isFromCache: isFromCache ?? this.isFromCache,
    );
  }
}
