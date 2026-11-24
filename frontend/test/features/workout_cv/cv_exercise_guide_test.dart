import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_exercise_guide_data.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/workout_cv_exercise_registry.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_exercise_guide_sheet.dart';

void main() {
  group('CvExerciseGuideData', () {
    test('resolves all 5 core exercises with specific specs and >= 4 blind spots',
        () {
      final cases = <String, CvExerciseModule>{
        'pull-up': CvExerciseModule.pullUp,
        'lat-pulldown': CvExerciseModule.latPulldown,
        'barbell-back-squat': CvExerciseModule.squat,
        'goblet-squat': CvExerciseModule.squat,
        'push-up': CvExerciseModule.pushUp,
        'db-bicep-curl': CvExerciseModule.bicepCurl,
      };

      for (final entry in cases.entries) {
        final spec = CvExerciseGuideData.forExercise(slug: entry.key);
        expect(spec.module, entry.value, reason: 'slug: ${entry.key}');
        expect(spec.supportedAngles.length, 3, reason: 'slug: ${entry.key}');
        expect(
          spec.supportedAngles
              .where((a) => a.supportLevel == CvAngleSupportLevel.best)
              .length,
          1,
          reason: 'slug: ${entry.key} should have 1 best angle',
        );
        expect(spec.cameraPlacementVi, isNotEmpty);
        expect(spec.cameraPlacementEn, isNotEmpty);
        expect(spec.lightingTipVi, isNotEmpty);
        expect(spec.lightingTipEn, isNotEmpty);
        expect(spec.blindSpotsVi.length, greaterThanOrEqualTo(4));
        expect(spec.blindSpotsEn.length, greaterThanOrEqualTo(4));
      }
    });

    test('push-up marks 0° as notRecommended and provides non-empty warnings',
        () {
      final spec = CvExerciseGuideData.forExercise(slug: 'push-up');

      final zeroAngle =
          spec.supportedAngles.firstWhere((a) => a.angleCode == '0°');
      expect(zeroAngle.supportLevel, CvAngleSupportLevel.notRecommended);

      final sideAngle =
          spec.supportedAngles.firstWhere((a) => a.angleCode == '90°');
      expect(sideAngle.supportLevel, CvAngleSupportLevel.best);

      expect(spec.angleWarningVi, isNotNull);
      expect(spec.angleWarningVi!.trim(), isNotEmpty);
      expect(spec.angleWarningEn, isNotNull);
      expect(spec.angleWarningEn!.trim(), isNotEmpty);
    });

    test('provides fallback spec for other CV exercises and unknown slugs', () {
      final rowSpec =
          CvExerciseGuideData.forExercise(slug: 'bent-over-barbell-row');
      expect(rowSpec.module, CvExerciseModule.row);
      expect(rowSpec.blindSpotsVi.length, greaterThanOrEqualTo(4));
      expect(rowSpec.blindSpotsEn.length, greaterThanOrEqualTo(4));

      final pressSpec =
          CvExerciseGuideData.forExercise(slug: 'barbell-overhead-press');
      expect(pressSpec.module, CvExerciseModule.overheadPress);

      final plankSpec = CvExerciseGuideData.forExercise(slug: 'plank');
      expect(plankSpec.module, CvExerciseModule.plankHold);

      final unknownSpec = CvExerciseGuideData.forExercise(slug: 'unknown-ex');
      expect(unknownSpec.module, isNull);
      expect(unknownSpec.supportedAngles, isNotEmpty);
      expect(unknownSpec.blindSpotsVi.length, greaterThanOrEqualTo(4));
    });
  });

  group('CvExerciseGuideSheet', () {
    void setSmallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<bool?> openSheetAndPump(
      WidgetTester tester, {
      required ThemeData theme,
      required String exerciseId,
      required String exerciseSlug,
      String? exerciseName,
      required bool isVietnamese,
      required bool isPreCameraEntry,
    }) async {
      bool? sheetResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    sheetResult = await showCvExerciseGuideSheet(
                      context,
                      exerciseId: exerciseId,
                      exerciseSlug: exerciseSlug,
                      exerciseName: exerciseName,
                      isVietnamese: isVietnamese,
                      isPreCameraEntry: isPreCameraEntry,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return sheetResult;
    }

    testWidgets(
      'renders push-up guide in Dark theme (VI) on 360x640 without overflow and returns true on confirm',
      (tester) async {
        setSmallViewport(tester);

        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await showCvExerciseGuideSheet(
                        context,
                        exerciseId: 'push-up',
                        exerciseSlug: 'push-up',
                        isVietnamese: true,
                        isPreCameraEntry: true,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Hít đất (Push-up)'), findsOneWidget);
        expect(find.text('Góc quay hỗ trợ'), findsOneWidget);
        expect(find.text('Cách đặt máy & Ánh sáng'), findsOneWidget);
        expect(find.text('Điểm mù AI (Lưu ý trung thực)'), findsOneWidget);
        expect(
          find.textContaining('Không nên quay chính diện 0°'),
          findsOneWidget,
        );

        final confirmButton =
            find.byKey(const ValueKey('cv_exercise_guide_confirm_button'));
        expect(confirmButton, findsOneWidget);
        expect(find.text('Đã hiểu, tiếp tục'), findsOneWidget);

        await tester.tap(confirmButton);
        await tester.pumpAndSettle();
        expect(result, isTrue);
      },
    );

    testWidgets(
      'renders push-up guide in Light theme (EN) on 360x640 without overflow',
      (tester) async {
        setSmallViewport(tester);

        await openSheetAndPump(
          tester,
          theme: ThemeData.light(),
          exerciseId: 'push-up',
          exerciseSlug: 'push-up',
          isVietnamese: false,
          isPreCameraEntry: true,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Push-up'), findsOneWidget);
        expect(find.text('Supported Camera Angles'), findsOneWidget);
        expect(find.text('Camera Placement & Lighting'), findsOneWidget);
        expect(find.text('AI Blind Spots (Honest Limits)'), findsOneWidget);
        expect(find.textContaining('Avoid front-facing 0°'), findsOneWidget);
        expect(find.text('Got it, continue'), findsOneWidget);
      },
    );

    testWidgets(
      'renders squat guide in Light & Dark theme (VI/EN) with close button returning true',
      (tester) async {
        setSmallViewport(tester);

        for (final isDark in [false, true]) {
          for (final isVi in [true, false]) {
            bool? result;
            await tester.pumpWidget(
              MaterialApp(
                theme: isDark ? ThemeData.dark() : ThemeData.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          result = await showCvExerciseGuideSheet(
                            context,
                            exerciseId: 'barbell-back-squat',
                            exerciseSlug: 'barbell-back-squat',
                            exerciseName: isVi ? 'Squat Tạ Đòn' : 'Back Squat',
                            isVietnamese: isVi,
                            isPreCameraEntry: false,
                          );
                        },
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            );

            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(
              find.text(isVi ? 'Squat Tạ Đòn' : 'Back Squat'),
              findsOneWidget,
            );
            expect(
              find.text(isVi ? 'Đóng' : 'Close'),
              findsOneWidget,
            );

            await tester.tap(
              find.byKey(const ValueKey('cv_exercise_guide_confirm_button')),
            );
            await tester.pumpAndSettle();
            expect(result, isTrue);
          }
        }
      },
    );
  });
}
