import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/nutrition/presentation/providers/recipes_supplements_provider.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/screens/chat/widgets/ai_mode_selector.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_supplements_card.dart';
import 'package:health_ai_app/services/analytics_service.dart';

class MockAnalyticsService extends Mock implements AnalyticsService {}

class FakeSupplementsNotifier
    extends StateNotifier<AsyncValue<List<Supplement>>>
    implements SupplementsNotifier {
  FakeSupplementsNotifier(List<Supplement> items)
      : super(AsyncValue.data(items));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('1. NutritionSupplementsCard Widget Tests', () {
    const testDate = '2026-11-17';

    testWidgets(
      'Khi danh sách rỗng -> hiển thị 3 chip ghi nhanh (Creatine 5g, Whey 1 scoop, Multivitamin)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supplementsByDateProvider(testDate).overrideWith(
                (ref) => FakeSupplementsNotifier([]),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: NutritionSupplementsCard(
                  dateStr: testDate,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SUPPLEMENTS'), findsOneWidget);
        expect(find.text('Ghi nhanh 1 chạm:'), findsOneWidget);
        expect(find.text('Creatine 5g'), findsOneWidget);
        expect(find.text('Whey 1 scoop'), findsOneWidget);
        expect(find.text('Multivitamin'), findsOneWidget);
      },
    );

    testWidgets(
      'Khi có 1 Supplement (Creatine Monohydrate, 5 g, 14:00) -> render đúng tên và liều lượng',
      (tester) async {
        final supplement = Supplement(
          id: 'supp_101',
          name: 'Creatine Monohydrate',
          amount: 5,
          unit: 'g',
          time: '14:00',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supplementsByDateProvider(testDate).overrideWith(
                (ref) => FakeSupplementsNotifier([supplement]),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: NutritionSupplementsCard(
                  dateStr: testDate,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SUPPLEMENTS'), findsOneWidget);
        expect(find.text('Creatine Monohydrate'), findsOneWidget);
        expect(find.text('5 g'), findsOneWidget);
        expect(find.text('14:00'), findsOneWidget);

        // Đảm bảo không render các chip ghi nhanh khi đã có dữ liệu
        expect(find.text('Ghi nhanh 1 chạm:'), findsNothing);
        expect(find.text('Creatine 5g'), findsNothing);
        expect(find.text('Whey 1 scoop'), findsNothing);
        expect(find.text('Multivitamin'), findsNothing);
      },
    );
  });

  group('2. AIModeSelector Widget Tests', () {
    testWidgets(
      'Mặc định Core 3 đang dùng (check icon), Swift 3 và Pro 3 sắp ra mắt (Icons.lock_outline)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              locale: Locale('vi'),
              home: Scaffold(
                body: AIModeSelector(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Kiểm tra cả 3 chip hiển thị
        expect(find.text('Swift 3'), findsOneWidget);
        expect(find.text('Core 3'), findsOneWidget);
        expect(find.text('Pro 3'), findsOneWidget);

        // 2. Mặc định Core 3 được chọn
        expect(
          container.read(chatControllerProvider).selectedAIMode,
          AIMode.core3,
        );

        // 3. Chip đang dùng hiển thị icon check, 2 chip còn lại hiển thị Icons.lock_outline
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
        expect(find.text('Đang dùng'), findsOneWidget);
        expect(find.text('Sắp ra mắt'), findsNWidgets(2));

        // 4. Tap vào Swift 3 -> hiển thị thông báo hiệu chuẩn, không đổi mode
        await tester.tap(find.text('Swift 3'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          container.read(chatControllerProvider).selectedAIMode,
          AIMode.core3,
        );
        expect(
          find.text('Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.'),
          findsOneWidget,
        );

        // 5. Tap vào Pro 3 -> hiển thị thông báo sắp ra mắt, không đổi mode
        await tester.tap(find.text('Pro 3'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          container.read(chatControllerProvider).selectedAIMode,
          AIMode.core3,
        );
        expect(
          find.text('Chế độ Pro 3 sẽ ra mắt trong bản cập nhật tới.'),
          findsOneWidget,
        );
      },
    );
  });

  group('3. HistoryAnalyticsSheet Paywall & Entitlement Tests', () {
    testWidgets(
      'Mock getPreflightQuote(7) hợp lệ & getPreflightQuote(30) ném 403 entitlement_required -> chọn 30 ngày hiện paywall + nút Mở khóa gói hội viên thay vì lỗi mạng chung, bấm lại 7 ngày hiển thị bình thường',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockService = MockAnalyticsService();

        const quote7 = AnalyticsQuote(
          quoteId: 'quote-7-valid',
          rangeDays: 7,
          rawNutritionCount: 14,
          activeDays: 6,
          workoutSessions: 5,
          includedWorkouts: 5,
          workoutTruncated: false,
          estimatedTokens: 850,
          quotaCost: 1,
        );

        when(() => mockService.getPreflightQuote(7))
            .thenAnswer((_) async => quote7);

        final paywallDioException = DioException(
          requestOptions: RequestOptions(path: '/api/analytics/quote'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/analytics/quote'),
            statusCode: 403,
            data: {
              'detail': {
                'code': 'entitlement_required',
                'benefit_id': 'ai.extended_memory',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        );

        when(() => mockService.getPreflightQuote(30))
            .thenThrow(paywallDioException);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('vi'),
              home: Scaffold(
                body: HistoryAnalyticsSheet(
                  service: mockService,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ban đầu (7 ngày): Quote hợp lệ được hiển thị, chưa kích hoạt paywall
        expect(find.text('~850 token'), findsOneWidget);
        expect(find.text('Mở khóa gói hội viên'), findsNothing);
        expect(
          find.text('Phân tích lịch sử 30 ngày dành cho hội viên nâng cao'),
          findsNothing,
        );
        verify(() => mockService.getPreflightQuote(7)).called(1);

        // Chuyển sang 30 ngày -> nhận 403
        await tester.tap(find.text('30 ngày'));
        await tester.pumpAndSettle();

        verify(() => mockService.getPreflightQuote(30)).called(1);

        // Kiểm tra giao diện hiện thông báo nâng cấp + nút "Mở khóa gói hội viên"
        expect(
          find.text('Phân tích lịch sử 30 ngày dành cho hội viên nâng cao'),
          findsOneWidget,
        );
        expect(find.text('Mở khóa gói hội viên'), findsOneWidget);

        // Đảm bảo KHÔNG hiển thị lỗi mạng chung
        expect(find.text('Không thể lấy dữ liệu phân tích'), findsNothing);
        expect(find.text('quote_fetch_error'), findsNothing);

        // Bấm lại 7 ngày -> hiển thị quote bình thường trở lại
        await tester.tap(find.text('7 ngày'));
        await tester.pumpAndSettle();

        verify(() => mockService.getPreflightQuote(7)).called(1);

        // Paywall card đã ẩn, quote hiển thị lại
        expect(find.text('Mở khóa gói hội viên'), findsNothing);
        expect(
          find.text('Phân tích lịch sử 30 ngày dành cho hội viên nâng cao'),
          findsNothing,
        );
        expect(find.text('~850 token'), findsOneWidget);
      },
    );
  });
}
