import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/features/membership/data/models/account_membership_dto.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';
import 'package:health_ai_app/features/membership/presentation/screens/manage_membership_screen.dart';
import 'package:health_ai_app/features/membership/presentation/screens/membership_overview_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/profile/widgets/membership_banner_card.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/widgets/app_logo.dart';

Widget _buildWrapper({
  required Widget child,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.dark,
  AccountMembershipState? membershipState,
  ProfileState? profileState,
}) {
  return ProviderScope(
    overrides: [
      if (membershipState != null)
        accountMembershipProvider.overrideWith((ref) => _StaticAccountNotifier(membershipState)),
      if (profileState != null)
        profileProvider.overrideWith((ref) => _StaticProfileNotifier(profileState)),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: Scaffold(
        backgroundColor: themeMode == ThemeMode.dark ? const Color(0xFF0C0D0E) : Colors.white,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _StaticAccountNotifier extends StateNotifier<AccountMembershipState>
    implements AccountMembershipNotifier {
  _StaticAccountNotifier(super.state);

  @override
  String? get activeAccountId => state.accountId;

  @override
  Future<AccountMembershipState> loadMembership({String? accountId}) async => state;

  @override
  void reset() {}

  @override
  void setActiveAccount(String? accountId) {}
}

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  Future<void> fetchProfile() async {}

  @override
  Future<bool> saveProfile(ProfileEntity profile) async => true;

  @override
  Future<void> updateField<T>(String field, T value) async {}
}

const _dummyProfile = ProfileEntity(
  age: 21,
  height: 171.0,
  weight: 68.0,
  gender: Gender.male,
  activityCanonical: 'high',
  goal: Goal.gain_muscle,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Saman Signature Membership Banner Card Tests', () {
    testWidgets('1. Preview Mode (English) renders official S logo, ivory text, no sparkles', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: AccountMembershipState.demoBaseline(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Check title
      expect(find.text('Saman Membership'), findsOneWidget);
      // Check preview badge
      expect(find.text('PREVIEW'), findsOneWidget);
      // Check description
      expect(find.text('Explore Plus, Pro, and Ultra'), findsOneWidget);
      // Check CTA
      expect(find.text('Explore plans'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // Verify no sparkles icon
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      // Verify official AppLogo is rendered
      expect(find.byType(AppLogo), findsOneWidget);

      // Verify semantics
      final semantics = tester.getSemantics(find.byKey(const Key('profile_membership_banner_card')));
      expect(semantics.label, contains('Saman Membership'));
      expect(semantics.label, contains('PREVIEW'));
    });

    testWidgets('2. Preview Mode (Vietnamese) renders correct localized copy', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: AccountMembershipState.demoBaseline(),
          locale: const Locale('vi'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('Xem trước'), findsOneWidget);
      expect(find.text('Tìm hiểu các gói Plus, Pro và Ultra'), findsOneWidget);
      expect(find.text('Khám phá các gói'), findsOneWidget);
    });

    testWidgets('3. Confirmed Free tier renders "View upgrade options"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final confirmedFree = AccountMembershipState.known(
        AccountMembershipDto.defaultFree('athlete_01'),
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: confirmedFree,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('View upgrade options'), findsOneWidget);
    });

    testWidgets('4. Confirmed Free tier (Vietnamese) renders "Xem gói nâng cấp"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final confirmedFree = AccountMembershipState.known(
        AccountMembershipDto.defaultFree('athlete_01'),
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: confirmedFree,
          locale: const Locale('vi'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('Xem gói nâng cấp'), findsOneWidget);
    });

    testWidgets('5. Active Paid tier renders real plan tier and "View your plan"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final activePlus = AccountMembershipState.known(
        const AccountMembershipDto(
          userId: 'athlete_01',
          tier: MembershipTier.plus,
          status: 'active',
          isActiveSubscription: true,
        ),
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: activePlus,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('PLUS'), findsOneWidget);
      expect(find.text('Active plan: Plus'), findsOneWidget);
      expect(find.text('View your plan'), findsOneWidget);
    });

    testWidgets('6. Active Paid tier (Vietnamese) renders "Xem gói của bạn"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final activeUltra = AccountMembershipState.known(
        const AccountMembershipDto(
          userId: 'athlete_01',
          tier: MembershipTier.ultra,
          status: 'active',
          isActiveSubscription: true,
        ),
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(),
          membershipState: activeUltra,
          locale: const Locale('vi'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('ULTRA'), findsOneWidget);
      expect(find.text('Gói đang hoạt động: Ultra'), findsOneWidget);
      expect(find.text('Xem gói của bạn'), findsOneWidget);
    });

    testWidgets('7. Update Signal renders "Updated" / "Có cập nhật" badge alongside Preview', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildWrapper(
          child: const MembershipBannerCard(
            hasUpdate: true,
            updateMessage: 'New Gemini 3.8 Intelligence',
          ),
          membershipState: AccountMembershipState.demoBaseline(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Both badges must be visible
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('New Gemini 3.8 Intelligence'), findsOneWidget);
    });

    testWidgets('8. Narrow screen (320px) and 200% text scale render without overflow', (tester) async {
      // Small screen test
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildWrapper(
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2.0),
            ),
            child: const MembershipBannerCard(
              hasUpdate: true,
              updateMessage: 'Cập nhật phân tích món ăn thông minh với Saman Plus',
            ),
          ),
          membershipState: AccountMembershipState.demoBaseline(),
          locale: const Locale('vi'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Saman Membership'), findsOneWidget);
      expect(find.text('Xem trước'), findsOneWidget);
      expect(find.text('Có cập nhật'), findsOneWidget);
    });

    testWidgets('9. Navigation routes to MembershipOverviewScreen when preview / free', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildWrapper(
          profileState: ProfileState(
            status: ProfileStatus.ready,
            profile: _dummyProfile,
          ),
          membershipState: AccountMembershipState.demoBaseline(),
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final bannerFinder = find.byKey(const Key('profile_membership_banner_card'));
      expect(bannerFinder, findsOneWidget);

      await tester.tap(bannerFinder);
      await tester.pumpAndSettle();

      expect(find.byType(MembershipOverviewScreen), findsOneWidget);

      // Back to Profile
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('10. Navigation routes to ManageMembershipScreen when user has active paid plan', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final activePlan = AccountMembershipState.known(
        const AccountMembershipDto(
          userId: 'athlete_01',
          tier: MembershipTier.pro,
          status: 'active',
          isActiveSubscription: true,
        ),
      );

      await tester.pumpWidget(
        _buildWrapper(
          profileState: ProfileState(
            status: ProfileStatus.ready,
            profile: _dummyProfile,
          ),
          membershipState: activePlan,
          child: const ProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final bannerFinder = find.byKey(const Key('profile_membership_banner_card'));
      expect(bannerFinder, findsOneWidget);

      await tester.tap(bannerFinder);
      await tester.pumpAndSettle();

      expect(find.byType(ManageMembershipScreen), findsOneWidget);
    });
  });
}

