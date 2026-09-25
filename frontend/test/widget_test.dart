// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/main.dart';
import 'package:health_ai_app/providers/profile_provider.dart';

class _TestProfileRepository implements ProfileRepository {
  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

  @override
  Future<ProfileEntity?> fetchProfile() async => ProfileEntity.empty();

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
      {bool cacheOnSuccess = false}) async =>
      const ProfileSnapshot(profile: ProfileEntity());

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<void> clearLocalProfile() async {}
}

class TestProfileNotifier extends ProfileNotifier {
  TestProfileNotifier() : super(_TestProfileRepository());

  @override
  Future<void> loadProfile() async {}
}

void main() {
  testWidgets('app builds with provider scope', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPrefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileProvider.overrideWith(
            (ref) => TestProfileNotifier(),
          ),
        ],
        child: const MyApp(enableSplashAnimations: false),
      ),
    );

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
