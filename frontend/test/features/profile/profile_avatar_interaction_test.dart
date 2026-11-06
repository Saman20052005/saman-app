import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/domain/repositories/avatar_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/widgets/saman_avatar.dart';

class _MockProfileRepository implements ProfileRepository {
  ProfileSnapshot? snapshot;
  _MockProfileRepository([this.snapshot]);

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({bool cacheOnSuccess = false}) async =>
      snapshot;

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshot?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {
    snapshot = ProfileSnapshot(profile: profile);
  }

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<void> clearLocalProfile({String? userId}) async {
    snapshot = null;
  }

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

class _MockAvatarRepository implements AvatarRepository {
  Map<String, dynamic> uploadResult = {
    'avatar': 'https://res.cloudinary.com/saman/new_custom_avatar.jpg',
    'avatar_source': 'custom',
    'can_use_google_avatar': true,
  };
  Map<String, dynamic> googleResult = {
    'avatar': 'https://lh3.googleusercontent.com/google_photo.jpg',
    'avatar_source': 'google',
    'can_use_google_avatar': true,
  };

  bool throwOnUpload = false;
  int uploadCallCount = 0;
  int googleCallCount = 0;
  Completer<void>? uploadCompleter;

  @override
  Future<Map<String, dynamic>> uploadAvatar(XFile file, {bool Function()? isSessionCurrent}) async {
    uploadCallCount++;
    if (uploadCompleter != null) {
      await uploadCompleter!.future;
    }
    if (throwOnUpload) {
      throw Exception('Upload network error');
    }
    return uploadResult;
  }

  @override
  Future<Map<String, dynamic>> useGoogleAvatar({bool Function()? isSessionCurrent}) async {
    googleCallCount++;
    return googleResult;
  }
}

class _CustomProfileNotifier extends ProfileNotifier {
  _CustomProfileNotifier(
    super.repository, {
    required super.avatarRepository,
    required ProfileState initialState,
  }) {
    state = initialState;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({
    required ProfileSnapshot snapshot,
    required _MockAvatarRepository avatarRepo,
  }) {
    final mockRepo = _MockProfileRepository(snapshot);
    final initialState = ProfileState(
      status: ProfileStatus.ready,
      profile: snapshot.profile,
      snapshot: snapshot,
      confirmedUserId: snapshot.userId,
      isNetworkConfirmed: true,
    );

    return ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(mockRepo),
        avatarRepositoryProvider.overrideWithValue(avatarRepo),
        profileProvider.overrideWith(
          (ref) => _CustomProfileNotifier(
            mockRepo,
            avatarRepository: avatarRepo,
            initialState: initialState,
          ),
        ),
      ],
      child: const MaterialApp(
        home: ProfileScreen(),
      ),
    );
  }

