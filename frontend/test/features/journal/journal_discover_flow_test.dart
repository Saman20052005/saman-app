import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/journal/data/datasources/journal_fake_datasource.dart';
import 'package:health_ai_app/features/journal/data/repositories/journal_repository_impl.dart';
import 'package:health_ai_app/features/journal/presentation/providers/journal_providers.dart';
import 'package:health_ai_app/features/journal/presentation/screens/journal_discover_screen.dart';
import 'package:health_ai_app/screens/home/widgets/saman_picks_carousel.dart';

void main() {
  setUp(() {
    SamanPicksCarousel.resetLastNavTime();
  });

  Widget createTestWidget({
    JournalFakeDatasource? datasource,
    Widget? home,
    Locale locale = const Locale('vi'),
  }) {
    return ProviderScope(
      overrides: [
        if (datasource != null)
          journalRepositoryProvider.overrideWithValue(
            JournalRepositoryImpl(datasource: datasource),
          ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        onGenerateRoute: AppRoutes.onGenerateRoute,
        home: home ?? const JournalDiscoverScreen(),
      ),
    );
  }

  group('JCOM-01 — Home Entrypoint & Navigation Throttling', () {
    testWidgets('Home carousel Journal card navigates to /journal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var journalTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (context) => Scaffold(
                  body: SamanPicksCarousel(
                    onJournalTap: () => journalTapped = true,
                  ),
                ),
            AppRoutes.journal: (context) => const Scaffold(
                  body: Text('Journal Screen Destination'),
                ),
          },
        ),
      );

      expect(find.text('SAMAN JOURNAL'), findsOneWidget);
      expect(find.text('Recover better after Leg Day'), findsOneWidget);

      await tester.tap(find.text('Recover better after Leg Day'));
      await tester.pumpAndSettle();

      expect(journalTapped, isTrue);
    });

    testWidgets('Home carousel rapid double tap does not push duplicate routes',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int pushCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.journal) {
              pushCount++;
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('Journal Target')),
              );
            }
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: SamanPicksCarousel(),
              ),
            );
          },
        ),
      );

      // Rapidly tap twice within throttle window (<400ms)
      await tester.tap(find.text('Recover better after Leg Day'), warnIfMissed: false);
      await tester.tap(find.text('Recover better after Leg Day'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(pushCount, equals(1));
    });

    testWidgets('Other carousel cards (Saman Shop) maintain existing behavior',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var shopTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanPicksCarousel(
              onShopTap: () => shopTapped = true,
            ),
          ),
        ),
      );

      // Drag carousel left to reveal the second card
      await tester.drag(find.byType(ListView), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.text('Recovery essentials, picked for your plan'), findsOneWidget);
      await tester.tap(find.text('Recovery essentials, picked for your plan'));
      await tester.pumpAndSettle();

      expect(shopTapped, isTrue);
    });
  });

  group('JCOM-01 — R01 Journal Discover Screen & Components', () {
    testWidgets('R01 renders all primary sections, tabs, hero and doorway card',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(
        simulatedDelay: Duration.zero,
      );

      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Saman Journal'), findsOneWidget);
      expect(find.byKey(const ValueKey('journal_back_button')), findsOneWidget);

      // Tabs
      expect(find.text('Khám phá'), findsOneWidget);
      expect(find.text('Thư viện'), findsWidgets);
      expect(find.text('Cẩm nang'), findsOneWidget);

      // Search bar trigger
      expect(find.byKey(const ValueKey('journal_search_bar_trigger')), findsOneWidget);
      expect(find.text('Tìm kiến thức, bài tập, món ăn…'), findsOneWidget);

      // Hero Card
      expect(find.text('PHỤC HỒI'), findsOneWidget);
      expect(find.text('Phục hồi tốt hơn sau buổi tập chân'), findsOneWidget);
      expect(find.text('4 phút đọc'), findsOneWidget);

      // Topic Chips
      expect(find.text('Tập luyện'), findsOneWidget);
      expect(find.text('Dinh dưỡng'), findsOneWidget);
      expect(find.text('Phục hồi'), findsWidgets);
      expect(find.text('Thói quen'), findsOneWidget);

      // Continue reading section
      expect(find.text('TIẾP TỤC ĐỌC'), findsOneWidget);
      expect(find.text('Hiểu calories và các chất dinh dưỡng'), findsOneWidget);
      expect(find.text('Đã đọc 40%'), findsOneWidget);

      // Libraries
      expect(find.text('Bài tập & lịch tập'), findsOneWidget);
      expect(find.text('128 chuyển động'), findsOneWidget);
      expect(find.text('Thực phẩm & công thức'), findsOneWidget);
      expect(find.text('240+ dữ liệu chuẩn'), findsOneWidget);

      final verticalScrollable = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;

      // Guided series
      await tester.scrollUntilVisible(
        find.text('Bắt đầu cùng Saman'),
        200,
        scrollable: verticalScrollable,
      );
      expect(find.text('Bắt đầu cùng Saman'), findsOneWidget);
      expect(find.text('LỘ TRÌNH NỀN TẢNG'), findsOneWidget);

      // Community doorway card
      await tester.scrollUntilVisible(
        find.text('Khám phá cộng đồng'),
        200,
        scrollable: verticalScrollable,
      );
      expect(find.text('Saman Community'), findsOneWidget);
      expect(find.text('Chia sẻ hành trình. Cùng nhau tiến bộ.'), findsOneWidget);
      expect(find.text('Khám phá cộng đồng'), findsOneWidget);
    });

    testWidgets('Tapping internal tab Thư viện or Cẩm nang shows honest backlog notice',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      // Tap tab Thư viện
      await tester.tap(find.text('Thư viện').first);
      await tester.pumpAndSettle();

      expect(find.text('Mục "Thư viện" đang được xây dựng'), findsOneWidget);
      expect(find.text('Quay lại Khám phá'), findsOneWidget);

      // Tap button to return to Khám phá
      await tester.tap(find.text('Quay lại Khám phá'));
      await tester.pumpAndSettle();

      // Confirmed back in Khám phá
      expect(find.text('Phục hồi tốt hơn sau buổi tập chân'), findsOneWidget);
    });

    testWidgets('Community doorway tap displays clear preview sheet without dead routes',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      // Drag up to reveal the community doorway card completely
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();

      expect(find.text('Khám phá cộng đồng'), findsOneWidget);
      await tester.tap(find.text('Khám phá cộng đồng'));
      await tester.pumpAndSettle();

      // Navigated to Community Feed (R03) with clear preview notice
      expect(find.text('Saman Community'), findsWidgets);
      expect(find.textContaining('Bản xem trước giao diện'), findsOneWidget);

      // Verify back stack: pop back to R01
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Khám phá cộng đồng'), findsOneWidget);
    });

    testWidgets('R01 Error and retry flow works properly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(
        simulatedDelay: Duration.zero,
        shouldSimulateError: true,
      );

      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải nội dung'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      // Now disable error and tap retry
      datasource.shouldSimulateError = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Phục hồi tốt hơn sau buổi tập chân'), findsOneWidget);
    });
  });
}
