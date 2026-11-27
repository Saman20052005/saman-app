import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_metadata.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/privacy/data/privacy_service.dart';
import 'package:health_ai_app/features/privacy/presentation/screens/health_consent_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/features/profile/presentation/profile_gate.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/settings/app_settings_screen.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final dynamic body;
}

class _MockHttpAdapter implements HttpClientAdapter {
  _MockHttpAdapter(this.handler);

  final Map<String, dynamic> Function(_RecordedRequest req) handler;
  final List<_RecordedRequest> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    dynamic decodedBody;
    if (options.data != null) {
      decodedBody = options.data;
    } else if (requestStream != null) {
      final bytes = await requestStream.expand((e) => e).toList();
      if (bytes.isNotEmpty) {
        decodedBody = jsonDecode(utf8.decode(bytes));
      }
    }

    final req = _RecordedRequest(
      method: options.method.toUpperCase(),
      path: options.path,
      headers: Map<String, dynamic>.from(options.headers),
      body: decodedBody,
    );
    requests.add(req);

    final payload = handler(req);
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository([this.snapshot]);
  ProfileSnapshot? snapshot;

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot({
    bool cacheOnSuccess = false,
  }) async =>
      snapshot;

  @override
  Future<ProfileEntity?> fetchProfile() async => snapshot?.profile;

  @override
  Future<void> syncProfile(ProfileEntity profile) async {}

  @override
  Future<void> cacheSnapshot(ProfileSnapshot snapshot) async {}

  @override
  Future<void> clearLocalProfile({String? userId}) async {}

  @override
  Future<void> saveDraft(OnboardingDraft draft) async {}

  @override
  Future<OnboardingDraft?> getDraft(String userId) async => null;

  @override
  Future<void> clearDraft(String userId) async {}
}

class _StaticProfileNotifier extends ProfileNotifier {
  _StaticProfileNotifier(super.repository, ProfileState initialState) {
    state = initialState;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

class _FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-11-27',
              meals: const [],
              currentWater: 1000,
              targetWater: 2500,
              totalCaloriesConsumed: 1200,
              totalProteinConsumed: 90,
              totalCarbsConsumed: 140,
              totalFatConsumed: 40,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2200,
        protein: 150,
        carbs: 240,
        fat: 65,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testProfile = ProfileEntity(
    age: 26,
    height: 172.0,
    weight: 68.0,
    gender: Gender.male,
    activityCanonical: 'moderate',
    goal: Goal.maintain_weight,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthHelper.setStorageForTesting(_InMemorySecureStorage());
  });

  tearDown(() {
    AuthHelper.resetStorageForTesting();
    ProfileGate.bypassConsentGateForTests = false;
  });

