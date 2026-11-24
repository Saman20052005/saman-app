import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/workout_cv/domain/services/cv_hardware_radar_service.dart';
import 'package:health_ai_app/features/workout_cv/presentation/widgets/cv_hardware_radar_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHardwareProbe implements CvHardwareProbe {
  _FakeHardwareProbe({
    required this.info,
    required this.benchmarks,
  });

  final Map<String, dynamic> info;
  final List<Map<String, dynamic>> benchmarks;

  int infoCalls = 0;
  int benchmarkCalls = 0;

  @override
  Future<Map<String, dynamic>?> getDeviceHardwareInfo() async {
    infoCalls++;
    return info;
  }

  @override
  Future<Map<String, dynamic>?> runPoseBenchmark({int frameCount = 12}) async {
    final index = benchmarkCalls < benchmarks.length
        ? benchmarkCalls
        : benchmarks.length - 1;
    benchmarkCalls++;
    return benchmarks[index];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('CvHardwareRadarService.classify', () {
    test('classifies >= 15 FPS with >= 3072 MB RAM as optimal', () {
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 15.0,
          totalRamMb: 3072,
        ),
        CvHardwareTier.optimal,
      );
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 24.5,
          totalRamMb: 8192,
        ),
        CvHardwareTier.optimal,
      );
    });

    test('classifies >= 15 FPS with unreadable RAM (0 MB) as optimal', () {
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 18.0,
          totalRamMb: 0,
        ),
        CvHardwareTier.optimal,
      );
    });

    test('classifies 8.0..14.99 FPS as standard', () {
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 8.0,
          totalRamMb: 4096,
        ),
        CvHardwareTier.standard,
      );
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 14.2,
          totalRamMb: 6144,
        ),
        CvHardwareTier.standard,
      );
    });

    test('classifies >= 15 FPS with low RAM (< 3072 MB) as standard', () {
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 19.5,
          totalRamMb: 2048,
        ),
        CvHardwareTier.standard,
      );
    });

    test('classifies < 8.0 FPS as limited', () {
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 7.9,
          totalRamMb: 8192,
        ),
        CvHardwareTier.limited,
      );
      expect(
        CvHardwareRadarService.classify(
          measuredFps: 4.5,
          totalRamMb: 2048,
        ),
        CvHardwareTier.limited,
      );
    });
  });

  group('CvHardwareRadarService caching & acknowledgement', () {
    test('shouldShowRadarSheet lifecycle before and after markAcknowledged',
        () async {
      final probe = _FakeHardwareProbe(
        info: const <String, dynamic>{
          'deviceModel': 'Pixel 7',
          'manufacturer': 'Google',
          'socHardware': 'Tensor G2',
          'totalRamMb': 8192,
          'cpuCores': 8,
          'androidSdk': 34,
        },
        benchmarks: const <Map<String, dynamic>>[
          <String, dynamic>{
            'measuredFps': 18.4,
            'avgInferenceMs': 54.3,
            'framesRun': 12,
          },
        ],
      );
      final service = CvHardwareRadarService(probe: probe);

      expect(await service.shouldShowRadarSheet(), isTrue);
      expect(await service.loadCachedReport(), isNull);

      final report = await service.runEvaluation();
      expect(report.tier, CvHardwareTier.optimal);
      expect(report.measuredFps, 18.4);
      expect(report.totalRamMb, 8192);
      expect(report.acknowledged, isFalse);

      // Cached but not yet acknowledged -> still should show
      expect(await service.shouldShowRadarSheet(), isTrue);

      final cached = await service.loadCachedReport();
      expect(cached, isNotNull);
      expect(cached!.deviceModel, 'Pixel 7');
      expect(cached.acknowledged, isFalse);

      final acked = await service.markAcknowledged(report);
      expect(acked.acknowledged, isTrue);
      expect(await service.shouldShowRadarSheet(), isFalse);

      final cachedAfterAck = await service.loadCachedReport();
      expect(cachedAfterAck?.acknowledged, isTrue);
    });
  });

  group('CvHardwareRadarSheet widget tests', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required ThemeData theme,
      required bool isVietnamese,
      required CvHardwareRadarService service,
      ValueChanged<bool?>? onPopped,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open_radar_btn'),
                onPressed: () async {
                  final res = await showCvHardwareRadarSheet(
                    context,
                    service: service,
                    isVietnamese: isVietnamese,
                  );
                  onPopped?.call(res);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open_radar_btn')));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Dark mode + Vietnamese: displays real FPS & RAM, no fake %, rerun & acknowledge work',
        (tester) async {
      final probe = _FakeHardwareProbe(
        info: const <String, dynamic>{
          'deviceModel': 'Galaxy A54',
          'manufacturer': 'Samsung',
          'socHardware': 'Exynos 1380',
          'totalRamMb': 4096,
          'cpuCores': 8,
          'androidSdk': 34,
        },
        benchmarks: const <Map<String, dynamic>>[
          <String, dynamic>{
            'measuredFps': 14.2,
            'avgInferenceMs': 70.4,
            'framesRun': 12,
          },
          <String, dynamic>{
            'measuredFps': 16.8,
            'avgInferenceMs': 59.5,
            'framesRun': 12,
          },
        ],
      );
      final service = CvHardwareRadarService(probe: probe);
      bool? poppedResult;

      await pumpSheet(
        tester,
        theme: ThemeData.dark(),
        isVietnamese: true,
        service: service,
        onPopped: (val) => poppedResult = val,
      );

      expect(find.text('14.2 FPS'), findsOneWidget);
      expect(find.text('4.0 GB (4096 MB)'), findsOneWidget);
      expect(find.text('Samsung Galaxy A54'), findsOneWidget);
      expect(find.text('Đạt chuẩn'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Tap "Đo lại hiệu năng" -> calls probe a second time & updates FPS
      await tester.tap(find.byKey(const ValueKey('cv_hardware_radar_rerun_button')));
      await tester.pumpAndSettle();

      expect(probe.benchmarkCalls, 2);
      expect(find.text('16.8 FPS'), findsOneWidget);
      expect(find.text('Tối ưu'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Tap "Tôi hiểu và tiếp tục" -> saves acknowledged=true and closes sheet
      await tester.tap(find.byKey(const ValueKey('cv_hardware_radar_ack_button')));
      await tester.pumpAndSettle();

      expect(poppedResult, isTrue);
      expect(await service.shouldShowRadarSheet(), isFalse);
      final cached = await service.loadCachedReport();
      expect(cached?.acknowledged, isTrue);
    });

    testWidgets(
        'Light mode + English: displays limited warning (< 8 FPS) without fake %, rerun & acknowledge work',
        (tester) async {
      final probe = _FakeHardwareProbe(
        info: const <String, dynamic>{
          'deviceModel': 'Redmi 9A',
          'manufacturer': 'Xiaomi',
          'socHardware': 'Helio G25',
          'totalRamMb': 2048,
          'cpuCores': 8,
          'androidSdk': 30,
        },
        benchmarks: const <Map<String, dynamic>>[
          <String, dynamic>{
            'measuredFps': 6.5,
            'avgInferenceMs': 153.8,
            'framesRun': 12,
          },
        ],
      );
      final service = CvHardwareRadarService(probe: probe);
      bool? poppedResult;

      await pumpSheet(
        tester,
        theme: ThemeData.light(),
        isVietnamese: false,
        service: service,
        onPopped: (val) => poppedResult = val,
      );

      expect(find.text('6.5 FPS'), findsOneWidget);
      expect(find.text('2.0 GB (2048 MB)'), findsOneWidget);
      expect(find.text('Hardware Limited'), findsOneWidget);
      expect(find.textContaining('2–3s/rep'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('cv_hardware_radar_rerun_button')));
      await tester.pumpAndSettle();
      expect(probe.benchmarkCalls, 2);

      await tester.tap(find.byKey(const ValueKey('cv_hardware_radar_ack_button')));
      await tester.pumpAndSettle();

      expect(poppedResult, isTrue);
      expect(await service.shouldShowRadarSheet(), isFalse);
    });
  });
}
