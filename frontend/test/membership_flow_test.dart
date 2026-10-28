import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/features/membership/presentation/screens/compare_plans_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/membership_coming_soon_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/membership_overview_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/plan_detail_screen.dart';
import 'package:health_ai_app/features/membership/presentation/tokens/membership_tokens.dart';
import 'package:health_ai_app/features/membership/presentation/widgets/primary_membership_button.dart';
import 'package:health_ai_app/features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:health_ai_app/presentation/screens/workout_home_screen.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_draft.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProfileRepository implements ProfileRepository {
  ProfileSnapshot? snapshot;

  _FakeProfileRepository();

  @override
  Future<ProfileSnapshot?> fetchProfileSnapshot(
          {bool cacheOnSuccess = false}) async =>
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

class _CustomProfileNotifier extends ProfileNotifier {
  _CustomProfileNotifier(super.repository, ProfileState initialState) {
    state = initialState;
  }

  @override
  Future<void> loadProfile({bool forceRefresh = false}) async {}
}

class _MockNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _MockNutritionNotifier()
      : super(AsyncValue.data(NutritionPlan(
          date: '2026-10-27',
          meals: [
            Meal(
              foodId: 'plan-1',
              mealType: 'Dinner',
              time: '19:00',
              name: 'Salmon Fillet & Sweet Potato',
              calories: 520,
              protein: 44,
              carbs: 48,
              fat: 16,
              weightGrams: 250,
            ),
          ],
          targetWater: 2500,
          currentWater: 1500,
        )));

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2500,
        protein: 160,
        carbs: 240,
        fat: 65,
      );

  @override
  Future<void> loadDailyPlan(DateTime date,
      {bool forceRefresh = false,
      int fallbackCalories = 2000,
      String fallbackGoal = 'maintain'}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required Widget child,
  BillingPeriod initialPeriod = BillingPeriod.monthly,
  double textScaleFactor = 1.0,
  Size screenSize = const Size(390, 844),
  Key? captureKey,
  ProfileState? profileState,
  List<dynamic> extraOverrides = const [],
}) {
  SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
  return ProviderScope(
    overrides: [
      billingPeriodProvider.overrideWith((ref) => initialPeriod),
      secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
      if (profileState != null)
        profileProvider.overrideWith(
          (ref) => _CustomProfileNotifier(
            _FakeProfileRepository(),
            profileState,
          ),
        ),
      workoutHistoryProvider.overrideWith((ref) async => []),
      nutritionProvider.overrideWith((ref) => _MockNutritionNotifier()),
      ...extraOverrides.cast<Override>(),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: MembershipTokens.canvas,
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          textScaler: TextScaler.linear(textScaleFactor),
          padding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
        child: captureKey != null
            ? RepaintBoundary(key: captureKey, child: child)
            : child,
      ),
    ),
  );
}

