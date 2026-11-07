import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/domain/repositories/avatar_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  ProfileSnapshot? snapshot;
  _FakeProfileRepository([this.snapshot]);

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

class _FakeAvatarRepository implements AvatarRepository {
  Map<String, dynamic> uploadResult = {
    'avatar': 'https://res.cloudinary.com/saman/custom_avatar.jpg',
    'avatar_source': 'custom',
    'can_use_google_avatar': true,
  };
  Map<String, dynamic> googleResult = {
    'avatar': 'https://lh3.googleusercontent.com/google_photo.jpg',
    'avatar_source': 'google',
    'can_use_google_avatar': true,
  };

  @override
  Future<Map<String, dynamic>> uploadAvatar(XFile file, {bool Function()? isSessionCurrent}) async =>
      uploadResult;

  @override
  Future<Map<String, dynamic>> useGoogleAvatar({bool Function()? isSessionCurrent}) async =>
      googleResult;
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier(
    super.repository, {
    required super.avatarRepository,
    required ProfileState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

Widget _buildLocalizedProfileApp({
  required Widget child,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(languageProvider);
        return MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        );
      },
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'vi',
      'language_code': 'vi',
      'theme_mode': 'dark',
    });
  });

  group('Checkpoint LOC-03: AppTranslations Profile & Settings Dictionary Parity', () {
    test('en and vi translation maps contain identical keys for Profile, Avatar, Validation, Settings', () {
      final requiredProfileKeys = [
        // Avatar Dialogs
        'avatar_dialog_title',
        'choose_gallery',
        'use_google_photo',
        'avatar_preview_title',
        'avatar_update_success',
        'avatar_crop_hint',
        'save_avatar',

        // Profile & Health Labels
        'profile_title',
        'personal_info',
        'health_metrics',
        'age_label',
        'height_label',
        'weight_label',
        'activity_level_label',
        'fitness_goal_label',
        'edit_profile',
        'save_changes',
        'your_saman_profile',
        'your_goal',
        'your_details',
        'activity_level_heading',
        'account_heading',
        'profile_incomplete_notice',
        'journey_rewards_heading',
        'my_journey_title',
        'wallet_rewards_title',
        'manage_membership',
        'app_settings',
        'logout',
        'logout_confirm_title',
        'logout_dialog_saman_msg',
        'error_load_profile',
        'try_again',

        // Validation Errors
        'val_age_range',
        'val_height_range',
        'val_weight_range',

        // Settings & Preferences
        'settings_title',
        'theme_setting',
        'theme_light',
        'theme_dark',
        'theme_system',
      ];

      for (final key in requiredProfileKeys) {
        final enVal = AppTranslations.text(key, const Locale('en'));
        final viVal = AppTranslations.text(key, const Locale('vi'));

        expect(enVal, isNotEmpty, reason: 'Key "$key" should have non-empty EN translation');
        expect(viVal, isNotEmpty, reason: 'Key "$key" should have non-empty VI translation');
        expect(enVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for EN');
        expect(viVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for VI');
      }
    });

    test('Profile specific translations evaluate to expected strings in VI and EN', () {
      expect(AppTranslations.text('profile_title', const Locale('vi')), 'Hồ sơ');
      expect(AppTranslations.text('profile_title', const Locale('en')), 'Profile');

      expect(AppTranslations.text('avatar_dialog_title', const Locale('vi')), 'Ảnh đại diện');
      expect(AppTranslations.text('avatar_dialog_title', const Locale('en')), 'Profile Photo');

      expect(AppTranslations.text('choose_gallery', const Locale('vi')), 'Chọn từ thư viện');
      expect(AppTranslations.text('choose_gallery', const Locale('en')), 'Choose from gallery');

      expect(AppTranslations.text('use_google_photo', const Locale('vi')), 'Dùng ảnh Google');
      expect(AppTranslations.text('use_google_photo', const Locale('en')), 'Use Google photo');

      expect(AppTranslations.text('avatar_preview_title', const Locale('vi')), 'Xem trước ảnh đại diện');
      expect(AppTranslations.text('avatar_preview_title', const Locale('en')), 'Avatar Preview');

      expect(AppTranslations.text('avatar_update_success', const Locale('vi')), 'Cập nhật ảnh đại diện thành công!');
      expect(AppTranslations.text('avatar_update_success', const Locale('en')), 'Avatar updated successfully!');

      expect(AppTranslations.text('age_label', const Locale('vi')), 'Tuổi');
      expect(AppTranslations.text('age_label', const Locale('en')), 'Age');

      expect(AppTranslations.text('height_label', const Locale('vi')), 'Chiều cao');
      expect(AppTranslations.text('height_label', const Locale('en')), 'Height');

      expect(AppTranslations.text('weight_label', const Locale('vi')), 'Cân nặng');
      expect(AppTranslations.text('weight_label', const Locale('en')), 'Weight');

      expect(AppTranslations.text('your_goal', const Locale('vi')), 'MỤC TIÊU CỦA BẠN');
      expect(AppTranslations.text('your_goal', const Locale('en')), 'YOUR GOAL');

      expect(AppTranslations.text('your_details', const Locale('vi')), 'THÔNG TIN CỦA BẠN');
      expect(AppTranslations.text('your_details', const Locale('en')), 'YOUR DETAILS');

      expect(AppTranslations.text('activity_level_heading', const Locale('vi')), 'MỨC ĐỘ VẬN ĐỘNG');
      expect(AppTranslations.text('activity_level_heading', const Locale('en')), 'ACTIVITY LEVEL');

      expect(AppTranslations.text('account_heading', const Locale('vi')), 'TÀI KHOẢN');
      expect(AppTranslations.text('account_heading', const Locale('en')), 'ACCOUNT');

      expect(AppTranslations.text('logout', const Locale('vi')), 'Đăng xuất');
      expect(AppTranslations.text('logout', const Locale('en')), 'Log out');

      expect(AppTranslations.text('val_age_range', const Locale('vi')), 'Tuổi phải từ 10 đến 120');
      expect(AppTranslations.text('val_age_range', const Locale('en')), 'Age must be between 10 and 120');

      expect(AppTranslations.text('val_height_range', const Locale('vi')), 'Chiều cao phải từ 50cm đến 250cm');
      expect(AppTranslations.text('val_height_range', const Locale('en')), 'Height must be between 50cm and 250cm');

      expect(AppTranslations.text('val_weight_range', const Locale('vi')), 'Cân nặng phải từ 20kg đến 300kg');
      expect(AppTranslations.text('val_weight_range', const Locale('en')), 'Weight must be between 20kg and 300kg');

      expect(AppTranslations.text('settings_title', const Locale('vi')), 'Cài đặt');
      expect(AppTranslations.text('settings_title', const Locale('en')), 'Settings');

      expect(AppTranslations.text('theme_setting', const Locale('vi')), 'Giao diện');
      expect(AppTranslations.text('theme_setting', const Locale('en')), 'Theme');
    });
  });

  group('Checkpoint LOC-03: ProfileScreen Reactive Localization Switch VI <-> EN <-> VI', () {
    testWidgets('Toggles ProfileScreen headers, details, cards, and logout between VI and EN reactively',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testSnapshot = ProfileSnapshot(
        userId: 'loc_user_1',
        fullName: 'Minh Athlete',
        profile: ProfileEntity(
          age: 28,
          height: 175,
          weight: 70,
          gender: Gender.male,
          activityLevel: ActivityLevel.high,
          goal: Goal.gain_muscle,
        ),
        avatar: null,
        canUseGoogleAvatar: true,
      );

      final fakeRepo = _FakeProfileRepository(testSnapshot);
      final fakeAvatarRepo = _FakeAvatarRepository();
      final initialState = ProfileState(
        status: ProfileStatus.ready,
        profile: testSnapshot.profile,
        snapshot: testSnapshot,
        confirmedUserId: testSnapshot.userId,
        isNetworkConfirmed: true,
      );

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          avatarRepositoryProvider.overrideWithValue(fakeAvatarRepo),
          profileProvider.overrideWith(
            (ref) => _TestProfileNotifier(
              fakeRepo,
              avatarRepository: fakeAvatarRepo,
              initialState: initialState,
            ),
          ),
          languageProvider.overrideWith((ref) => LanguageNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedProfileApp(
          container: container,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Vietnamese Initial State
      expect(find.text('Hồ sơ'), findsOneWidget);
      expect(find.text('Hồ sơ Saman của bạn'), findsOneWidget);
      expect(find.text('MỤC TIÊU CỦA BẠN'), findsOneWidget);
      expect(find.text('THÔNG TIN CỦA BẠN'), findsOneWidget);
      expect(find.text('MỨC ĐỘ VẬN ĐỘNG'), findsOneWidget);
      expect(find.text('Tuổi'), findsOneWidget);
      expect(find.text('Giới tính'), findsOneWidget);
      expect(find.text('Chiều cao'), findsOneWidget);
      expect(find.text('Cân nặng'), findsOneWidget);
      expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);
      expect(find.text('HÀNH TRÌNH & ĐIỂM THƯỞNG'), findsOneWidget);
      expect(find.text('Hành trình Saman'), findsOneWidget);
      expect(find.text('Điểm thưởng & Đổi lượt AI'), findsOneWidget);
      expect(find.text('TÀI KHOẢN'), findsOneWidget);
      expect(find.text('Quản lý gói hội viên'), findsOneWidget);
      expect(find.text('Cài đặt ứng dụng'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);

      // 2. Switch Language to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // 3. Verify English State
      expect(find.text('Hồ sơ'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Your Saman profile'), findsOneWidget);
      expect(find.text('YOUR GOAL'), findsOneWidget);
      expect(find.text('YOUR DETAILS'), findsOneWidget);
      expect(find.text('ACTIVITY LEVEL'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('JOURNEY & REWARDS'), findsOneWidget);
      expect(find.text('Saman Journey'), findsOneWidget);
      expect(find.text('Rewards & AI Credits'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Manage membership'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      // 4. Switch Back to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      // 5. Verify Vietnamese State Restored
      expect(find.text('Hồ sơ'), findsOneWidget);
      expect(find.text('Hồ sơ Saman của bạn'), findsOneWidget);
      expect(find.text('MỤC TIÊU CỦA BẠN'), findsOneWidget);
      expect(find.text('THÔNG TIN CỦA BẠN'), findsOneWidget);
      expect(find.text('MỨC ĐỘ VẬN ĐỘNG'), findsOneWidget);
      expect(find.text('Tuổi'), findsOneWidget);
      expect(find.text('Giới tính'), findsOneWidget);
      expect(find.text('Chiều cao'), findsOneWidget);
      expect(find.text('Cân nặng'), findsOneWidget);
      expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);
      expect(find.text('HÀNH TRÌNH & ĐIỂM THƯỞNG'), findsOneWidget);
      expect(find.text('TÀI KHOẢN'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
    });

    testWidgets('Avatar Options BottomSheet reflects language switch reactively',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testSnapshot = ProfileSnapshot(
        userId: 'loc_user_avatar',
        fullName: 'Athlete Avatar',
        profile: ProfileEntity(age: 25, height: 170, weight: 65),
        avatar: null,
        canUseGoogleAvatar: true,
      );

      final fakeRepo = _FakeProfileRepository(testSnapshot);
      final fakeAvatarRepo = _FakeAvatarRepository();
      final initialState = ProfileState(
        status: ProfileStatus.ready,
        profile: testSnapshot.profile,
        snapshot: testSnapshot,
        confirmedUserId: testSnapshot.userId,
        isNetworkConfirmed: true,
      );

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          avatarRepositoryProvider.overrideWithValue(fakeAvatarRepo),
          profileProvider.overrideWith(
            (ref) => _TestProfileNotifier(
              fakeRepo,
              avatarRepository: fakeAvatarRepo,
              initialState: initialState,
            ),
          ),
          languageProvider.overrideWith((ref) => LanguageNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedProfileApp(
          container: container,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Open Avatar Sheet in Vietnamese
      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();

      expect(find.text('Ảnh đại diện'), findsOneWidget);
      expect(find.text('Chọn từ thư viện'), findsOneWidget);
      expect(find.text('Dùng ảnh Google'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Dismiss Sheet
      await tester.tap(find.byKey(const Key('avatar_option_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Chọn từ thư viện'), findsNothing);

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // Open Avatar Sheet in English
      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();

      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Use Google photo'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Dismiss Sheet
      await tester.tap(find.byKey(const Key('avatar_option_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Choose from gallery'), findsNothing);
    });

    testWidgets('Logout Confirmation Dialog reflects language switch reactively',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testSnapshot = ProfileSnapshot(
        userId: 'loc_user_logout',
        fullName: 'Athlete Logout',
        profile: ProfileEntity(age: 30, height: 180, weight: 75),
        avatar: null,
      );

      final fakeRepo = _FakeProfileRepository(testSnapshot);
      final fakeAvatarRepo = _FakeAvatarRepository();
      final initialState = ProfileState(
        status: ProfileStatus.ready,
        profile: testSnapshot.profile,
        snapshot: testSnapshot,
        confirmedUserId: testSnapshot.userId,
        isNetworkConfirmed: true,
      );

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          avatarRepositoryProvider.overrideWithValue(fakeAvatarRepo),
          profileProvider.overrideWith(
            (ref) => _TestProfileNotifier(
              fakeRepo,
              avatarRepository: fakeAvatarRepo,
              initialState: initialState,
            ),
          ),
          languageProvider.overrideWith((ref) => LanguageNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedProfileApp(
          container: container,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Logout in Vietnamese
      await tester.ensureVisible(find.text('Đăng xuất'));
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Đăng xuất')),
        findsNWidgets(2),
      ); // Dialog Title & Action Button
      expect(find.text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản Saman không?'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Cancel Dialog
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // Switch to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // Tap Logout in English
      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Log out')),
        findsNWidgets(2),
      ); // Dialog Title & Action Button
      expect(find.text('Are you sure you want to log out of your Saman account?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel Dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Incomplete Profile Notice reflects language switch reactively',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const incompleteSnapshot = ProfileSnapshot(
        userId: 'loc_user_inc',
        fullName: 'Athlete Incomplete',
        profile: ProfileEntity(age: null, height: null, weight: null),
        avatar: null,
      );

      final fakeRepo = _FakeProfileRepository(incompleteSnapshot);
      final fakeAvatarRepo = _FakeAvatarRepository();
      final initialState = ProfileState(
        status: ProfileStatus.incomplete,
        profile: incompleteSnapshot.profile,
        snapshot: incompleteSnapshot,
        confirmedUserId: incompleteSnapshot.userId,
        isNetworkConfirmed: true,
      );

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileRepositoryProvider.overrideWithValue(fakeRepo),
          avatarRepositoryProvider.overrideWithValue(fakeAvatarRepo),
          profileProvider.overrideWith(
            (ref) => _TestProfileNotifier(
              fakeRepo,
              avatarRepository: fakeAvatarRepo,
              initialState: initialState,
            ),
          ),
          languageProvider.overrideWith((ref) => LanguageNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedProfileApp(
          container: container,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Incomplete banner in VI
      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);

      // Switch to EN
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ chưa hoàn thiện'), findsNothing);
      expect(find.text('Profile incomplete'), findsOneWidget);

      // Switch back to VI
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ chưa hoàn thiện'), findsOneWidget);
      expect(find.text('Profile incomplete'), findsNothing);
    });
  });
}
