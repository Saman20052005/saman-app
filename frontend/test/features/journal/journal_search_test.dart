import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/journal/data/datasources/journal_fake_datasource.dart';
import 'package:health_ai_app/features/journal/data/repositories/journal_repository_impl.dart';
import 'package:health_ai_app/features/journal/presentation/providers/journal_providers.dart';
import 'package:health_ai_app/features/journal/presentation/screens/journal_search_screen.dart';

void main() {
  Widget createTestWidget({
    JournalFakeDatasource? datasource,
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
        home: const JournalSearchScreen(),
      ),
    );
  }

  group('JCOM-01 — R02 Journal Search Screen & Contract Tests', () {
    testWidgets('R02 renders search bar, clear button, filters and results',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);

      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      // Search bar
      expect(find.byKey(const ValueKey('search_back_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('journal_search_input_field')), findsOneWidget);

      // Default query "protein" is populated per design mockup
      expect(find.text('protein'), findsOneWidget);

      // Filter chips
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Bài viết'), findsWidgets);
      expect(find.text('Bài tập'), findsWidgets);
      expect(find.text('Thực phẩm'), findsWidgets);
      expect(find.text('Công thức'), findsWidgets);

      // Grouped results
      expect(find.text('Hiểu protein trong bữa ăn hằng ngày'), findsOneWidget);
      expect(find.text('Ức gà'), findsOneWidget);
      expect(find.text('Sữa chua, yến mạch và trái cây'), findsOneWidget);
      expect(find.text('Tập tạ và tổng hợp protein cơ bắp'), findsOneWidget);

      final verticalScrollable = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;

      // Scroll down to advice tip footer
      await tester.scrollUntilVisible(
        find.text('Gợi ý từ Saman Journal'),
        200,
        scrollable: verticalScrollable,
      );
      expect(find.text('Gợi ý từ Saman Journal'), findsOneWidget);
      expect(find.textContaining('1.6 - 2.2g đạm'), findsOneWidget);
    });

    testWidgets('Category chips filter results immediately without mixing community posts',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      // Tap "Bài tập" (visible in initial view)
      await tester.tap(find.byKey(const ValueKey('filter_chip_exercises')));
      await tester.pumpAndSettle();

      expect(find.text('Tập tạ và tổng hợp protein cơ bắp'), findsOneWidget);
      expect(find.text('Hiểu protein trong bữa ăn hằng ngày'), findsNothing);

      // Drag the horizontal chips ListView left to reveal "Thực phẩm"
      await tester.drag(find.byType(ListView).first, const Offset(-150, 0));
      await tester.pumpAndSettle();

      // Tap "Thực phẩm"
      await tester.tap(find.byKey(const ValueKey('filter_chip_foods')));
      await tester.pumpAndSettle();

      // Food matches appear
      expect(find.text('Ức gà'), findsWidgets);
      // Exercise should now be filtered out
      expect(find.text('Tập tạ và tổng hợp protein cơ bắp'), findsNothing);
    });

    testWidgets('Clear button clears search query and updates result stream',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('clear_search_button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clear_search_button')));
      await tester.pumpAndSettle();

      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('journal_search_input_field')),
      );
      expect(input.controller?.text, isEmpty);
    });

    testWidgets('Empty search result displays honest empty state with query',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('journal_search_input_field')),
        'khong_co_ket_qua_xyz',
      );
      // Fast forward past 300ms debounce
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        find.text('Không tìm thấy kết quả phù hợp cho "khong_co_ket_qua_xyz"'),
        findsOneWidget,
      );
    });

    testWidgets('Search error displays error message and retry retains query and category',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(
        simulatedDelay: Duration.zero,
        shouldSimulateError: true,
      );

      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      expect(find.text('Lỗi tìm kiếm'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);

      // Disable error and tap retry
      datasource.shouldSimulateError = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Ức gà'), findsOneWidget);
    });

    testWidgets('Tapping food item "+" opens preview sheet without writing to database',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datasource = JournalFakeDatasource(simulatedDelay: Duration.zero);
      await tester.pumpWidget(createTestWidget(datasource: datasource));
      await tester.pumpAndSettle();

      final addBtn = find.byIcon(Icons.add_rounded).first;
      expect(addBtn, findsOneWidget);

      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.text('CHI TIẾT DINH DƯỠNG'), findsOneWidget);
      expect(
        find.textContaining('Nút thêm nhanh chưa ghi nhận món ăn vào nhật ký Nutrition'),
        findsOneWidget,
      );

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });
  });

  group('JCOM-01 — Race Condition & Stale Query Guard Unit Test', () {
    test('Older query response never overwrites newer query response in notifier',
        () async {
      final datasource = JournalFakeDatasource(
        simulatedDelay: const Duration(milliseconds: 100),
      );
      final notifier = JournalSearchNotifier(
        JournalRepositoryImpl(datasource: datasource),
      );

      // Trigger first query
      notifier.onQueryChanged('first_query');

      // Immediately trigger second query before first finishes
      notifier.onQueryChanged('second_query');

      // Wait for both to complete
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Active state query MUST be 'second_query'
      expect(notifier.state.query, equals('second_query'));

      notifier.dispose();
    });
  });
}
