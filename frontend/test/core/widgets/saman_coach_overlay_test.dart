import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/core/widgets/coach_marks/coach_tour_service.dart';
import 'package:health_ai_app/core/widgets/coach_marks/coach_tour_step.dart';
import 'package:health_ai_app/core/widgets/coach_marks/saman_coach_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    CoachTourService.isTestBypassEnabled = false;
    SamanCoachOverlay.dismissActive();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    SamanCoachOverlay.dismissActive();
  });

  group('CoachTourService', () {
    test('shouldShow defaults to true, markSeen sets false, resetAll restores true',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);

      for (final screenId in CoachTourService.allScreenIds) {
        expect(await service.shouldShow(screenId), isTrue);
      }

      await service.markSeen(CoachTourService.homeScreenId);
      expect(await service.shouldShow(CoachTourService.homeScreenId), isFalse);
      expect(
        await service.shouldShow(CoachTourService.nutritionScreenId),
        isTrue,
      );
      expect(
        await service.shouldShow(CoachTourService.workoutScreenId),
        isTrue,
      );

      await service.markSeen(CoachTourService.nutritionScreenId);
      await service.markSeen(CoachTourService.workoutScreenId);
      await service.markSeen('custom_extra_v1');

      await service.resetAll();

      for (final screenId in CoachTourService.allScreenIds) {
        expect(await service.shouldShow(screenId), isTrue);
      }
      expect(await service.shouldShow('custom_extra_v1'), isTrue);
    });
  });

  group('SamanCoachOverlay', () {
    Widget buildTestHost({
      required GlobalKey hostKey,
      required GlobalKey key1,
      required GlobalKey key2,
      required GlobalKey key3,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Column(
              key: hostKey,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  key: key1,
                  width: 120,
                  height: 44,
                  color: Colors.teal,
                  child: const Text('Target 1'),
                ),
                Container(
                  key: key2,
                  width: 140,
                  height: 44,
                  color: Colors.amber,
                  child: const Text('Target 2'),
                ),
                Container(
                  key: key3,
                  width: 120,
                  height: 44,
                  color: Colors.blue,
                  child: const Text('Target 3'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('3-step tour advances 1/3 -> 2/3 -> 3/3 (Xong) and marks seen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);
      final hostKey = GlobalKey();
      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();

      await tester.pumpWidget(
        buildTestHost(hostKey: hostKey, key1: key1, key2: key2, key3: key3),
      );

      final steps = [
        CoachTourStep(
          targetKey: key1,
          title: 'Bước 1',
          description: 'Mô tả bước 1',
        ),
        CoachTourStep(
          targetKey: key2,
          title: 'Bước 2',
          description: 'Mô tả bước 2',
        ),
        CoachTourStep(
          targetKey: key3,
          title: 'Bước 3',
          description: 'Mô tả bước 3',
        ),
      ];

      final shown = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.homeScreenId,
        steps: steps,
        service: service,
      );
      expect(shown, isTrue);
      expect(SamanCoachOverlay.isShowing, isTrue);

      await tester.pumpAndSettle();

      // Re-entrancy guard prevents opening a second overlay.
      final secondAttempt = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.homeScreenId,
        steps: steps,
        service: service,
        forceShow: true,
      );
      expect(secondAttempt, isFalse);

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Bước 1'), findsOneWidget);
      expect(find.text('Tiếp theo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('Bước 2'), findsOneWidget);
      expect(find.text('Tiếp theo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('Bước 3'), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_next_button')));
      await tester.pumpAndSettle();

      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(find.text('3/3'), findsNothing);
      expect(await service.shouldShow(CoachTourService.homeScreenId), isFalse);

      final shownAgain = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.homeScreenId,
        steps: steps,
        service: service,
      );
      expect(shownAgain, isFalse);
      expect(SamanCoachOverlay.isShowing, isFalse);
    });

    testWidgets('skip button closes overlay immediately and marks seen',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);
      final hostKey = GlobalKey();
      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();

      await tester.pumpWidget(
        buildTestHost(hostKey: hostKey, key1: key1, key2: key2, key3: key3),
      );

      final shown = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.nutritionScreenId,
        steps: [
          CoachTourStep(
            targetKey: key1,
            title: 'Bước 1',
            description: 'Mô tả 1',
          ),
          CoachTourStep(
            targetKey: key2,
            title: 'Bước 2',
            description: 'Mô tả 2',
          ),
          CoachTourStep(
            targetKey: key3,
            title: 'Bước 3',
            description: 'Mô tả 3',
          ),
        ],
        service: service,
      );
      expect(shown, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('1/3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('coach_tour_skip_button')));
      await tester.pumpAndSettle();

      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(find.text('1/3'), findsNothing);
      expect(
        await service.shouldShow(CoachTourService.nutritionScreenId),
        isFalse,
      );
    });

    testWidgets('skips unmounted GlobalKeys safely and aborts if all unmounted',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final service = CoachTourService(prefs: prefs);
      final hostKey = GlobalKey();
      final mountedKey1 = GlobalKey();
      final mountedKey2 = GlobalKey();
      final unusedKey3 = GlobalKey();
      final unmountedKey = GlobalKey();

      await tester.pumpWidget(
        buildTestHost(
          hostKey: hostKey,
          key1: mountedKey1,
          key2: mountedKey2,
          key3: unusedKey3,
        ),
      );

      // All unmounted -> returns false, no overlay, not marked seen.
      final noneShown = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.workoutScreenId,
        steps: [
          CoachTourStep(
            targetKey: unmountedKey,
            title: 'Missing',
            description: 'Not mounted',
          ),
        ],
        service: service,
      );
      expect(noneShown, isFalse);
      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(
        await service.shouldShow(CoachTourService.workoutScreenId),
        isTrue,
      );

      // 1 unmounted + 2 mounted -> shows 1/2 and 2/2 cleanly.
      final partialShown = await SamanCoachOverlay.showIfNeeded(
        context: hostKey.currentContext!,
        screenId: CoachTourService.workoutScreenId,
        steps: [
          CoachTourStep(
            targetKey: unmountedKey,
            title: 'Missing',
            description: 'Not mounted',
          ),
          CoachTourStep(
            targetKey: mountedKey1,
            title: 'Hợp lệ 1',
            description: 'Mô tả 1',
          ),
          CoachTourStep(
            targetKey: mountedKey2,
            title: 'Hợp lệ 2',
            description: 'Mô tả 2',
          ),
        ],
        service: service,
      );
      expect(partialShown, isTrue);
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Hợp lệ 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Hợp lệ 2'), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coach_tour_next_button')));
      await tester.pumpAndSettle();

      expect(SamanCoachOverlay.isShowing, isFalse);
      expect(
        await service.shouldShow(CoachTourService.workoutScreenId),
        isFalse,
      );
    });
  });
}