  group('ProfileScreen Avatar Interaction Tests', () {
    testWidgets('Displays SamanAvatar and camera badge on ProfileScreen',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final semantics = tester.ensureSemantics();

      const snapshot = ProfileSnapshot(
        userId: 'u1',
        fullName: 'Athlete Saman',
        profile: ProfileEntity(
          age: 26,
          height: 178,
          weight: 72,
          gender: Gender.male,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        avatar: null,
        canUseGoogleAvatar: false,
      );
      final avatarRepo = _MockAvatarRepository();

      await tester.pumpWidget(buildTestApp(snapshot: snapshot, avatarRepo: avatarRepo));
      await tester.pumpAndSettle();

      expect(find.byType(SamanAvatar), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_tap_target')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Đổi ảnh đại diện'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets(
        'Tapping avatar opens bottom sheet with gallery and cancel, hides Google when canUseGoogle is false',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const snapshot = ProfileSnapshot(
        userId: 'u1',
        fullName: 'Athlete Saman',
        profile: ProfileEntity(
          age: 26,
          height: 178,
          weight: 72,
          gender: Gender.male,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        avatar: null,
        canUseGoogleAvatar: false,
      );
      final avatarRepo = _MockAvatarRepository();

      await tester.pumpWidget(buildTestApp(snapshot: snapshot, avatarRepo: avatarRepo));
      await tester.pumpAndSettle();

      // Tap avatar
      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();

      expect(find.text('Ảnh đại diện'), findsOneWidget);
      expect(find.byKey(const Key('avatar_option_gallery')), findsOneWidget);
      expect(find.byKey(const Key('avatar_option_cancel')), findsOneWidget);
      expect(find.byKey(const Key('avatar_option_google')), findsNothing);

      // Tap Cancel dismisses cleanly
      await tester.tap(find.byKey(const Key('avatar_option_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Ảnh đại diện'), findsNothing);
    });

    testWidgets(
        'Shows Google option when canUseGoogleAvatar is true, tapping it invokes useGoogleAvatar',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const snapshot = ProfileSnapshot(
        userId: 'u1',
        fullName: 'Athlete Saman',
        profile: ProfileEntity(
          age: 26,
          height: 178,
          weight: 72,
          gender: Gender.male,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        avatar: 'https://res.cloudinary.com/saman/custom.jpg',
        avatarSource: 'custom',
        canUseGoogleAvatar: true,
      );
      final avatarRepo = _MockAvatarRepository();

      await tester.pumpWidget(buildTestApp(snapshot: snapshot, avatarRepo: avatarRepo));
      await tester.pumpAndSettle();

      // Tap avatar
      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('avatar_option_google')), findsOneWidget);

      // Tap Google option
      await tester.tap(find.byKey(const Key('avatar_option_google')));
      await tester.pumpAndSettle();

      expect(avatarRepo.googleCallCount, 1);
      expect(find.text('Đã chuyển sang ảnh đại diện Google'), findsOneWidget);
    });
  });

  group('ProfileNotifier Avatar State & Session Isolation Tests', () {
    test('uploadAvatar updates snapshot avatar and avatarSource', () async {
      const snapshot = ProfileSnapshot(
        userId: 'u100',
        profile: ProfileEntity(),
        avatar: null,
        avatarSource: 'none',
      );
      final mockRepo = _MockProfileRepository(snapshot);
      final avatarRepo = _MockAvatarRepository();
      final notifier = _CustomProfileNotifier(
        mockRepo,
        avatarRepository: avatarRepo,
        initialState: ProfileState(
          status: ProfileStatus.ready,
          profile: snapshot.profile,
          snapshot: snapshot,
          confirmedUserId: 'u100',
        ),
      );

      final dummyFile = XFile('test_path.jpg', name: 'photo.jpg');
      final success = await notifier.uploadAvatar(dummyFile);
      expect(success, true);
      expect(notifier.state.avatar, 'https://res.cloudinary.com/saman/new_custom_avatar.jpg');
      expect(notifier.state.avatarSource, 'custom');
      expect(mockRepo.snapshot?.avatar, 'https://res.cloudinary.com/saman/new_custom_avatar.jpg');
    });

    test('Late avatar response from previous session is discarded on logout/session reset', () async {
      const snapshot = ProfileSnapshot(
        userId: 'u100',
        profile: ProfileEntity(),
      );
      final mockRepo = _MockProfileRepository(snapshot);
      final avatarRepo = _MockAvatarRepository();
      final completer = Completer<void>();
      avatarRepo.uploadCompleter = completer;

      final notifier = _CustomProfileNotifier(
        mockRepo,
        avatarRepository: avatarRepo,
        initialState: ProfileState(
          status: ProfileStatus.ready,
          profile: snapshot.profile,
          snapshot: snapshot,
          confirmedUserId: 'u100',
        ),
      );

      // Start upload in-flight
      final dummyFile = XFile('test_path.jpg', name: 'photo.jpg');
      final uploadFuture = notifier.uploadAvatar(dummyFile);

      // User logs out while upload is in flight!
      notifier.resetSession();

      // Complete the network call
      completer.complete();
      final success = await uploadFuture;

      // Late response MUST be discarded!
      expect(success, false);
      expect(notifier.state.avatar, isNull);
    });
  });
}