  group('PrivacyService unit tests', () {
    test('fetchConsentStatus, submitConsent, exportUserData, deleteAccount',
        () async {
      final adapter = _MockHttpAdapter((req) {
        if (req.method == 'GET' && req.path.endsWith('/api/user/consent')) {
          return {
            'has_consented': false,
            'required_version': PrivacyService.requiredConsentVersion,
          };
        }
        if (req.method == 'POST' && req.path.endsWith('/api/user/consent')) {
          return {
            'has_consented': true,
            'required_version': PrivacyService.requiredConsentVersion,
            'consent_version': PrivacyService.requiredConsentVersion,
            'accepted_at': '2026-11-27T07:00:00Z',
            'accepted_health_data': true,
            'accepted_ai_processing': true,
            'acknowledged_medical_disclaimer': true,
          };
        }
        if (req.method == 'GET' && req.path.endsWith('/api/user/export')) {
          return {
            'exported_at': '2026-11-27T07:00:00Z',
            'collections': {'workouts': [], 'nutrition_logs': []},
          };
        }
        if (req.method == 'DELETE' && req.path.endsWith('/api/user/account')) {
          return {
            'deleted': true,
            'collections_cleaned': 37,
            'total_documents_deleted': 12,
            'r2_objects_deleted': 1,
            'r2_objects_failed': 0,
          };
        }
        throw StateError('Unexpected request: ${req.method} ${req.path}');
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = PrivacyService(
        dio: dio,
        tokenProvider: () async => 'test-jwt-token',
      );

      final initial = await service.fetchConsentStatus(userId: 'user_1');
      expect(initial.hasConsented, isFalse);
      expect(await service.hasCachedConsent('user_1'), isFalse);

      final submitted = await service.submitConsent(
        userId: 'user_1',
        acceptedHealthData: true,
        acceptedAiProcessing: true,
        acknowledgedMedicalDisclaimer: true,
      );
      expect(submitted.hasConsented, isTrue);
      expect(await service.hasCachedConsent('user_1'), isTrue);

      final exported = await service.exportUserData();
      expect(exported['exported_at'], equals('2026-11-27T07:00:00Z'));

      final deleted = await service.deleteAccount(
        confirmText: 'XOA',
        userId: 'user_1',
      );
      expect(deleted.deleted, isTrue);
      expect(deleted.collectionsCleaned, equals(37));
      expect(await service.hasCachedConsent('user_1'), isFalse);

      final deleteReq = adapter.requests.last;
      expect(deleteReq.method, equals('DELETE'));
      expect(deleteReq.body, equals({'confirm_text': 'XOA'}));
      expect(
        deleteReq.headers['Authorization'],
        equals('Bearer test-jwt-token'),
      );
    });
  });

  group('HealthConsentScreen widget tests', () {
    testWidgets('requires all 3 checkboxes before enabling submit and calling API',
        (tester) async {
      bool acceptedCalled = false;
      final adapter = _MockHttpAdapter((req) {
        return {
          'has_consented': true,
          'required_version': PrivacyService.requiredConsentVersion,
          'consent_version': PrivacyService.requiredConsentVersion,
          'accepted_at': '2026-11-27T07:00:00Z',
          'accepted_health_data': true,
          'accepted_ai_processing': true,
          'acknowledged_medical_disclaimer': true,
        };
      });
      final service = PrivacyService(
        dio: Dio()..httpClientAdapter = adapter,
        tokenProvider: () async => 'jwt',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            privacyServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: HealthConsentScreen(
              userId: 'user_consent_1',
              onAccepted: () => acceptedCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      ElevatedButton submitButton() => tester.widget<ElevatedButton>(
            find.byKey(const Key('consent_submit_button')),
          );

      // 0 checked -> disabled
      expect(submitButton().onPressed, isNull);

      // 1 checked -> disabled
      await tester.tap(find.byKey(const Key('consent_checkbox_health')));
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // 2 checked -> disabled
      await tester.tap(find.byKey(const Key('consent_checkbox_ai')));
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // 3 checked -> enabled
      await tester.tap(find.byKey(const Key('consent_checkbox_medical')));
      await tester.pump();
      expect(submitButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('consent_submit_button')));
      await tester.pumpAndSettle();

      expect(adapter.requests.length, equals(1));
      expect(adapter.requests.first.method, equals('POST'));
      expect(acceptedCalled, isTrue);
    });
  });

  group('AppSettingsScreen privacy section tests', () {
    testWidgets('export data dialog and 2-step delete account confirmation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls.add(call);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final adapter = _MockHttpAdapter((req) {
        if (req.method == 'GET' && req.path.endsWith('/api/user/export')) {
          return {
            'exported_at': '2026-11-27T07:10:00Z',
            'collections': {'workouts': []},
          };
        }
        if (req.method == 'DELETE' && req.path.endsWith('/api/user/account')) {
          return {
            'deleted': true,
            'collections_cleaned': 37,
            'total_documents_deleted': 5,
            'r2_objects_deleted': 0,
            'r2_objects_failed': 0,
          };
        }
        return {
          'has_consented': true,
          'required_version': PrivacyService.requiredConsentVersion,
          'consent_version': PrivacyService.requiredConsentVersion,
        };
      });

      final service = PrivacyService(
        dio: Dio()..httpClientAdapter = adapter,
        tokenProvider: () async => 'jwt',
      );
      final fakeRepo = _FakeProfileRepository(
        const ProfileSnapshot(profile: testProfile, userId: 'user_del_1'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(_InMemorySecureStorage()),
            privacyServiceProvider.overrideWithValue(service),
            profileRepositoryProvider.overrideWithValue(fakeRepo),
            profileProvider.overrideWith(
              (ref) => _StaticProfileNotifier(
                fakeRepo,
                ProfileState(
                  status: ProfileStatus.ready,
                  profile: testProfile,
                  confirmedUserId: 'user_del_1',
                  isNetworkConfirmed: true,
                ),
              ),
            ),
            appVersionProvider.overrideWithValue('1.0.0 (1)'),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            routes: {
              AppRoutes.login: (_) => const Scaffold(
                    key: Key('login_screen_marker'),
                    body: Text('Login'),
                  ),
            },
            home: const AppSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Export Data
      final exportRow = find.byKey(const Key('setting_row_export_data'));
      await tester.ensureVisible(exportRow);
      await tester.tap(exportRow);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_copy_json_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('export_copy_json_button')));
      await tester.pump();
      expect(clipboardCalls, isNotEmpty);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      // 2. Delete Account
      final deleteRow = find.byKey(const Key('setting_row_delete_account'));
      await tester.ensureVisible(deleteRow);
      await tester.tap(deleteRow);
      await tester.pumpAndSettle();

      ElevatedButton confirmBtn() => tester.widget<ElevatedButton>(
            find.byKey(const Key('delete_account_confirm_button')),
          );

      expect(confirmBtn().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('delete_account_confirm_input')),
        'WRONG',
      );
      await tester.pump();
      expect(confirmBtn().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('delete_account_confirm_input')),
        'XOA',
      );
      await tester.pump();
      expect(confirmBtn().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('delete_account_confirm_button')));
      await tester.pumpAndSettle();

      expect(
        adapter.requests.any(
          (r) =>
              r.method == 'DELETE' &&
              r.path.endsWith('/api/user/account') &&
              (r.body as Map)['confirm_text'] == 'XOA',
        ),
        isTrue,
      );
      expect(find.byKey(const Key('login_screen_marker')), findsOneWidget);
    });
  });

  group('ProfileGate consent gate integration tests', () {
    testWidgets(
        'shows HealthConsentScreen when unconsented, admits MainScreen after submit, and uses cache next time',
        (tester) async {
      bool serverConsented = false;
      int getConsentCalls = 0;

      final adapter = _MockHttpAdapter((req) {
        if (req.method == 'GET' && req.path.endsWith('/api/user/consent')) {
          getConsentCalls++;
          return {
            'has_consented': serverConsented,
            'required_version': PrivacyService.requiredConsentVersion,
          };
        }
        if (req.method == 'POST' && req.path.endsWith('/api/user/consent')) {
          serverConsented = true;
          return {
            'has_consented': true,
            'required_version': PrivacyService.requiredConsentVersion,
            'consent_version': PrivacyService.requiredConsentVersion,
            'accepted_at': '2026-11-27T07:20:00Z',
            'accepted_health_data': true,
            'accepted_ai_processing': true,
            'acknowledged_medical_disclaimer': true,
          };
        }
        return {};
      });

      final service = PrivacyService(
        dio: Dio()..httpClientAdapter = adapter,
        tokenProvider: () async => 'jwt',
      );
      final fakeRepo = _FakeProfileRepository(
        const ProfileSnapshot(profile: testProfile, userId: 'user_gate_1'),
      );

      Widget buildGate() {
        return ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(_InMemorySecureStorage()),
            privacyServiceProvider.overrideWithValue(service),
            profileRepositoryProvider.overrideWithValue(fakeRepo),
            profileProvider.overrideWith(
              (ref) => _StaticProfileNotifier(
                fakeRepo,
                ProfileState(
                  status: ProfileStatus.ready,
                  profile: testProfile,
                  confirmedUserId: 'user_gate_1',
                  isNetworkConfirmed: true,
                ),
              ),
            ),
            nutritionProvider.overrideWith((ref) => _FakeNutritionNotifier()),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ProfileGate(),
          ),
        );
      }

      // First launch: unconsented -> shows HealthConsentScreen
      await tester.pumpWidget(buildGate());
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(HealthConsentScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(getConsentCalls, equals(1));

      // Accept all 3 checkboxes & submit
      await tester.tap(find.byKey(const Key('consent_checkbox_health')));
      await tester.tap(find.byKey(const Key('consent_checkbox_ai')));
      await tester.tap(find.byKey(const Key('consent_checkbox_medical')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('consent_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(HealthConsentScreen), findsNothing);
      expect(await service.hasCachedConsent('user_gate_1'), isTrue);

      // Second launch (fresh ProfileGate): cache hit -> enters MainScreen directly with 0 extra GET calls
      await tester.pumpWidget(Container());
      await tester.pump();
      await tester.pumpWidget(buildGate());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(HealthConsentScreen), findsNothing);
      expect(getConsentCalls, equals(1));
    });
  });
}
