import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/core/widgets/coach_marks/coach_tour_service.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/domain/models/community_notification.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/notifications/community_notifications_screen.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home/widgets/widgets.dart';
import 'package:health_ai_app/screens/home_screen.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/screens/settings/app_settings_screen.dart';

class _NullPlanNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _NullPlanNutritionNotifier() : super(const AsyncValue.data(null));

  @override
  MacroTargets? get macroTargets => null;

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  Future<String> addWater(
    int amountMl, {
    required String date,
    String? idempotencyKey,
  }) async =>
      'ok';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCommunityNotificationsNotifier
    extends StateNotifier<CommunityNotificationsState>
    implements CommunityNotificationsNotifier {
  _FakeCommunityNotificationsNotifier({
    List<CommunityNotification> initial = const [],
  }) : super(CommunityNotificationsState(allNotifications: initial));

  @override
  Future<void> loadNotifications() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    CoachTourService.isTestBypassEnabled = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
  });

  tearDown(() {
    CoachTourService.isTestBypassEnabled = false;
  });

  group('QuickActionDock', () {
    testWidgets(
      'has no Tooltip wrapper and triggers Log meal / Add water on first tap',
      (tester) async {
        var logMealTapped = 0;
        var addWaterTapped = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuickActionDock(
                onLogMealTap: () => logMealTapped++,
                onAddWaterTap: () => addWaterTapped++,
              ),
            ),
          ),
        );

        expect(find.byType(Tooltip), findsNothing);

        await tester.tap(find.text('Log meal'));
        await tester.pump();
        expect(logMealTapped, 1);

        await tester.tap(find.text('Add water'));
        await tester.pump();
        expect(addWaterTapped, 1);
      },
    );
  });

  group('SamanPicksCarousel', () {
    testWidgets(
      'hides frozen V1 cards (Journal & Shop) and collapses to zero height',
      (tester) async {
        expect(kEnableFrozenModulesV1, isFalse);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SamanPicksCarousel(),
              ),
            ),
          ),
        );

        expect(find.textContaining('SAMAN JOURNAL'), findsNothing);
        expect(find.textContaining('SAMAN SHOP'), findsNothing);

        final size = tester.getSize(find.byType(SamanPicksCarousel));
        expect(size, Size.zero);
      },
    );
  });

  group('HomeScreen wiring and honest data', () {
    Future<ProviderContainer> pumpHomeScreen(
      WidgetTester tester, {
      List<CommunityNotification> notifications = const [],
    }) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sharedPrefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          nutritionProvider.overrideWith((ref) => _NullPlanNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(null),
          communityNotificationsProvider.overrideWith(
            (ref) => _FakeCommunityNotificationsNotifier(initial: notifications),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return container;
    }

    testWidgets(
      'shows honest zero state instead of fake 1850 kcal when plan is null and CTA switches to Nutrition tab',
      (tester) async {
        final container = await pumpHomeScreen(tester);

        expect(find.text('1,850'), findsNothing);
        expect(find.text('1850'), findsNothing);
        expect(find.text('120g'), findsNothing);
        expect(find.text('210g'), findsNothing);
        expect(find.text('55g'), findsNothing);
        expect(find.text('1.8L'), findsNothing);

        expect(find.text('Chưa thiết lập mục tiêu hôm nay'), findsOneWidget);
        expect(find.text('Thiết lập mục tiêu'), findsOneWidget);

        await tester.ensureVisible(find.text('Thiết lập mục tiêu'));
        await tester.tap(find.text('Thiết lập mục tiêu'));
        await tester.pump();

        expect(container.read(mainNavIndexProvider), 3);
      },
    );

    testWidgets(
      'View progress has no broken-font snackbar and switches mainNavIndexProvider to Workout tab (1)',
      (tester) async {
        final container = await pumpHomeScreen(tester);

        expect(find.textContaining('T?nh n?ng'), findsNothing);

        final consistencyCard = find.byType(WeeklyConsistencyCard);
        expect(consistencyCard, findsOneWidget);
        await tester.ensureVisible(consistencyCard);

        final widget = tester.widget<WeeklyConsistencyCard>(consistencyCard);
        widget.onViewProgressTap?.call();
        await tester.pump();

        expect(find.textContaining('T?nh n?ng'), findsNothing);
        expect(container.read(mainNavIndexProvider), 1);
      },
    );

    testWidgets(
      'Settings button navigates directly to AppSettingsScreen without BottomSheet',
      (tester) async {
        await pumpHomeScreen(tester);

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();

        expect(find.byType(AppSettingsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Notification bell reflects real unreadCount (false by default) and opens CommunityNotificationsScreen',
      (tester) async {
        await pumpHomeScreen(tester);

        final headerDefault = tester.widget<HomeHeader>(find.byType(HomeHeader));
        expect(headerDefault.hasUnreadNotifications, isFalse);

        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();

        expect(find.byType(CommunityNotificationsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Notification bell badge turns true when unread notifications exist',
      (tester) async {
        await pumpHomeScreen(
          tester,
          notifications: const [
            CommunityNotification(
              id: 'n1',
              actorName: 'Minh',
              actionText: 'liked your post',
              timeAgo: '2m',
              isUnread: true,
              type: CommunityNotificationType.like,
            ),
          ],
        );

        final header = tester.widget<HomeHeader>(find.byType(HomeHeader));
        expect(header.hasUnreadNotifications, isTrue);
      },
    );

    testWidgets(
      'Saman Community card displays on Home and navigates to AppRoutes.communityFeed while Shop and Journal stay hidden',
      (tester) async {
        await pumpHomeScreen(tester);

        // Verify Shop and Journal remain 100% hidden
        expect(find.textContaining('SAMAN JOURNAL'), findsNothing);
        expect(find.textContaining('SAMAN SHOP'), findsNothing);

        // Scroll down in CustomScrollView to lazily build and reveal SamanCommunityCard
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();

        // Verify Saman Community card is present
        final communityCard = find.byType(SamanCommunityCard);
        expect(communityCard, findsOneWidget);
        expect(find.text('Cộng đồng Saman'), findsOneWidget);
        expect(
          find.text('Chia sẻ buổi tập, Form Check & kết nối gymer'),
          findsOneWidget,
        );

        await tester.ensureVisible(communityCard);
        await tester.tap(communityCard);
        await tester.pumpAndSettle();

        // Destination screen is CommunityFeedScreen
        expect(find.byType(CommunityFeedScreen), findsOneWidget);
      },
    );
  });
}
