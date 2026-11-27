import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/core/widgets/saman_tier_avatar.dart';
import 'package:health_ai_app/features/membership/domain/models/membership_plan.dart';
import 'package:health_ai_app/features/membership/presentation/providers/membership_providers.dart';

void main() {
  group('SamanTierAvatar', () {
    for (final entry in const <(MembershipTier, String)>[
      (MembershipTier.free, 'FREE'),
      (MembershipTier.plus, 'PLUS'),
      (MembershipTier.pro, 'PRO'),
      (MembershipTier.ultra, 'ULTRA'),
    ]) {
      testWidgets('renders ${entry.$2} badge and initials without overflow',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: Scaffold(
                body: Center(
                  child: SamanTierAvatar(
                    name: 'QA Cloud',
                    tier: entry.$1,
                    size: 52,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('QC'), findsOneWidget);
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          find.byKey(ValueKey('saman_tier_badge_${entry.$1.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'renders compact sizes (32px, 34px) and topCenter position with 0 overflow',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SamanTierAvatar(
                    name: 'QA Cloud',
                    tier: MembershipTier.ultra,
                    size: 32,
                  ),
                  SamanTierAvatar(
                    name: 'QA Cloud',
                    tier: MembershipTier.pro,
                    size: 34,
                  ),
                  SamanTierAvatar(
                    name: 'QA Cloud',
                    tier: MembershipTier.plus,
                    size: 52,
                    badgePosition: SamanTierBadgePosition.topCenter,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('ULTRA'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('PLUS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reads tier dynamically from currentMembershipTierProvider',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMembershipTierProvider
                .overrideWithValue(MembershipTier.ultra),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SamanTierAvatar(
                  name: 'QA Cloud',
                  size: 52,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('ULTRA'), findsOneWidget);
      expect(find.text('QC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