Future<void> _captureScreen(WidgetTester tester, String filename) async {
  final boundaryFinder = find.byKey(const ValueKey('render_capture_boundary'));
  if (boundaryFinder.evaluate().isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      final evidenceDir = Platform.environment['SAMAN_RENDER_EVIDENCE'] ??
          'D:/SamanDev/runtime_evidence/membership/CP-MEM-03';
      final file = File('$evidenceDir/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    image.dispose();
  });
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final Uint8List kTransparentImage = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });
  group('Membership Catalog & Product Contract Tests', () {
    test('Catalog contains 4 plans with exact pricing and specifications', () {
      const plans = MembershipCatalog.plans;
      expect(plans.length, 4);

      // Free Plan
      final free = plans.firstWhere((p) => p.tier == MembershipTier.free);
      expect(free.monthlyPrice, 0);
      expect(free.yearlyPrice, 0);
      expect(free.yearlyEquivalentMonthlyPrice, 0);
      expect(free.isCurrent, isTrue);
      expect(free.isRecommended, isFalse);
      expect(free.plannedBenefits, isEmpty);

      // Plus Plan
      final plus = plans.firstWhere((p) => p.tier == MembershipTier.plus);
      expect(plus.monthlyPrice, 10);
      expect(plus.yearlyPrice, 60);
      expect(plus.yearlyEquivalentMonthlyPrice, 5);
      expect(plus.isRecommended, isFalse);
      expect(plus.plannedBenefits.length, 2);
      expect(plus.aiAllowanceText, 'To be announced');
      expect(plus.workoutCvAllowanceText, isNull);

      // Pro Plan
      final pro = plans.firstWhere((p) => p.tier == MembershipTier.pro);
      expect(pro.monthlyPrice, 15);
      expect(pro.yearlyPrice, 120);
      expect(pro.yearlyEquivalentMonthlyPrice, 10);
      expect(pro.isRecommended, isTrue);
      expect(pro.plannedBenefits.length, 3);
      expect(pro.aiAllowanceText, 'To be announced');
      expect(pro.workoutCvAllowanceText, 'To be announced');

      // Ultra Plan
      final ultra = plans.firstWhere((p) => p.tier == MembershipTier.ultra);
      expect(ultra.monthlyPrice, 30);
      expect(ultra.yearlyPrice, 240);
      expect(ultra.yearlyEquivalentMonthlyPrice, 20);
      expect(ultra.isRecommended, isFalse);
      expect(ultra.plannedBenefits.length, 3);
      expect(ultra.aiAllowanceText, '5x Pro · Planned');
      expect(ultra.workoutCvAllowanceText, 'To be announced');
    });

    test('Comparison Matrix features are correctly grouped and mapped', () {
      const features = MembershipCatalog.matrixFeatures;
      expect(features.length, 11);

      // Group 1: Core Essentials (4 items)
      final core =
          features.where((f) => f.group == FeatureGroup.coreEssentials);
      expect(core.length, 4);
      for (final f in core) {
        expect(f.statusFor(MembershipTier.free), InclusionStatus.included);
        expect(f.statusFor(MembershipTier.plus), InclusionStatus.included);
        expect(f.statusFor(MembershipTier.pro), InclusionStatus.included);
        expect(f.statusFor(MembershipTier.ultra), InclusionStatus.included);
      }

      // Group 2: Nutrition AI (2 items)
      final nutrition =
          features.where((f) => f.group == FeatureGroup.nutritionAi);
      expect(nutrition.length, 2);
      for (final f in nutrition) {
        expect(f.statusFor(MembershipTier.free), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.plus), InclusionStatus.planned);
        expect(f.statusFor(MembershipTier.pro), InclusionStatus.planned);
        expect(f.statusFor(MembershipTier.ultra), InclusionStatus.planned);
      }

      // Group 3: Workout CV (3 items)
      final workout = features.where((f) => f.group == FeatureGroup.workoutCv);
      expect(workout.length, 3);
      for (final f in workout) {
        expect(f.statusFor(MembershipTier.free), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.plus), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.pro), InclusionStatus.planned);
        expect(f.statusFor(MembershipTier.ultra), InclusionStatus.planned);
      }

      // Group 4: Advanced Intelligence (2 items)
      final advanced =
          features.where((f) => f.group == FeatureGroup.advancedIntelligence);
      expect(advanced.length, 2);
      for (final f in advanced) {
        expect(f.statusFor(MembershipTier.free), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.plus), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.pro), InclusionStatus.notIncluded);
        expect(f.statusFor(MembershipTier.ultra), InclusionStatus.planned);
      }
    });

    test('Account remains Free demo entitlement', () {
      final container = ProviderContainer();
      final currentTier = container.read(currentMembershipTierProvider);
      expect(currentTier, MembershipTier.free);
    });
  });

  group('MembershipOverviewScreen UI & Pricing Tests', () {
    testWidgets('Renders header, 4 plan cards, and toggles Monthly/Yearly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // App bar & Header
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('MEMBERSHIP PREVIEW'), findsOneWidget);
      expect(find.text('Elevate your training.'), findsOneWidget);
      expect(find.text('CURRENT PLAN: FREE'), findsOneWidget);

      // 4 Plan Names
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Plus'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Ultra'), findsOneWidget);

      // Badges
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text('COMING SOON'), findsNWidgets(3)); // Plus, Pro, Ultra
      expect(find.text('Your Active Plan'), findsOneWidget);

      // Default Monthly prices
      expect(find.text(r'$0'), findsNWidgets(2)); // Notice card + Free card
      expect(find.text(r'$10'), findsOneWidget);
      expect(find.text(r'$15'), findsOneWidget);
      expect(find.text(r'$30'), findsOneWidget);

      // Buttons
      expect(find.text('Explore Plus'), findsOneWidget);
      expect(find.text('Explore Pro'), findsOneWidget);
      expect(find.text('Explore Ultra'), findsOneWidget);
      expect(find.text('Compare all plans'), findsOneWidget);

      // Switch to Yearly
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();

      // Yearly pricing verification
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text(r'$120'), findsOneWidget);
      expect(find.text(r'$240'), findsOneWidget);
      expect(find.text('Equivalent to \$5 / month'), findsOneWidget);
      expect(find.text('Equivalent to \$10 / month'), findsOneWidget);
      expect(find.text('Equivalent to \$20 / month'), findsOneWidget);
    });
  });

  group('MembershipOverviewScreen Navigation & Plan Detail Routing Tests', () {
    testWidgets('Explore Plus opens Plus PlanDetailScreen and Back returns',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Explore Plus'), 200);
      await tester.tap(find.text('Explore Plus'));
      await tester.pumpAndSettle();

      // In Plus detail screen
      expect(find.text('NUTRITION AI'), findsOneWidget);
      expect(find.text('Gemini food photo analysis'), findsOneWidget);

      // Hit Back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on Overview
      expect(find.text('Elevate your training.'), findsOneWidget);
    });

    testWidgets('Explore Pro opens Pro PlanDetailScreen with Recommended badge',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Explore Pro'), 200);
      await tester.tap(find.text('Explore Pro'));
      await tester.pumpAndSettle();

      expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);
      expect(find.text('Workout CV AI'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Elevate your training.'), findsOneWidget);
    });

    testWidgets('Compare all plans button opens ComparePlansScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Compare all plans'), 200);
      await tester.tap(find.text('Compare all plans'));
      await tester.pumpAndSettle();

      expect(find.text('Compare plans'), findsOneWidget);
      expect(find.text('Find your fit.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Elevate your training.'), findsOneWidget);
    });
  });

  group('Profile Integration Tests (Banner & Manage Membership)', () {
    testWidgets(
        'ProfileScreen renders banner and tapping opens MembershipOverviewScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 26,
        height: 178.0,
        weight: 74.0,
        gender: Gender.male,
        activityCanonical: 'moderate',
        goal: Goal.gain_muscle,
      );

      await tester.pumpWidget(
        _buildTestApp(
          profileState: ProfileState(
            status: ProfileStatus.ready,
            profile: testProfile,
          ),
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find banner card
      final bannerFinder =
          find.byKey(const Key('profile_membership_banner_card'));
      expect(bannerFinder, findsOneWidget);
      expect(find.text('Saman Membership'), findsOneWidget);

      // Tap banner to navigate to Overview
      await tester.tap(bannerFinder);
      await tester.pumpAndSettle();

      // Now in Overview screen
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('Elevate your training.'), findsOneWidget);

      // Back to Profile
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_membership_banner_card')),
          findsOneWidget);
    });

    testWidgets(
        'ProfileScreen renders Manage membership and opens ManageMembershipScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testProfile = ProfileEntity(
        age: 26,
        height: 178.0,
        weight: 74.0,
        gender: Gender.male,
        activityCanonical: 'moderate',
        goal: Goal.gain_muscle,
      );

      await tester.pumpWidget(
        _buildTestApp(
          profileState: ProfileState(
            status: ProfileStatus.ready,
            profile: testProfile,
          ),
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to ACCOUNT section
      final manageNavFinder =
          find.byKey(const Key('manage_membership_nav_row'));
      await tester.scrollUntilVisible(manageNavFinder, 200);
      expect(manageNavFinder, findsOneWidget);

      await tester.tap(manageNavFinder);
      await tester.pumpAndSettle();

      // In Manage Membership Screen
      expect(find.text('Manage membership'), findsOneWidget);
      expect(find.text('CURRENT PLAN'), findsOneWidget);

      // Back to Profile
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('manage_membership_nav_row')), findsOneWidget);
    });

    testWidgets(
        'ManageMembership -> Explore Plans opens Overview -> Back returns to Manage',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Explore Plans in Manage screen
      await tester.scrollUntilVisible(find.text('Explore Plans'), 200);
      await tester.tap(find.text('Explore Plans'));
      await tester.pumpAndSettle();

      // Now on Overview
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('Elevate your training.'), findsOneWidget);

      // Tap Back on Overview -> Should return to Manage
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Manage membership'), findsOneWidget);
      expect(find.text('CURRENT PLAN'), findsOneWidget);
    });
  });

  group('Safe Back to Membership & Full Chain Navigation', () {
    testWidgets(
        'Overview -> Compare -> Detail -> Coming Soon -> Back to Membership returns to Overview',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. From Overview, tap Compare all plans
      await tester.scrollUntilVisible(find.text('Compare all plans'), 200);
      await tester.tap(find.text('Compare all plans'));
      await tester.pumpAndSettle();
      expect(find.text('Compare plans'), findsOneWidget);

      // 2. From Compare, tap Explore Pro
      await tester.scrollUntilVisible(find.text('Explore Pro'), 200);
      await tester.tap(find.text('Explore Pro'));
      await tester.pumpAndSettle();
      expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);

      // 3. From Detail, tap Coming Soon
      await tester.scrollUntilVisible(find.text('Coming Soon'), 200);
      await tester.tap(find.text('Coming Soon'));
      await tester.pumpAndSettle();
      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text("YOU'RE EXPLORING"), findsOneWidget);

      // 4. Tap Back to Membership on Coming Soon screen
      await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
      await tester.tap(find.text('Back to Membership'));
      await tester.pumpAndSettle();

      // Should safely pop back to MembershipOverviewScreen!
      expect(find.text('Elevate your training.'), findsOneWidget);
      expect(find.text('CURRENT PLAN: FREE'), findsOneWidget);
    });

    testWidgets('Detail Back to Membership returns to Overview',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Explore Ultra from Overview
      await tester.scrollUntilVisible(find.text('Explore Ultra'), 200);
      await tester.tap(find.text('Explore Ultra'));
      await tester.pumpAndSettle();
      expect(find.text('PERSONALIZED INTELLIGENCE'), findsOneWidget);

      // Tap Back to Membership
      await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
      await tester.tap(find.text('Back to Membership'));
      await tester.pumpAndSettle();

      expect(find.text('Elevate your training.'), findsOneWidget);
    });

    testWidgets(
        'Standalone PlanDetail safely navigates to Overview on Back to Membership',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Mounted without Overview in stack
      await tester.pumpWidget(
        _buildTestApp(
          child: const PlanDetailScreen(tier: MembershipTier.plus),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NUTRITION AI'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
      await tester.tap(find.text('Back to Membership'));
      await tester.pumpAndSettle();

      // Should safely push Overview without crashing
      expect(find.text('Elevate your training.'), findsOneWidget);
    });
  });

  group('ComparePlansScreen UI & Billing Period Tests', () {
    testWidgets('Renders all sections and toggles Monthly/Yearly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and intro
      expect(find.text('Compare plans'), findsOneWidget);
      expect(find.text('MEMBERSHIP PREVIEW'), findsOneWidget);
      expect(find.text('Find your fit.'), findsOneWidget);

      // Default Monthly pricing check
      expect(find.text(r'$0'), findsOneWidget);
      expect(find.text(r'$10'), findsOneWidget);
      expect(find.text(r'$15'), findsOneWidget);
      expect(find.text(r'$30'), findsOneWidget);

      // Legend
      expect(find.text('STATUS LEGEND'), findsOneWidget);
      expect(find.text('Included in Free'), findsOneWidget);
      expect(find.text('Planned inclusion'), findsOneWidget);
      expect(find.text('Not in this tier'), findsOneWidget);

      // Switch to Yearly
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();

      // Verify Yearly pricing shown
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text(r'$120'), findsOneWidget);
      expect(find.text(r'$240'), findsOneWidget);
      expect(find.text('Equivalent to \$5 / month'), findsOneWidget);
      expect(find.text('Equivalent to \$10 / month'), findsOneWidget);
      expect(find.text('Equivalent to \$20 / month'), findsOneWidget);
    });
  });

  group('Compare -> Detail Navigation & State Flow Tests', () {
    testWidgets('Preserves BillingPeriod through Compare -> Detail -> Back',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Yearly in Compare
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(find.text(r'$60'), findsOneWidget);

      // Scroll to and Tap Explore Plus
      await tester.scrollUntilVisible(find.text('Explore Plus'), 200);
      await tester.tap(find.text('Explore Plus'));
      await tester.pumpAndSettle();

      // Should be in Plus PlanDetailScreen
      expect(find.text('Plus'), findsWidgets);
      expect(find.text('NUTRITION AI'), findsOneWidget);
      // Yearly price should be preserved!
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text('/ year'), findsOneWidget);
      expect(find.text('Equivalent to \$5 / month'), findsOneWidget);

      // Hit Back in AppBar
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on Compare screen, and Yearly is still active!
      expect(find.text('Compare plans'), findsOneWidget);
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text('Equivalent to \$5 / month'), findsOneWidget);
    });

    testWidgets('Opens Pro Detail with RECOMMENDED badge and correct benefits',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to and Tap Explore Pro
      await tester.scrollUntilVisible(find.text('Explore Pro'), 200);
      await tester.tap(find.text('Explore Pro'));
      await tester.pumpAndSettle();

      // Verify Pro Screen details
      expect(find.text('Pro'), findsWidgets);
      expect(find.text('RECOMMENDED'), findsWidgets);
      expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);
      expect(find.text('Workout CV AI'), findsOneWidget);
      expect(find.text('Movement analysis and rep counting'), findsOneWidget);
      expect(find.text('Separate Workout CV allowance'), findsOneWidget);
    });

    testWidgets(
        'Opens Ultra Detail with 5x Pro allowance and Advanced Thinking',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to and Tap Explore Ultra
      await tester.scrollUntilVisible(find.text('Explore Ultra'), 200);
      await tester.tap(find.text('Explore Ultra'));
      await tester.pumpAndSettle();

      // Verify Ultra Screen details
      expect(find.text('Ultra'), findsWidgets);
      expect(find.text('PERSONALIZED INTELLIGENCE'), findsOneWidget);
      expect(find.text('5x Pro AI allowance'), findsOneWidget);
      expect(find.text('Advanced Thinking'), findsOneWidget);
      expect(find.text('Extended history and personalized memory'),
          findsOneWidget);
      expect(find.text('5x Pro · Planned'), findsOneWidget);
    });
  });

  group('PlanDetailScreen Inherited Benefits & Interactions', () {
    testWidgets('Inherited benefits card expands and collapses properly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const PlanDetailScreen(tier: MembershipTier.pro),
        ),
      );
      await tester.pumpAndSettle();

      // Initially collapsed
      expect(find.text('Everything in Plus'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Nutrition logging'), findsNothing);

      // Tap to expand
      await tester.scrollUntilVisible(find.text('Everything in Plus'), 200);
      await tester.tap(find.text('Everything in Plus'));
      await tester.pumpAndSettle();

      // Now expanded: shows Free essentials and planned Plus benefits
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.text('Nutrition logging'), findsOneWidget);
      expect(find.text('Manual workout tracking'), findsOneWidget);
      expect(find.text('Free food photo analysis'), findsOneWidget);
      expect(find.text('Gemini food photo analysis'), findsOneWidget);
      expect(find.text('Monthly AI allowance'), findsOneWidget);

      // Tap again to collapse
      await tester.scrollUntilVisible(find.text('Everything in Plus'), 200);
      await tester.tap(find.text('Everything in Plus'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Nutrition logging'), findsNothing);
    });

    testWidgets('Primary Coming Soon and Back to Membership trigger callbacks',
        (tester) async {
      bool comingSoonTriggered = false;
      bool backToMembershipTriggered = false;

      await tester.pumpWidget(
        _buildTestApp(
          child: PlanDetailScreen(
            tier: MembershipTier.plus,
            onComingSoon: () => comingSoonTriggered = true,
            onBackToMembership: () => backToMembershipTriggered = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to and Tap Coming Soon
      await tester.scrollUntilVisible(find.text('Coming Soon'), 200);
      await tester.tap(find.text('Coming Soon'));
      expect(comingSoonTriggered, isTrue);

      // Scroll to and Tap Back to Membership
      await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
      await tester.tap(find.text('Back to Membership'));
      expect(backToMembershipTriggered, isTrue);
    });
  });

  group('Responsiveness & Layout Tests', () {
    testWidgets('Overview renders at 390x844 without overflow errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Overview renders with large text scale (1.3x) without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          textScaleFactor: 1.3,
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('ComparePlansScreen renders at 390x844 without overflow errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ComparePlansScreen renders with large text scale (1.3x) without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          textScaleFactor: 1.3,
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Touch target size for Primary button is >= 48px',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const Scaffold(
            body: PrimaryMembershipButton(
              text: 'Coming Soon',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(ElevatedButton));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
        'ManageMembershipScreen renders at 390x844 and with large text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          textScaleFactor: 1.3,
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'MembershipComingSoonScreen renders at 390x844 and with large text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(390, 844),
          textScaleFactor: 1.3,
          child: const MembershipComingSoonScreen(tier: MembershipTier.ultra),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ManageMembershipScreen Content & FAQ Interaction Tests', () {
    testWidgets('Renders Current Plan Free and all Free benefits',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Header & Badge
      expect(find.text('Manage membership'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);

      // Current Plan Free
      expect(find.text('CURRENT PLAN'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('· \$0'), findsOneWidget);
      expect(find.text('Your everyday tracking essentials.'), findsOneWidget);
      expect(find.text('No paid membership activated.'), findsOneWidget);

      // Free Benefits
      expect(find.text('YOUR FREE BENEFITS'), findsOneWidget);
      expect(find.text('Nutrition logging'), findsOneWidget);
      expect(find.text('Keep a record of your meals.'), findsOneWidget);
      expect(find.text('Manual workout tracking'), findsOneWidget);
      expect(find.text('Free food photo analysis'), findsOneWidget);
      expect(find.text('Basic health metrics'), findsOneWidget);

      // Discovery Card
      expect(find.text("Explore what's next."), findsOneWidget);
      expect(find.text('Explore Plans'), findsOneWidget);

      // FAQ
      expect(find.text('MEMBERSHIP FAQ'), findsOneWidget);
      expect(find.text('What does my Free plan include?'), findsOneWidget);
      expect(find.text('Can I upgrade now?'), findsOneWidget);
      expect(find.text('Are prices and AI limits final?'), findsOneWidget);

      // Footer
      expect(
        find.text('Membership preview · Paid plans are not available yet.'),
        findsOneWidget,
      );
    });

    testWidgets('Toggles FAQ item expansion in ManageMembershipScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially collapsed
      expect(
        find.text(
            'Paid memberships are Coming Soon. You can explore the planned benefits, but this preview does not purchase or activate a plan.'),
        findsNothing,
      );

      // Scroll to and Tap FAQ 2
      await tester.scrollUntilVisible(find.text('Can I upgrade now?'), 200);
      await tester.tap(find.text('Can I upgrade now?'));
      await tester.pumpAndSettle();

      // Expanded
      expect(
        find.text(
            'Paid memberships are Coming Soon. You can explore the planned benefits, but this preview does not purchase or activate a plan.'),
        findsOneWidget,
      );

      // Tap again to collapse
      await tester.tap(find.text('Can I upgrade now?'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Paid memberships are Coming Soon. You can explore the planned benefits, but this preview does not purchase or activate a plan.'),
        findsNothing,
      );
    });

    testWidgets('Explore Plans button invokes callback', (tester) async {
      bool explorePlansInvoked = false;

      await tester.pumpWidget(
        _buildTestApp(
          child: ManageMembershipScreen(
            onExplorePlans: () => explorePlansInvoked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Explore Plans'), 200);
      await tester.tap(find.text('Explore Plans'));
      expect(explorePlansInvoked, isTrue);
    });
  });

  group('MembershipComingSoonScreen UI & Pricing Tests', () {
    testWidgets('Shows Plus plan details with Monthly pricing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          initialPeriod: BillingPeriod.monthly,
          child: const MembershipComingSoonScreen(tier: MembershipTier.plus),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('COMING SOON'), findsOneWidget);
      expect(find.text('Something to look forward to.'), findsOneWidget);
      expect(find.text("YOU'RE EXPLORING"), findsOneWidget);
      expect(find.text('Plus'), findsOneWidget);
      expect(find.text('NUTRITION AI'), findsOneWidget);
      expect(
        find.text(
            'Planned Gemini food photo analysis with a monthly AI allowance.'),
        findsOneWidget,
      );

      // Monthly price
      expect(find.text(r'$10'), findsOneWidget);
      expect(find.text('/ month'), findsOneWidget);

      // Reassurance card
      expect(find.text('Your account stays on Free.'), findsOneWidget);
      expect(
        find.text(
            'No payment has been taken and no paid membership has been activated.'),
        findsOneWidget,
      );

      // Primary Action
      expect(find.text('Back to Membership'), findsOneWidget);
    });

    testWidgets('Shows Pro plan details with Yearly pricing and equiv text',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          initialPeriod: BillingPeriod.yearly,
          child: const MembershipComingSoonScreen(tier: MembershipTier.pro),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);
      expect(
        find.text(
            'Planned Workout CV, movement analysis, and rep counting, alongside Nutrition AI.'),
        findsOneWidget,
      );

      // Yearly price for Pro
      expect(find.text(r'$120'), findsOneWidget);
      expect(find.text('/ year'), findsOneWidget);
      expect(find.text('Equivalent to \$10 / month'), findsOneWidget);
    });

    testWidgets('Back to Membership button calls callback', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool backInvoked = false;

      await tester.pumpWidget(
        _buildTestApp(
          child: MembershipComingSoonScreen(
            tier: MembershipTier.ultra,
            onBackToMembership: () => backInvoked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
      await tester.tap(find.text('Back to Membership'));
      expect(backInvoked, isTrue);
    });
  });

  group('Widget Render Evidence Captures', () {
    testWidgets('Renders and captures MembershipOverviewScreen Monthly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const captureKey = ValueKey('render_capture_boundary');
      await tester.pumpWidget(
        _buildTestApp(
          captureKey: captureKey,
          initialPeriod: BillingPeriod.monthly,
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'overview_monthly.png');
    });

    testWidgets('Renders and captures MembershipOverviewScreen Yearly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const captureKey = ValueKey('render_capture_boundary');
      await tester.pumpWidget(
        _buildTestApp(
          captureKey: captureKey,
          initialPeriod: BillingPeriod.yearly,
          child: const MembershipOverviewScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'overview_yearly.png');
    });

    testWidgets('Renders and captures ManageMembershipScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const captureKey = ValueKey('render_capture_boundary');
      await tester.pumpWidget(
        _buildTestApp(
          captureKey: captureKey,
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'manage_membership.png');
    });

    testWidgets('Renders and captures MembershipComingSoonScreen Monthly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const captureKey = ValueKey('render_capture_boundary');
      await tester.pumpWidget(
        _buildTestApp(
          captureKey: captureKey,
          initialPeriod: BillingPeriod.monthly,
          child: const MembershipComingSoonScreen(tier: MembershipTier.pro),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'coming_soon_pro_monthly.png');
    });

    testWidgets('Renders and captures MembershipComingSoonScreen Yearly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const captureKey = ValueKey('render_capture_boundary');
      await tester.pumpWidget(
        _buildTestApp(
          captureKey: captureKey,
          initialPeriod: BillingPeriod.yearly,
          child: const MembershipComingSoonScreen(tier: MembershipTier.pro),
        ),
      );
      await tester.pumpAndSettle();

      await _captureScreen(tester, 'coming_soon_pro_yearly.png');
    });

    group('UpgradeBottomSheet UI & Content Tests', () {
      testWidgets('Nutrition Upgrade Sheet renders all specs and benefits',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            child: const UpgradeBottomSheet(tier: MembershipTier.plus),
          ),
        );
        await tester.pumpAndSettle();

        // Top Icon Tile
        expect(find.byIcon(Icons.restaurant), findsOneWidget);

        // Badge
        expect(
            find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText().contains('PLUS')),
            findsWidgets);
        expect(
            find.byWidgetPredicate((w) =>
                w is RichText && w.text.toPlainText().contains('PREVIEW')),
            findsWidgets);

        // Headline and Subtitle
        expect(find.text('Explore Nutrition AI'), findsOneWidget);
        expect(
          find.text(
              'Discover planned Gemini food photo analysis with Saman Plus.'),
          findsOneWidget,
        );

        // Benefits
        expect(find.text('Gemini food photo analysis'), findsOneWidget);
        expect(find.text('Monthly AI allowance'), findsOneWidget);

        // Inset Card Footer
        expect(find.text('Limits to be announced.'), findsOneWidget);
        expect(find.text('PLANNED'), findsOneWidget);

        // Buttons & Footnote
        expect(find.text('Explore Plus'), findsOneWidget);
        expect(find.text('Continue with Free'), findsOneWidget);
        expect(
          find.text('Preview only · Paid memberships are not available yet.'),
          findsOneWidget,
        );
      });

      testWidgets('Workout Upgrade Sheet renders all specs and benefits',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            child: const UpgradeBottomSheet(tier: MembershipTier.pro),
          ),
        );
        await tester.pumpAndSettle();

        // Top Icon Tile
        expect(find.byIcon(Icons.fitness_center), findsOneWidget);

        // Badge
        expect(
            find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText().contains('PRO')),
            findsWidgets);
        expect(
            find.byWidgetPredicate((w) =>
                w is RichText && w.text.toPlainText().contains('PREVIEW')),
            findsWidgets);

        // Headline and Subtitle
        expect(find.text('Explore Workout Intelligence'), findsOneWidget);
        expect(
          find.text('Discover planned Workout CV benefits with Saman Pro.'),
          findsOneWidget,
        );

        // Benefits
        expect(find.text('Workout CV AI'), findsOneWidget);
        expect(find.text('Movement analysis and rep counting'), findsOneWidget);
        expect(find.text('Separate Workout CV allowance'), findsOneWidget);

        // Inset Card Footer
        expect(find.text('Limits to be announced.'), findsOneWidget);
        expect(find.text('PLANNED'), findsOneWidget);

        // Buttons & Footnote
        expect(find.text('Explore Pro'), findsOneWidget);
        expect(find.text('Back to Workout'), findsOneWidget);
        expect(
          find.text('Preview only · Paid memberships are not available yet.'),
          findsOneWidget,
        );
      });
    });

    group('UpgradeBottomSheet Responsiveness & Layout Tests', () {
      testWidgets('Nutrition Upgrade Sheet renders at 390x844 without overflow',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: const Size(390, 844),
            child: const UpgradeBottomSheet(tier: MembershipTier.plus),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'Nutrition Upgrade Sheet renders with 1.3x text scale without overflow',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            textScaleFactor: 1.3,
            child: const UpgradeBottomSheet(tier: MembershipTier.plus),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('Workout Upgrade Sheet renders at 390x844 without overflow',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            screenSize: const Size(390, 844),
            child: const UpgradeBottomSheet(tier: MembershipTier.pro),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'Workout Upgrade Sheet renders with 1.3x text scale without overflow',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            textScaleFactor: 1.3,
            child: const UpgradeBottomSheet(tier: MembershipTier.pro),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('Touch target size for Primary button is >= 48px',
          (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const UpgradeBottomSheet(tier: MembershipTier.plus),
          ),
        );
        await tester.pumpAndSettle();

        final buttonFinder =
            find.byKey(const ValueKey('upgrade_sheet_explore_plus_button'));
        final buttonSize = tester.getSize(buttonFinder);
        expect(buttonSize.height, greaterThanOrEqualTo(48.0));
      });
    });

    group('UpgradeBottomSheet Actions & Return Value Tests', () {
      testWidgets(
          'Explore Plus returns MembershipTier.plus and Close returns null',
          (tester) async {
        MembershipTier? result;

        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showUpgradeBottomSheet(
                    context,
                    tier: MembershipTier.plus,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Explore Nutrition AI'), findsOneWidget);

        // Tap Explore Plus
        await tester.tap(
            find.byKey(const ValueKey('upgrade_sheet_explore_plus_button')));
        await tester.pumpAndSettle();

        // Returned tier must be plus
        expect(result, MembershipTier.plus);

        // Now test Close returns null
        result = MembershipTier.plus;
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('upgrade_sheet_close_button')));
        await tester.pumpAndSettle();

        expect(result, isNull);
      });

      testWidgets(
          'Explore Pro returns MembershipTier.pro and Secondary returns null',
          (tester) async {
        MembershipTier? result;

        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showUpgradeBottomSheet(
                    context,
                    tier: MembershipTier.pro,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Explore Workout Intelligence'), findsOneWidget);

        // Tap Explore Pro
        await tester.tap(
            find.byKey(const ValueKey('upgrade_sheet_explore_pro_button')));
        await tester.pumpAndSettle();

        expect(result, MembershipTier.pro);

        // Test Secondary returns null
        result = MembershipTier.pro;
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('upgrade_sheet_secondary_button')));
        await tester.pumpAndSettle();

        expect(result, isNull);
      });

      testWidgets('Dismissing sheet preserves origin screen state',
          (tester) async {
        int counter = 42;

        await tester.pumpWidget(
          _buildTestApp(
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Column(
                  children: [
                    Text('Counter: $counter'),
                    ElevatedButton(
                      onPressed: () async {
                        final res = await showUpgradeBottomSheet(
                          context,
                          tier: MembershipTier.plus,
                        );
                        if (res != null) {
                          setState(() => counter = 999);
                        }
                      },
                      child: const Text('Open Sheet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Counter: 42'), findsOneWidget);

        // Open and dismiss sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('upgrade_sheet_close_button')));
        await tester.pumpAndSettle();

        // State is completely preserved
        expect(find.text('Counter: 42'), findsOneWidget);
      });
    });

    group('Safe Navigation & Origin Route Preservation Tests', () {
      testWidgets(
          'Feature -> Detail -> Coming Soon -> Back to Membership -> Back returns to Feature',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('ORIGIN FEATURE SCREEN'),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              settings: const RouteSettings(
                                  name: '/membership/detail/plus'),
                              builder: (_) => const PlanDetailScreen(
                                tier: MembershipTier.plus,
                              ),
                            ),
                          );
                        },
                        child: const Text('Open Detail'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ORIGIN FEATURE SCREEN'), findsOneWidget);

        // 1. Open Detail
        await tester.tap(find.text('Open Detail'));
        await tester.pumpAndSettle();
        expect(find.text('NUTRITION AI'), findsOneWidget);

        // 2. Open Coming Soon
        await tester.scrollUntilVisible(find.text('Coming Soon'), 200);
        await tester.tap(find.text('Coming Soon'));
        await tester.pumpAndSettle();
        expect(find.text("YOU'RE EXPLORING"), findsOneWidget);

        // 3. Tap Back to Membership on Coming Soon
        await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
        await tester.tap(find.text('Back to Membership'));
        await tester.pumpAndSettle();

        // Lands on Overview
        expect(find.text('Elevate your training.'), findsOneWidget);

        // 4. Tap Back from Overview
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Must land back on Origin Feature Screen!
        expect(find.text('ORIGIN FEATURE SCREEN'), findsOneWidget);
        expect(find.text('NUTRITION AI'), findsNothing);
        expect(find.text("YOU'RE EXPLORING"), findsNothing);
      });

      testWidgets(
          'An unnamed origin route (settings.name == null) is preserved on Back to Membership',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Push unnamed route
        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('UNNAMED ORIGIN ROUTE'),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              // unnamed route
                              builder: (_) => Scaffold(
                                body: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('UNNAMED SUB FEATURE'),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              settings: const RouteSettings(
                                                  name:
                                                      '/membership/detail/pro'),
                                              builder: (_) =>
                                                  const PlanDetailScreen(
                                                tier: MembershipTier.pro,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text('Open Pro Detail'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: const Text('Open Unnamed Sub Feature'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open unnamed sub feature
        await tester.tap(find.text('Open Unnamed Sub Feature'));
        await tester.pumpAndSettle();
        expect(find.text('UNNAMED SUB FEATURE'), findsOneWidget);

        // Open Pro Detail
        await tester.tap(find.text('Open Pro Detail'));
        await tester.pumpAndSettle();
        expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);

        // Tap Back to Membership on Detail
        await tester.scrollUntilVisible(find.text('Back to Membership'), 200);
        await tester.tap(find.text('Back to Membership'));
        await tester.pumpAndSettle();

        // Lands on Overview
        expect(find.text('Elevate your training.'), findsOneWidget);

        // Back from Overview must return to UNNAMED SUB FEATURE
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('UNNAMED SUB FEATURE'), findsOneWidget);
      });
    });

    group('Feature Header Entry Points & Exploration Tests', () {
      testWidgets('NutritionScreen renders PLUS · PREVIEW chip and opens sheet',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            profileState: ProfileState(
              profile: const ProfileEntity(
                age: 28,
                gender: Gender.male,
                height: 178,
                weight: 75,
                activityLevel: ActivityLevel.medium,
                goal: Goal.gain_muscle,
              ),
              targetCalories: 2500,
              targetProtein: 160,
              targetCarbs: 240,
              targetFat: 65,
              waterTargetMl: 2500,
              isLoading: false,
            ),
            child: const NutritionScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Check header and Report button
        expect(find.text('Nutrition'), findsOneWidget);
        expect(find.text('Report'), findsOneWidget);

        // Check PLUS · PREVIEW chip
        final chipFinder = find.byKey(const ValueKey('nutrition_upgrade_chip'));
        expect(chipFinder, findsOneWidget);

        // Tap chip to open upgrade sheet
        await tester.tap(chipFinder);
        await tester.pumpAndSettle();

        // Sheet is visible
        expect(find.text('Explore Nutrition AI'), findsOneWidget);
        expect(find.text('Gemini food photo analysis'), findsOneWidget);

        // Tap Explore Plus
        await tester.tap(
            find.byKey(const ValueKey('upgrade_sheet_explore_plus_button')));
        await tester.pumpAndSettle();

        // Navigates to PlanDetailScreen (Plus)
        expect(find.text('NUTRITION AI'), findsOneWidget);

        // Back returns to NutritionScreen
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('Nutrition'), findsOneWidget);
        expect(find.text('Report'), findsOneWidget);
      });

      testWidgets(
          'WorkoutHomeScreen renders PRO · PREVIEW chip and opens sheet',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildTestApp(
            child: const WorkoutHomeScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Check header and My Plans
        expect(find.text('Workout'), findsOneWidget);
        expect(find.text('My Plans'), findsOneWidget);

        // Check PRO · PREVIEW chip
        final chipFinder = find.byKey(const ValueKey('workout_upgrade_chip'));
        expect(chipFinder, findsOneWidget);

        // Tap chip to open workout upgrade sheet
        await tester.tap(chipFinder);
        await tester.pumpAndSettle();

        // Sheet is visible
        expect(find.text('Explore Workout Intelligence'), findsOneWidget);
        expect(find.text('Workout CV AI'), findsOneWidget);

        // Tap Explore Pro
        await tester.tap(
            find.byKey(const ValueKey('upgrade_sheet_explore_pro_button')));
        await tester.pumpAndSettle();

        // Navigates to PlanDetailScreen (Pro)
        expect(find.text('WORKOUT INTELLIGENCE'), findsOneWidget);
        expect(find.text('RECOMMENDED'), findsOneWidget);

        // Back returns to WorkoutHomeScreen
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Workout'), findsOneWidget);
        expect(find.text('My Plans'), findsOneWidget);
      });
    });

    group('CP-MEM-03 Upgrade Bottom Sheets Render Captures', () {
      testWidgets('Renders and captures Nutrition Upgrade Sheet',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const captureKey = ValueKey('render_capture_boundary');
        await tester.pumpWidget(
          _buildTestApp(
            captureKey: captureKey,
            child: Scaffold(
              backgroundColor: MembershipTokens.canvas,
              body: Stack(
                children: [
                  Container(color: Colors.black.withOpacity(0.75)),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: UpgradeBottomSheet(tier: MembershipTier.plus),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureScreen(tester, 'nutrition_upgrade_sheet.png');
      });

      testWidgets('Renders and captures Workout Upgrade Sheet', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const captureKey = ValueKey('render_capture_boundary');
        await tester.pumpWidget(
          _buildTestApp(
            captureKey: captureKey,
            child: Scaffold(
              backgroundColor: MembershipTokens.canvas,
              body: Stack(
                children: [
                  Container(color: Colors.black.withOpacity(0.75)),
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: UpgradeBottomSheet(tier: MembershipTier.pro),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureScreen(tester, 'workout_upgrade_sheet.png');
      });
    });
  });
}
