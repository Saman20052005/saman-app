import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/nutrition/weekly_report_screen.dart';
import 'package:health_ai_app/services/nutrition_service.dart';

Future<void> _captureRepaintBoundary(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();

    const evidenceDir =
        'd:/SamanDev/runtime_evidence/NUTRITION_ACTIVE_20261027/ui_evidence';
    final dir = Directory(evidenceDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('$evidenceDir/$fileName').writeAsBytesSync(bytes);

    // Also copy to artifact directory for rendering in completion reports
    const artifactDir =
        'C:/Users/GL/.gemini/antigravity/brain/073893c8-527f-4884-b01c-2a307df2a727';
    final aDir = Directory(artifactDir);
    if (!aDir.existsSync()) {
      aDir.createSync(recursive: true);
    }
    File('$artifactDir/$fileName').writeAsBytesSync(bytes);
  });
}

class FakeNutritionService extends NutritionService {
  Map<String, dynamic> Function(String startDate)? onGetWeeklyReport;
  bool shouldThrow = false;
  String? lastRequestedStartDate;

  @override
  Future<Map<String, dynamic>> getWeeklyReport(String startDate) async {
    lastRequestedStartDate = startDate;
    if (shouldThrow) {
      throw Exception('Network connection error');
    }
    if (onGetWeeklyReport != null) {
      return onGetWeeklyReport!(startDate);
    }
    return defaultWeeklyReportJson(startDate);
  }
}

