import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _PreviewProfileRepository implements ProfileRepository {
  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<void> clearLocalProfile() async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => null;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({
    bool cacheOnSuccess = false,
  }) async =>
      null;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}
}

class _PreviewProfileNotifier extends ProfileNotifier {
  _PreviewProfileNotifier(super.repository) {
    state = ProfileState(
      status: ProfileStatus.ready,
      profile: const ProfileEntity(
        age: 24,
        height: 175,
        weight: 70,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      ),
      targetCalories: 2450,
      targetProtein: 160,
    );
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

void main() {
  final repository = _PreviewProfileRepository();

  runApp(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        profileProvider.overrideWith(
          (ref) => _PreviewProfileNotifier(repository),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SamanTheme.dark(),
        home: const ProfileScreen(),
      ),
    ),
  );
}
