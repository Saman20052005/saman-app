import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/utils/auth_helper.dart';
import 'package:health_ai_app/providers/profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthHelper.logout - Token and Cache Cleanup', () {
    test('removes all auth tokens and identity from secure storage and prefs',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'secret_auth_token_123',
        'jwt_token': 'secret_jwt_token_456',
        'user_email': 'test@example.com',
        'user_fullname': 'Test Athlete',
      });

      SharedPreferences.setMockInitialValues({
        'cached_profile': '{"age": 25, "height": 175}',
        'cached_profile_snapshot_v2': '{"profile": {"age": 25}}',
        'language_code': 'vi',
        'is_dark_mode': true,
        'user_email': 'test@example.com',
        'user_fullname': 'Test Athlete',
      });

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );

      // Perform logout
      await AuthHelper.logout(container);

      // Verify secure storage cleanup
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'auth_token'), isNull);
      expect(await secure.read(key: 'jwt_token'), isNull);
      expect(await secure.read(key: 'user_email'), isNull);
      expect(await secure.read(key: 'user_fullname'), isNull);

      // Verify SharedPreferences cleanup
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cached_profile'), isFalse);
      expect(prefs.containsKey('cached_profile_snapshot_v2'), isFalse);
      expect(prefs.containsKey('user_email'), isFalse);
      expect(prefs.containsKey('user_fullname'), isFalse);

      // Verify preserved settings
      expect(prefs.getString('language_code'), equals('vi'));
      expect(prefs.getBool('is_dark_mode'), isTrue);
    });

    test('increments Profile session epoch and resets profile state', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      final notifier = container.read(profileProvider.notifier);
      final initialEpoch = notifier.sessionEpoch;

      await AuthHelper.logout(container);

      expect(notifier.sessionEpoch, equals(initialEpoch + 1));
      final state = container.read(profileProvider);
      expect(state.status, equals(ProfileStatus.initial));
      expect(state.profile.isValid, isFalse);
    });

    test('is idempotent when called multiple times sequentially', () async {
      SharedPreferences.setMockInitialValues({
        'language_code': 'en',
        'is_dark_mode': false,
      });

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      await AuthHelper.logout(container);
      await AuthHelper.logout(container);
      await AuthHelper.logout(container);

      expect(prefs.getString('language_code'), equals('en'));
      expect(prefs.getBool('is_dark_mode'), isFalse);
      expect(await AuthHelper.hasValidSession(), isFalse);
    });
  });
}