Map<String, dynamic> defaultWeeklyReportJson(String startDate) {
  return {
    "start_date": startDate,
    "end_date": "2026-11-01",
    "days_logged": 1,
    "daily": [
      {
        "date": "2026-10-26",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
      {
        "date": "2026-10-27",
        "calories": 125.0,
        "protein": 17.0,
        "carbs": 4.0,
        "fat": 4.0,
        "log_count": 1
      },
      {
        "date": "2026-10-28",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
      {
        "date": "2026-10-29",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
      {
        "date": "2026-10-30",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
      {
        "date": "2026-10-31",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
      {
        "date": "2026-11-01",
        "calories": 0.0,
        "protein": 0.0,
        "carbs": 0.0,
        "fat": 0.0,
        "log_count": 0
      },
    ],
    "weekly_totals": {
      "calories": 125.0,
      "protein": 17.0,
      "carbs": 4.0,
      "fat": 4.0,
    },
    "daily_average": {"calories": 18.0},
    "macro_targets": {
      "calories": 3129,
      "protein": 136.0,
      "carbs": 451.0,
      "fat": 87.0,
    },
  };
}

void main() {
  group('WeeklyReportScreen UI & Behavior Contract', () {
    late FakeNutritionService fakeService;

    setUp(() {
      fakeService = FakeNutritionService();
    });

    testWidgets('renders all modules according to design contract and real data',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: boundaryKey,
            child: WeeklyReportScreen(
              service: fakeService,
              initialDate: DateTime(2026, 10, 27),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Capture top view
      await _captureRepaintBoundary(
        tester,
        boundaryKey,
        '07_weekly_report_top.png',
      );

      // Module 1: Header
      expect(find.text('Báo cáo tuần'), findsOneWidget);
      expect(find.text('Nhìn lại dinh dưỡng của bạn'), findsOneWidget);
      expect(find.text('Tuần 44'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);

      // Module 1B: Week Selector
      expect(find.text('26 thg 10 – 1 thg 11'), findsOneWidget);
      expect(find.text('Năm 2026'), findsOneWidget);
      expect(find.text('1/7 ngày đã ghi'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Module 2: Daily Calorie Chart
      expect(find.text('Năng lượng theo ngày'), findsOneWidget);
      expect(find.text('Lượng đã ghi so với mục tiêu'), findsOneWidget);
      expect(find.text('Mục tiêu · 3.129 kcal'), findsOneWidget);
      expect(find.text('T2'), findsOneWidget);
      expect(find.text('T3'), findsOneWidget);
      expect(find.text('CN'), findsOneWidget);

      // Selected Day Footer (default selected is Oct 27 because it has data/is today)
      expect(find.text('Thứ Ba, 27/10'), findsOneWidget);
      expect(find.text('125 kcal'), findsWidgets); // on chart footer & breakdown
      expect(find.text('Đạm 17 g'), findsOneWidget);
      expect(find.text('Carb 4 g'), findsOneWidget);
      expect(find.text('Béo 4 g'), findsOneWidget);

      // Module 3: Weekly Macros
      expect(find.text('Macro trong tuần'), findsOneWidget);
      expect(find.text('Đạm'), findsOneWidget);
      expect(find.text('17 g'), findsOneWidget);
      expect(find.text('Mục tiêu 952 g'), findsOneWidget); // 136 * 7 = 952

      expect(find.text('Carb'), findsOneWidget);
      expect(find.text('4 g'), findsNWidgets(2)); // Carb & Fat are both 4g
      expect(find.text('Mục tiêu 3.157 g'), findsOneWidget); // 451 * 7 = 3157

      expect(find.text('Béo'), findsOneWidget);
      expect(find.text('Mục tiêu 609 g'), findsOneWidget); // 87 * 7 = 609

      // Module 4: Summary Metrics
      expect(find.text('Trung bình / ngày'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('So với mục tiêu'), findsOneWidget);
      expect(find.text('−3.111'), findsOneWidget); // 18 - 3129 = -3111
      expect(find.text('Trung bình tính trên 7 ngày của tuần.'), findsOneWidget);
      expect(
        find.text(
            'Bạn mới ghi 1/7 ngày. Báo cáo chưa phản ánh đầy đủ lượng ăn thực tế.'),
        findsOneWidget,
      );

      // Module 5: Daily Breakdown
      expect(find.text('Chi tiết từng ngày'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu'), findsNWidgets(6));

      // Scroll to capture bottom view
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await _captureRepaintBoundary(
        tester,
        boundaryKey,
        '08_weekly_report_scrolled.png',
      );
    });

    testWidgets('tapping different day updates selected day details',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WeeklyReportScreen(
            service: fakeService,
            initialDate: DateTime(2026, 10, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial selected day is Oct 27
      expect(find.text('Thứ Ba, 27/10'), findsOneWidget);

      // Tap on T2 (Monday Oct 26) label
      await tester.tap(find.text('T2'));
      await tester.pumpAndSettle();

      // Now footer displays Thứ Hai, 26/10 and unlogged state
      expect(find.text('Thứ Hai, 26/10'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu nhật ký cho ngày này'), findsOneWidget);

      // Tap back on T3
      await tester.tap(find.text('T3'));
      await tester.pumpAndSettle();
      expect(find.text('Thứ Ba, 27/10'), findsOneWidget);
      expect(find.text('Đạm 17 g'), findsOneWidget);
    });

    testWidgets('week navigation moves to previous and next weeks',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WeeklyReportScreen(
            service: fakeService,
            initialDate: DateTime(2026, 10, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeService.lastRequestedStartDate, '2026-10-26');

      // Tap previous week
      await tester.tap(find.byTooltip('Tuần trước'));
      await tester.pumpAndSettle();

      expect(fakeService.lastRequestedStartDate, '2026-10-19');
      expect(find.text('19 thg 10 – 25 thg 10'), findsOneWidget);

      // Tap next week twice
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(fakeService.lastRequestedStartDate, '2026-10-26');

      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(fakeService.lastRequestedStartDate, '2026-11-02');
      expect(find.text('2 thg 11 – 8 thg 11'), findsOneWidget);
    });

    testWidgets('handles empty week (0 days logged) gracefully',
        (tester) async {
      fakeService.onGetWeeklyReport = (startDate) => {
            "start_date": startDate,
            "end_date": "2026-11-01",
            "days_logged": 0,
            "daily": List.generate(
              7,
              (i) => {
                "date": "2026-10-${26 + i}",
                "calories": 0.0,
                "protein": 0.0,
                "carbs": 0.0,
                "fat": 0.0,
                "log_count": 0,
              },
            ),
            "weekly_totals": {
              "calories": 0.0,
              "protein": 0.0,
              "carbs": 0.0,
              "fat": 0.0,
            },
            "daily_average": {"calories": 0.0},
            "macro_targets": {
              "calories": 2000,
              "protein": 50.0,
              "carbs": 250.0,
              "fat": 65.0,
            },
          };

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WeeklyReportScreen(
            service: fakeService,
            initialDate: DateTime(2026, 10, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0/7 ngày đã ghi'), findsOneWidget);
      expect(
        find.text(
            'Chưa có nhật ký nào trong tuần này. Hãy ghi bữa ăn để xem báo cáo dinh dưỡng.'),
        findsOneWidget,
      );
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('handles missing or zero targets without NaN or crash',
        (tester) async {
      fakeService.onGetWeeklyReport = (startDate) => {
            "start_date": startDate,
            "end_date": "2026-11-01",
            "days_logged": 1,
            "daily": List.generate(
              7,
              (i) => {
                "date": "2026-10-${26 + i}",
                "calories": i == 1 ? 500.0 : 0.0,
                "protein": 0.0,
                "carbs": 0.0,
                "fat": 0.0,
                "log_count": i == 1 ? 1 : 0,
              },
            ),
            "weekly_totals": {
              "calories": 500.0,
              "protein": 0.0,
              "carbs": 0.0,
              "fat": 0.0,
            },
            "daily_average": {"calories": 71.4},
            "macro_targets": {
              "calories": 0,
              "protein": 0.0,
              "carbs": 0.0,
              "fat": 0.0,
            },
          };

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WeeklyReportScreen(
            service: fakeService,
            initialDate: DateTime(2026, 10, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa có mục tiêu'), findsWidgets);
      // Diff against target should be dash '—' when target is 0
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('displays error view on failure and allows retry',
        (tester) async {
      fakeService.shouldThrow = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WeeklyReportScreen(
            service: fakeService,
            initialDate: DateTime(2026, 10, 27),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải báo cáo tuần.'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      // Now service recovers
      fakeService.shouldThrow = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Báo cáo tuần'), findsOneWidget);
      expect(find.text('1/7 ngày đã ghi'), findsOneWidget);
    });
  });
}
