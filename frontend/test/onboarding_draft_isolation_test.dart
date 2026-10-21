import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/features/profile/data/datasources/profile_local_data_source.dart';
import 'package:health_ai_app/features/profile/data/models/profile_snapshot_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/presentation/onboarding/biometric_input_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileEntity - Six Raw Fields isComplete Validation', () {
    test('returns true only when all six raw fields are explicitly provided and valid', () {
      const completeProfile = ProfileEntity(
        userId: 'user_1',
        age: 25,
        height: 175.0,
        weight: 70.0,
        gender: Gender.female,
        activityLevel: ActivityLevel.high,
        goal: Goal.lose_weight,
      );

      expect(completeProfile.isComplete, isTrue);
      expect(completeProfile.isValid, isTrue);
    });

    test('raw fallback getters do NOT count towards isComplete', () {
      // Profile has valid age, height, weight, but NO gender, activityLevel, or goal
      const fallbackProfile = ProfileEntity(
        userId: 'user_fallback',
        age: 28,
        height: 178.0,
        weight: 75.0,
      );

      // isValid is true (only checks age, height, weight)
      expect(fallbackProfile.isValid, isTrue);

      // Fallbacks return defaults
      expect(fallbackProfile.gender, equals(Gender.male));
      expect(fallbackProfile.activityLevel, equals(ActivityLevel.medium));
      expect(fallbackProfile.goal, equals(Goal.maintain_weight));

      // BUT raw getters are null
      expect(fallbackProfile.rawGender, isNull);
      expect(fallbackProfile.rawActivityLevel, isNull);
      expect(fallbackProfile.rawGoal, isNull);

      // isComplete MUST be false
      expect(fallbackProfile.isComplete, isFalse);
    });

    test('Gender.other is valid for isComplete', () {
      const otherGenderProfile = ProfileEntity(
        userId: 'user_other',
        age: 24,
        height: 165.0,
        weight: 60.0,
        gender: Gender.other,
        activityLevel: ActivityLevel.low,
        goal: Goal.maintain_weight,
      );

      expect(otherGenderProfile.isComplete, isTrue);
      expect(otherGenderProfile.gender, equals(Gender.other));
    });

    test('boundary and invalid numeric values are incomplete', () {
      // Age out of bounds (< 13 or > 120)
      const youngProfile = ProfileEntity(
        age: 12,
        height: 150.0,
        weight: 45.0,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );
      expect(youngProfile.isComplete, isFalse);

      const oldProfile = ProfileEntity(
        age: 121,
        height: 160.0,
        weight: 55.0,
        gender: Gender.female,
        activityLevel: ActivityLevel.low,
        goal: Goal.maintain_weight,
      );
      expect(oldProfile.isComplete, isFalse);

      // Height <= 0 or not finite
      const zeroHeightProfile = ProfileEntity(
        age: 25,
        height: 0.0,
        weight: 65.0,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );
      expect(zeroHeightProfile.isComplete, isFalse);

      const infiniteHeightProfile = ProfileEntity(
        age: 25,
        height: double.infinity,
        weight: 65.0,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );
      expect(infiniteHeightProfile.isComplete, isFalse);

      // Weight <= 0 or not finite
      const negativeWeightProfile = ProfileEntity(
        age: 25,
        height: 170.0,
        weight: -5.0,
        gender: Gender.male,
        activityLevel: ActivityLevel.medium,
        goal: Goal.maintain_weight,
      );
      expect(negativeWeightProfile.isComplete, isFalse);
    });
  });

  group('OnboardingDraft & LocalDataSource - Owner Partitioning and Isolation', () {
    test('draft is stored under onboarding_draft_{user_id} with exact raw values', () async {
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const draft = OnboardingDraft(
        userId: 'usr_alpha_99',
        age: 27,
        height: 181.5,
        weight: 79.2,
        gender: Gender.male,
        activityLevel: ActivityLevel.high,
        goal: Goal.gain_muscle,
        step: 3,
        schemaVersion: 1,
      );

      await dataSource.saveDraft(draft);

      expect(prefs.containsKey('onboarding_draft_usr_alpha_99'), isTrue);
      final loaded = await dataSource.getDraft('usr_alpha_99');

      expect(loaded, isNotNull);
      expect(loaded!.userId, equals('usr_alpha_99'));
      expect(loaded.age, equals(27));
      expect(loaded.height, equals(181.5));
      expect(loaded.weight, equals(79.2));
      expect(loaded.gender, equals(Gender.male));
      expect(loaded.activityLevel, equals(ActivityLevel.high));
      expect(loaded.goal, equals(Goal.gain_muscle));
      expect(loaded.step, equals(3));
      expect(loaded.schemaVersion, equals(1));
    });

    test('rejects saving draft without verified userId', () async {
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const emptyUserDraft = OnboardingDraft(
        userId: '',
        age: 25,
      );

      expect(
        () => dataSource.saveDraft(emptyUserDraft),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('A/B draft isolation: User A cannot read or leak User B draft', () async {
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const draftA = OnboardingDraft(
        userId: 'user_alice',
        age: 22,
        height: 168.0,
        weight: 58.0,
        gender: Gender.female,
      );
      const draftB = OnboardingDraft(
        userId: 'user_bob',
        age: 35,
        height: 185.0,
        weight: 88.0,
        gender: Gender.male,
      );

      await dataSource.saveDraft(draftA);
      await dataSource.saveDraft(draftB);

      final readA = await dataSource.getDraft('user_alice');
      final readB = await dataSource.getDraft('user_bob');

      expect(readA!.userId, equals('user_alice'));
      expect(readA.age, equals(22));
      expect(readB!.userId, equals('user_bob'));
      expect(readB.age, equals(35));

      // Non-existent user returns null
      expect(await dataSource.getDraft('user_charlie'), isNull);
    });

    test('backend-complete user ignores stale onboarding draft', () {
      // Draft created from the confirmed incomplete snapshot (carries base)
      const incompleteSnapshot = ProfileSnapshot(
        userId: 'user_complete_1',
        profile: ProfileEntity(userId: 'user_complete_1'),
      );
      final draft = OnboardingDraft.forSnapshot(
        incompleteSnapshot,
        age: 20,
        step: 2,
      );

      // Confirmed snapshot from backend where profile is complete
      const completeSnapshot = ProfileSnapshot(
        userId: 'user_complete_1',
        profile: ProfileEntity(
          userId: 'user_complete_1',
          age: 29,
          height: 175.0,
          weight: 72.0,
          gender: Gender.male,
          activityLevel: ActivityLevel.medium,
          goal: Goal.maintain_weight,
        ),
      );

      // Incompatible because snapshot is already complete!
      expect(draft.isCompatibleWith(completeSnapshot), isFalse);

      // Incomplete snapshot with matching userId and unchanged base is compatible
      expect(draft.isCompatibleWith(incompleteSnapshot), isTrue);

      // Legacy draft without base values is never auto-resumed
      const legacyDraft = OnboardingDraft(userId: 'user_complete_1', age: 20);
      expect(legacyDraft.isCompatibleWith(incompleteSnapshot), isFalse);

      // Snapshot with different userId is incompatible
      const differentUserSnapshot = ProfileSnapshot(
        userId: 'user_complete_2',
        profile: ProfileEntity(userId: 'user_complete_2'),
      );
      expect(draft.isCompatibleWith(differentUserSnapshot), isFalse);
    });

    test('A/B partitioned cache isolation: User B does not get User A cached snapshot', () async {
      final prefs = await SharedPreferences.getInstance();
      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const snapshotA = ProfileSnapshotModel(
        userId: 'user_a_owner',
        profile: ProfileEntity(
          userId: 'user_a_owner',
          age: 25,
          height: 175,
          weight: 70,
        ),
        targetCalories: 2200,
      );

      await dataSource.cacheSnapshot(snapshotA);

      // User A reads their partitioned cache
      final loadedA = await dataSource.getLastSnapshot(expectedUserId: 'user_a_owner');
      expect(loadedA, isNotNull);
      expect(loadedA!.userId, equals('user_a_owner'));

      // User B querying with their own ID receives null
      final loadedB = await dataSource.getLastSnapshot(expectedUserId: 'user_b_owner');
      expect(loadedB, isNull);
    });

    test('legacy unowned cache is NOT applied to a newly authenticated user session', () async {
      final prefs = await SharedPreferences.getInstance();
      // Pre-existing legacy cache with NO user_id
      await prefs.setString(
        'cached_profile_snapshot_v2',
        '{"profile": {"age": 29, "height": 180, "weight": 75}}',
      );

      final dataSource = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      // Querying with an authenticated user ID rejects unowned cache
      final loaded = await dataSource.getLastSnapshot(expectedUserId: 'new_authenticated_user');
      expect(loaded, isNull);
    });
  });

  group('OnboardingDraft - Validation, Base Snapshot and Restore Compatibility', () {
    const baseSnapshot = ProfileSnapshot(
      userId: 'user_v',
      profile: ProfileEntity(userId: 'user_v', age: 30, height: 171.25),
    );

    Map<String, dynamic> validJson({
      Object? schema = 1,
      Object? step = 2,
      String owner = 'user_v',
    }) {
      return {
        'user_id': owner,
        'age': 31,
        'height': 180.5,
        'weight': null,
        'gender': null,
        'activity_level': null,
        'goal': null,
        'step': step,
        'schema_version': schema,
        'base': {
          'age': 30,
          'height': 171.25,
          'weight': null,
          'gender': null,
          'activity_level': null,
          'goal': null,
        },
      };
    }

    Future<ProfileLocalDataSourceImpl> sourceWithRaw(Object raw) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_draft_user_v': raw is String ? raw : jsonEncode(raw),
      });
      final prefs = await SharedPreferences.getInstance();
      return ProfileLocalDataSourceImpl(sharedPreferences: prefs);
    }

    test('well-formed stored draft is accepted (control for rejection cases)',
        () async {
      final ds = await sourceWithRaw(validJson());
      expect(await ds.getDraft('user_v'), isNotNull);
    });

    test('unsupported schema version is rejected', () async {
      final ds = await sourceWithRaw(validJson(schema: 99));
      expect(await ds.getDraft('user_v'), isNull);
      final missing = validJson()..remove('schema_version');
      expect(await (await sourceWithRaw(missing)).getDraft('user_v'), isNull);
    });

    test('step 0 and step 6 (and non-integer step) are rejected', () async {
      for (final badStep in <Object>[0, 6, -1, '2', 2.5]) {
        final ds = await sourceWithRaw(validJson(step: badStep));
        expect(await ds.getDraft('user_v'), isNull, reason: 'step=$badStep');
      }
      for (final okStep in [1, 5]) {
        final ds = await sourceWithRaw(validJson(step: okStep));
        expect((await ds.getDraft('user_v'))!.step, equals(okStep));
      }
    });

    test('corrupt JSON, wrong types and unknown enum are rejected without throwing',
        () async {
      expect(await (await sourceWithRaw('{not json')).getDraft('user_v'), isNull);
      expect(await (await sourceWithRaw('[1,2,3]')).getDraft('user_v'), isNull);
      expect(
          await (await sourceWithRaw(validJson()..['age'] = '31'))
              .getDraft('user_v'),
          isNull);
      expect(
          await (await sourceWithRaw(validJson()..['gender'] = 'robot'))
              .getDraft('user_v'),
          isNull);
    });

    test('draft stored under owner key but declaring another owner is rejected',
        () async {
      final ds = await sourceWithRaw(validJson(owner: 'someone_else'));
      expect(await ds.getDraft('user_v'), isNull);
    });

    test('saving draft with unsupported schema or step is rejected', () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = ProfileLocalDataSourceImpl(sharedPreferences: prefs);
      for (final bad in [
        const OnboardingDraft(userId: 'user_v', step: 0),
        const OnboardingDraft(userId: 'user_v', step: 6),
        const OnboardingDraft(userId: 'user_v', schemaVersion: 2),
      ]) {
        await expectLater(ds.saveDraft(bad), throwsArgumentError);
      }
      expect(prefs.containsKey('onboarding_draft_user_v'), isFalse);
    });

    test('same owner, backend still incomplete, base values changed: not restorable',
        () {
      final draft = OnboardingDraft.forSnapshot(baseSnapshot, age: 31, step: 3);
      expect(draft.isCompatibleWith(baseSnapshot), isTrue);

      for (final changed in [
        const ProfileEntity(userId: 'user_v', age: 33, height: 171.25),
        const ProfileEntity(userId: 'user_v', age: 30, height: 172.0),
        const ProfileEntity(userId: 'user_v', age: 30, height: 171.25, weight: 70),
        const ProfileEntity(
            userId: 'user_v', age: 30, height: 171.25, goal: Goal.lose_weight),
      ]) {
        final newer = ProfileSnapshot(userId: 'user_v', profile: changed);
        expect(newer.profile.isComplete, isFalse);
        expect(draft.isCompatibleWith(newer), isFalse);
      }
    });

    test('base comparison uses raw fields, never fallback getters', () {
      // Base: gender NOT set (raw null). Fallback getter would report male.
      final draft = OnboardingDraft.forSnapshot(baseSnapshot, age: 31);
      expect(draft.base!.gender, isNull);
      expect(draft.base!.activityLevel, isNull);
      expect(draft.base!.goal, isNull);

      // Backend now explicitly stores gender = male: fallback-equal, raw-different.
      const newer = ProfileSnapshot(
        userId: 'user_v',
        profile: ProfileEntity(
          userId: 'user_v',
          age: 30,
          height: 171.25,
          gender: Gender.male,
        ),
      );
      expect(newer.profile.gender, equals(baseSnapshot.profile.gender));
      expect(draft.isCompatibleWith(newer), isFalse);
    });

    test('draft based on an unconfirmed (cache) snapshot is refused and cache is not restorable',
        () {
      const cached = ProfileSnapshot(
        userId: 'user_v',
        profile: ProfileEntity(userId: 'user_v', age: 30, height: 171.25),
        isFromCache: true,
      );
      expect(() => OnboardingDraft.forSnapshot(cached), throwsArgumentError);

      final draft = OnboardingDraft.forSnapshot(baseSnapshot);
      expect(draft.isCompatibleWith(cached), isFalse);
      expect(
        () => OnboardingDraft.forSnapshot(
          const ProfileSnapshot(userId: '', profile: ProfileEntity()),
        ),
        throwsArgumentError,
      );
    });

    test('valid draft keeps precision and step, round-trips and never mutates the snapshot',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      final draft = OnboardingDraft.forSnapshot(
        baseSnapshot,
        age: 31,
        height: 181.57,
        weight: 79.234,
        gender: Gender.other,
        activityLevel: ActivityLevel.high,
        goal: Goal.gain_muscle,
        step: 4,
      );
      await ds.saveDraft(draft);
      final loaded = (await ds.getDraft('user_v'))!;

      expect(loaded.step, equals(4));
      expect(loaded.height, equals(181.57));
      expect(loaded.weight, equals(79.234));
      expect(loaded.gender, equals(Gender.other));
      expect(loaded.base!.height, equals(171.25));
      expect(loaded.isCompatibleWith(baseSnapshot), isTrue);

      // Reading/validating a draft leaves the confirmed snapshot untouched.
      expect(baseSnapshot.profile.age, equals(30));
      expect(baseSnapshot.profile.height, equals(171.25));
      expect(baseSnapshot.profile.weight, isNull);
      expect(baseSnapshot.profile.rawGender, isNull);
    });

    test('logout (clearCache with owner) enqueued behind an in-flight draft write removes the draft',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = ProfileLocalDataSourceImpl(sharedPreferences: prefs);
      final draft = OnboardingDraft.forSnapshot(baseSnapshot, age: 31);

      final write = ds.saveDraft(draft);
      final logoutClear = ds.clearCache(userId: 'user_v');
      await Future.wait([write, logoutClear]);

      expect(prefs.containsKey('onboarding_draft_user_v'), isFalse);
      expect(await ds.getDraft('user_v'), isNull);
    });
  });

  group('CP3 - Five Activity Choices, Decimals & Input Validation', () {
    test('all 5 activity choices persist and read back separately without loss', () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      for (final choice in OnboardingActivityChoice.values) {
        final draft = OnboardingDraft(
          userId: 'user_activity_test',
          activityChoice: choice,
          step: 4,
        );
        await ds.saveDraft(draft);

        final loaded = await ds.getDraft('user_activity_test');
        expect(loaded, isNotNull);
        expect(loaded!.activityChoice, equals(choice));
      }
    });

    test('draft v1 with legacy activityLevel reads back mapped choice while preserving base', () {
      final jsonV1 = {
        'user_id': 'user_legacy',
        'schema_version': 1,
        'step': 4,
        'activity_level': 'high',
        'base': {
          'age': null,
          'height': null,
          'weight': null,
          'gender': null,
          'activity_level': 'high',
          'goal': null,
        },
      };

      final parsed = OnboardingDraft.tryParse(jsonV1);
      expect(parsed, isNotNull);
      expect(parsed!.activityLevel, equals(ActivityLevel.high));
      expect(parsed.activityChoice, equals(OnboardingActivityChoice.active));
      expect(parsed.base!.activityLevel, equals(ActivityLevel.high));
    });

    test('legacy mapping: low->sedentary, medium->moderate, high->active', () {
      expect(OnboardingActivityChoice.fromLegacy(ActivityLevel.low),
          equals(OnboardingActivityChoice.sedentary));
      expect(OnboardingActivityChoice.fromLegacy(ActivityLevel.medium),
          equals(OnboardingActivityChoice.moderate));
      expect(OnboardingActivityChoice.fromLegacy(ActivityLevel.high),
          equals(OnboardingActivityChoice.active));
      expect(OnboardingActivityChoice.fromLegacy(null), isNull);
    });

    test('BiometricInputParser accepts . and , and rejects invalid/unfinished inputs', () {
      // Valid decimals
      expect(BiometricInputParser.parseValidBiometric('175'), equals(175.0));
      expect(BiometricInputParser.parseValidBiometric('175.5'), equals(175.5));
      expect(BiometricInputParser.parseValidBiometric('175,5'), equals(175.5));
      expect(BiometricInputParser.parseValidBiometric('72.25'), equals(72.25));
      expect(BiometricInputParser.parseValidBiometric('72,25'), equals(72.25));

      // Unfinished inputs: null
      expect(BiometricInputParser.parseValidBiometric('72.'), isNull);
      expect(BiometricInputParser.parseValidBiometric('175,'), isNull);
      expect(BiometricInputParser.parseValidBiometric(''), isNull);

      // Mixed / multiple separators
      expect(BiometricInputParser.parseValidBiometric('1,750.5'), isNull);
      expect(BiometricInputParser.parseValidBiometric('72..5'), isNull);
      expect(BiometricInputParser.parseValidBiometric('72,,5'), isNull);

      // Zero and negative: null
      expect(BiometricInputParser.parseValidBiometric('0'), isNull);
      expect(BiometricInputParser.parseValidBiometric('-5'), isNull);

      // Non-numeric / NaN / Infinity: null
      expect(BiometricInputParser.parseValidBiometric('NaN'), isNull);
      expect(BiometricInputParser.parseValidBiometric('Infinity'), isNull);
      expect(BiometricInputParser.parseValidBiometric('abc'), isNull);
    });

    test('raw text is persisted in draft without loss or rounding', () async {
      final prefs = await SharedPreferences.getInstance();
      final ds = ProfileLocalDataSourceImpl(sharedPreferences: prefs);

      const draft = OnboardingDraft(
        userId: 'user_raw_text',
        height: 175.5,
        weight: 72.25,
        rawHeightText: '175,5',
        rawWeightText: '72.250',
        step: 3,
      );
      await ds.saveDraft(draft);

      final loaded = await ds.getDraft('user_raw_text');
      expect(loaded, isNotNull);
      expect(loaded!.rawHeightText, equals('175,5'));
      expect(loaded.rawWeightText, equals('72.250'));
      expect(loaded.height, equals(175.5));
      expect(loaded.weight, equals(72.25));
    });
  });
}
