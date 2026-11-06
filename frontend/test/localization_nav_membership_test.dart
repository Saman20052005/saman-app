import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/screens/home/widgets/saman_bottom_navigation_bar.dart';
import 'package:health_ai_app/features/membership/presentation/screens/compare_plans_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';

Widget _buildLocalizedTestApp({
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
          home: Scaffold(body: child),
        );
      },
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'en',
      'language_code': 'en',
    });
  });

  group('AppTranslations Unit & Parity Verification', () {
    test('en and vi translation maps contain identical keys for navigation and membership', () {
      final requiredKeys = [
        // Navigation Tabs
        'tab_home',
        'tab_workout',
        'tab_saman',
        'tab_nutrition',
        'tab_profile',

        // Compare Plans Screen
        'membership_compare_title',
        'membership_preview_badge',
        'membership_find_your_fit',
        'membership_find_your_fit_desc',
        'billing_monthly',
        'billing_yearly',
        'demo_pricing_disclaimer',
        'paid_coming_soon_note',
        'status_legend_title',
        'legend_included_free',
        'legend_planned_inclusion',
        'legend_not_in_tier',
        'feature_matrix_title',
        'recommended_pro_badge',
        'summary_free_sub',
        'summary_plus_sub',
        'summary_pro_sub',
        'summary_ultra_sub',
        'per_month',
        'per_year',
        'equiv_to',
        'explore_plus',
        'explore_plus_sub',
        'explore_pro',
        'explore_pro_sub',
        'recommended_badge_mixed',
        'explore_ultra',
        'explore_ultra_sub',
        'explore_plan_details_title',
        'paid_notice_footer',

        // Manage Membership Screen
        'manage_membership_title',
        'account_badge',
        'current_plan_heading',
        'current_badge',
        'no_paid_activated',
        'your_free_benefits',
        'everyday_tracking_essentials',
        'benefit_nutrition_logging',
        'benefit_nutrition_logging_sub',
        'benefit_workout_tracking',
        'benefit_workout_tracking_sub',
        'benefit_food_analysis',
        'benefit_food_analysis_sub',
        'benefit_basic_metrics',
        'benefit_basic_metrics_sub',
        'coming_soon_badge',
        'explore_whats_next',
        'explore_whats_next_desc',
        'explore_plans_btn',
        'membership_faq_title',
        'faq_q1',
        'faq_a1',
        'faq_q2',
        'faq_a2',
        'faq_q3',
        'faq_a3',
        'quiet_footer_notice',
      ];

      for (final key in requiredKeys) {
        final enVal = AppTranslations.text(key, const Locale('en'));
        final viVal = AppTranslations.text(key, const Locale('vi'));

        expect(enVal, isNotEmpty, reason: 'Key "$key" should have non-empty EN translation');
        expect(viVal, isNotEmpty, reason: 'Key "$key" should have non-empty VI translation');
        expect(enVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for EN');
        expect(viVal, isNot(equals(key)), reason: 'Key "$key" should not return raw key for VI');
      }
    });

    test('AppTranslations.text falls back to English when locale is unsupported', () {
      expect(
        AppTranslations.text('tab_home', const Locale('fr')),
        equals('Home'),
      );
    });
  });

  group('SamanBottomNavigationBar Localization Switch EN <-> VI', () {
    testWidgets('Toggles all 5 tab labels between English and Vietnamese dynamically', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: SamanBottomNavigationBar(
            currentIndex: 0,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial English State
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(find.text('Trang chủ'), findsNothing);
      expect(find.text('Luyện tập'), findsNothing);
      expect(find.text('Dinh dưỡng'), findsNothing);
      expect(find.text('Hồ sơ'), findsNothing);

      // 2. Switch to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Dinh dưỡng'), findsOneWidget);
      expect(find.text('Hồ sơ'), findsOneWidget);

      expect(find.text('Home'), findsNothing);
      expect(find.text('Workout'), findsNothing);
      expect(find.text('Nutrition'), findsNothing);
      expect(find.text('Profile'), findsNothing);

      // 3. Switch back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Saman'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(find.text('Trang chủ'), findsNothing);
      expect(find.text('Tập luyện'), findsNothing);
    });
  });

  group('ComparePlansScreen Localization Switch EN <-> VI', () {
    testWidgets('Toggles headers, badges, pricing, and exploration rows between EN and VI', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify English
      expect(find.text(AppTranslations.text('membership_compare_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_preview_badge', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_find_your_fit', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_monthly', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_yearly', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('demo_pricing_disclaimer', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('status_legend_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_included_free', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_planned_inclusion', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_not_in_tier', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plan_details_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plus', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_pro', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_ultra', const Locale('en'))), findsOneWidget);

      // 2. Switch to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text(AppTranslations.text('membership_compare_title', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_preview_badge', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_find_your_fit', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_monthly', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_yearly', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('demo_pricing_disclaimer', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('status_legend_title', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_included_free', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_planned_inclusion', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('legend_not_in_tier', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plan_details_title', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plus', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_pro', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_ultra', const Locale('vi'))), findsOneWidget);

      // English titles should no longer exist
      expect(find.text(AppTranslations.text('membership_find_your_fit', const Locale('en'))), findsNothing);
      expect(find.text(AppTranslations.text('membership_compare_title', const Locale('en'))), findsNothing);

      // 3. Switch back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text(AppTranslations.text('membership_compare_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_find_your_fit', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_compare_title', const Locale('vi'))), findsNothing);
    });
  });

  group('ManageMembershipScreen Localization Switch EN <-> VI', () {
    testWidgets('Toggles current plan, benefits, discovery card, and FAQs between EN and VI', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const ManageMembershipScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify English
      expect(find.text(AppTranslations.text('manage_membership_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('account_badge', const Locale('en')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('current_plan_heading', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('no_paid_activated', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('your_free_benefits', const Locale('en')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('coming_soon_badge', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_whats_next', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plans_btn', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_faq_title', const Locale('en')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('faq_q1', const Locale('en'))), findsOneWidget);

      // 2. Switch to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      expect(find.text(AppTranslations.text('manage_membership_title', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('account_badge', const Locale('vi')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('current_plan_heading', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('no_paid_activated', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('your_free_benefits', const Locale('vi')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('coming_soon_badge', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_whats_next', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('explore_plans_btn', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('membership_faq_title', const Locale('vi')).toUpperCase()), findsOneWidget);
      expect(find.text(AppTranslations.text('faq_q1', const Locale('vi'))), findsOneWidget);

      // English titles should no longer exist
      expect(find.text(AppTranslations.text('manage_membership_title', const Locale('en'))), findsNothing);
      expect(find.text(AppTranslations.text('no_paid_activated', const Locale('en'))), findsNothing);

      // 3. Switch back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text(AppTranslations.text('manage_membership_title', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('no_paid_activated', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('manage_membership_title', const Locale('vi'))), findsNothing);
    });
  });

  group('State and Route Preservation Across EN <-> VI <-> EN Transitions', () {
    testWidgets('Preserves selected billing period state across language changes without resetting to default', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildLocalizedTestApp(
          container: container,
          child: const ComparePlansScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Default state is Monthly
      expect(container.read(billingPeriodProvider), equals(BillingPeriod.monthly));

      // 2. User selects Yearly
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(container.read(billingPeriodProvider), equals(BillingPeriod.yearly));

      // 3. Switch language to Vietnamese
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      // State MUST be preserved as Yearly (not reset to default Monthly)
      expect(container.read(billingPeriodProvider), equals(BillingPeriod.yearly));
      expect(find.text(AppTranslations.text('billing_yearly', const Locale('vi'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_monthly', const Locale('vi'))), findsOneWidget);

      // 4. Switch language back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      // State MUST STILL be preserved as Yearly
      expect(container.read(billingPeriodProvider), equals(BillingPeriod.yearly));
      expect(find.text(AppTranslations.text('billing_yearly', const Locale('en'))), findsOneWidget);
      expect(find.text(AppTranslations.text('billing_monthly', const Locale('en'))), findsOneWidget);
    });

    testWidgets('Preserves active navigation route and backstack across language changes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final locale = ref.watch(languageProvider);
              return MaterialApp(
                navigatorKey: navKey,
                locale: locale,
                supportedLocales: const [Locale('en'), Locale('vi')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (ctx) => ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).push(
                            MaterialPageRoute(
                              builder: (_) => const ComparePlansScreen(),
                            ),
                          );
                        },
                        child: const Text('Open Compare'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial route is Home with button
      expect(find.text('Open Compare'), findsOneWidget);
      expect(find.byType(ComparePlansScreen), findsNothing);

      // 2. Navigate to ComparePlansScreen
      await tester.tap(find.text('Open Compare'));
      await tester.pumpAndSettle();

      expect(find.byType(ComparePlansScreen), findsOneWidget);
      expect(find.text('Compare plans'), findsOneWidget);

      // 3. Switch language to Vietnamese while on ComparePlansScreen
      await container.read(languageProvider.notifier).changeLanguage('vi');
      await tester.pumpAndSettle();

      // Screen must NOT be popped, reset, or unmounted
      expect(find.byType(ComparePlansScreen), findsOneWidget);
      expect(find.text('So sánh các gói'), findsOneWidget);

      // 4. Switch back to English
      await container.read(languageProvider.notifier).changeLanguage('en');
      await tester.pumpAndSettle();

      expect(find.byType(ComparePlansScreen), findsOneWidget);
      expect(find.text('Compare plans'), findsOneWidget);

      // 5. Back navigation safely pops to original screen
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(ComparePlansScreen), findsNothing);
      expect(find.text('Open Compare'), findsOneWidget);
    });
  });
}
