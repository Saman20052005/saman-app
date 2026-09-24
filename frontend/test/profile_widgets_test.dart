import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/profile/widgets/profile_widgets.dart';

void main() {
  group('ProgressSnapshotCard Unit & Widget Tests', () {
    testWidgets('no fake numeric defaults (workoutsCount, streakDays, adherencePercent default to null)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(),
          ),
        ),
      );

      // Verify no 24, 7d, 82% fabricated values appear
      expect(find.text('24'), findsNothing);
      expect(find.text('7d'), findsNothing);
      expect(find.text('82%'), findsNothing);

      // Default unavailable label "—" is rendered 3 times for the 3 null metrics
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('null metrics display unavailable label while zero metrics display zero values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              workoutsCount: 0,
              streakDays: 0,
              adherencePercent: 0,
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('0d'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('large metrics do not crash or overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              workoutsCount: 999999,
              streakDays: 12345,
              adherencePercent: 100,
            ),
          ),
        ),
      );

      expect(find.text('999999'), findsOneWidget);
      expect(find.text('12345d'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('null onViewProgressTap produces no InkWell, chevron, or button semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              onViewProgressTap: null,
            ),
          ),
        ),
      );

      expect(find.text('View progress'), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('onViewProgressTap fires callback exactly once per tap and has min 48x48 target', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              onViewProgressTap: () => tapCount++,
            ),
          ),
        ),
      );

      final inkWellFinder = find.widgetWithText(InkWell, 'View progress');
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(inkWellFinder);
      await tester.pump();
      expect(tapCount, equals(1));
    });
  });

  group('PersonalIdentityCard Unit & Widget Tests', () {
    testWidgets('no fake plan or memberSince defaults', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'John Doe',
              userEmail: 'john@example.com',
            ),
          ),
        ),
      );

      expect(find.text('Free plan'), findsNothing);
      expect(find.text('FREE PLAN'), findsNothing);
      expect(find.text('Member since 2026'), findsNothing);
    });

    testWidgets('displays plan and memberSince only when supplied', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'John Doe',
              userEmail: 'john@example.com',
              planLabel: 'Pro Plan',
              memberSince: 'Member since 2024',
            ),
          ),
        ),
      );

      expect(find.text('PRO PLAN'), findsOneWidget);
      expect(find.text('Member since 2024'), findsOneWidget);
    });

    testWidgets('handles empty name, null/partial identity safely without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: '',
              userEmail: '',
            ),
          ),
        ),
      );

      expect(find.text('Athlete'), findsOneWidget);
      expect(find.text('AT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('initials logic: single-word, multi-word, Unicode Vietnamese names', (tester) async {
      // 1-word name
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'Alice',
              userEmail: 'a@example.com',
            ),
          ),
        ),
      );
      expect(find.text('AL'), findsOneWidget);

      // Multi-word name
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'John Michael Doe',
              userEmail: 'j@example.com',
            ),
          ),
        ),
      );
      expect(find.text('JD'), findsOneWidget);

      // Vietnamese Unicode name
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'Nguyễn Văn Ân',
              userEmail: 'n@example.com',
            ),
          ),
        ),
      );
      expect(find.text('NÂ'), findsOneWidget);
    });

    testWidgets('onEditProfileTap fires callback once and has 48x48 touch target', (tester) async {
      int editTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'Jane Doe',
              userEmail: 'jane@example.com',
              onEditProfileTap: () => editTaps++,
            ),
          ),
        ),
      );

      final editButtonFinder = find.byWidgetPredicate(
        (w) => w is InkWell && w.child is SizedBox && (w.child as SizedBox).width == 48,
      );
      expect(editButtonFinder, findsOneWidget);

      final Size size = tester.getSize(editButtonFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(editButtonFinder);
      await tester.pump();
      expect(editTaps, equals(1));
    });

    testWidgets('null onEditProfileTap renders no active edit button or InkWell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PersonalIdentityCard(
              userName: 'Jane Doe',
              userEmail: 'jane@example.com',
              onEditProfileTap: null,
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('SamanPlusCard Unit & Widget Tests', () {
    testWidgets('null onExploreTap has no enabled button semantics, no chevron, no InkWell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanPlusCard(
              onExploreTap: null,
            ),
          ),
        ),
      );

      expect(find.text('Explore Saman+'), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('comingSoonLabel renders when onExploreTap is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanPlusCard(
              onExploreTap: null,
              comingSoonLabel: 'Sắp ra mắt',
            ),
          ),
        ),
      );

      expect(find.text('Sắp ra mắt'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('enabled onExploreTap has min 48x48 hit target and fires callback once', (tester) async {
      int exploreTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanPlusCard(
              onExploreTap: () => exploreTaps++,
            ),
          ),
        ),
      );

      final inkWellFinder = find.widgetWithText(InkWell, 'Explore Saman+');
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(inkWellFinder);
      await tester.pump();
      expect(exploreTaps, equals(1));
    });
  });

  group('ProfileHeader Unit & Widget Tests', () {
    testWidgets('settings button has min 48x48 hit target and fires callback once', (tester) async {
      int settingsTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileHeader(
              onSettingsTap: () => settingsTaps++,
            ),
          ),
        ),
      );

      final settingsFinder = find.byType(InkWell);
      expect(settingsFinder, findsOneWidget);

      final Size size = tester.getSize(settingsFinder);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(settingsFinder);
      await tester.pump();
      expect(settingsTaps, equals(1));
    });

    testWidgets('null onSettingsTap hides settings button and creates no InkWell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileHeader(
              onSettingsTap: null,
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });
  });

  group('ProfileNavRow Unit & Widget Tests', () {
    testWidgets('actionable nav row shows chevron, supports 52px height, and fires callback once', (tester) async {
      int navTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileNavRow(
              title: 'Account Settings',
              onTap: () => navTaps++,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      final inkWellFinder = find.widgetWithText(InkWell, 'Account Settings');
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.height, greaterThanOrEqualTo(52.0));

      await tester.tap(inkWellFinder);
      await tester.pump();
      expect(navTaps, equals(1));
    });

    testWidgets('non-actionable nav row has no chevron (by default) and no InkWell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileNavRow(
              title: 'App Version',
              value: 'v1.0.0',
              onTap: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('App Version'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
    });
  });

  group('ProfileSectionGroup Unit & Widget Tests', () {
    testWidgets('renders children and handles null/empty title gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileSectionGroup(
              title: null,
              children: [
                Text('Child 1'),
                Text('Child 2'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Child 1'), findsOneWidget);
      expect(find.text('Child 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LogoutRow Unit & Widget Tests', () {
    testWidgets('actionable logout row has min 48x48 target and fires callback once', (tester) async {
      int logoutTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogoutRow(
              onTap: () => logoutTaps++,
            ),
          ),
        ),
      );

      final inkWellFinder = find.widgetWithText(InkWell, 'Log out');
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.height, greaterThanOrEqualTo(48.0));
      expect(size.width, greaterThanOrEqualTo(48.0));

      await tester.tap(inkWellFinder);
      await tester.pump();
      expect(logoutTaps, equals(1));
    });

    testWidgets('null onTap logout row has no InkWell and disabled semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LogoutRow(
              onTap: null,
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
    });
  });

  group('Rebuild & Dispose Safety', () {
    testWidgets('rebuild with updated data renders new values cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              workoutsCount: 10,
            ),
          ),
        ),
      );

      expect(find.text('10'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressSnapshotCard(
              workoutsCount: 20,
            ),
          ),
        ),
      );

      expect(find.text('10'), findsNothing);
      expect(find.text('20'), findsOneWidget);
    });
  });
}
