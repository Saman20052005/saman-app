import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/load_daily_plan_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/swap_meal_usecase.dart';
import 'package:health_ai_app/features/nutrition/domain/usecases/update_water_usecase.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/services/api_client.dart';

class _MockAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _MockNutritionRepo extends Mock implements INutritionRepository {}

class _SpyNutritionNotifier extends NutritionNotifier {
  _SpyNutritionNotifier()
      : super(
          repository: _MockNutritionRepo(),
          loadDailyPlanUseCase: LoadDailyPlanUseCase(_MockNutritionRepo()),
          updateWaterUseCase: UpdateWaterUseCase(_MockNutritionRepo()),
          swapMealUseCase: SwapMealUseCase(_MockNutritionRepo()),
          swapLoggedMealUseCase: SwapLoggedMealUseCase(_MockNutritionRepo()),
        );

  int refreshCalls = 0;

  @override
  Future<void> refreshCurrentPlan({
    String? dateStr,
    bool forceRefresh = true,
  }) async {
    refreshCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ChatController.confirmAction refreshes nutrition plan and daily brief on log_water success',
      () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'unit-test-token'});
    final originalAdapter = ApiClient.dio.httpClientAdapter;
    addTearDown(() => ApiClient.dio.httpClientAdapter = originalAdapter);

    var briefCalls = 0;
    ApiClient.dio.httpClientAdapter = _MockAdapter((options) {
      if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
        return ResponseBody.fromString(
          jsonEncode({
            'status': 'success',
            'message': 'Đã thêm 350 ml nước vào nhật ký hôm nay của bạn.',
            'amount_ml': 350,
            'action_id': 'act-water-350',
            'conversation_id': 'conv-water-1',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      if (options.uri.path.endsWith('/api/chat/daily-brief')) {
        briefCalls++;
        return ResponseBody.fromString(
          jsonEncode({
            'status': 'success',
            'brief': 'Bạn đã uống 350/2394 ml nước.',
            'metrics': {'calories': 0, 'water_ml': 350},
            'nudge': {'id': 'water_gap_nudge', 'message': 'Đã cập nhật 350 ml.'},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString('{}', 404);
    });

    final spyNutrition = _SpyNutritionNotifier();
    final container = ProviderContainer(
      overrides: [
        nutritionProvider.overrideWith((ref) => spyNutrition),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(chatControllerProvider.notifier);
    controller.state = ChatState(
      activeConversationId: 'conv-water-1',
      messages: [ChatMessage(role: 'assistant', content: 'Xác nhận +350ml nước?')],
      pendingAction: const {
        'id': 'act-water-350',
        'type': 'log_water',
        'amount_ml': 350,
        'status': 'pending',
      },
    );

    await controller.confirmAction('conv-water-1', 'act-water-350');

    expect(spyNutrition.refreshCalls, 1);
    expect(briefCalls, 1);
    expect(container.read(chatControllerProvider).pendingAction, isNull);
    expect(
      container.read(chatControllerProvider).dailyBriefMetrics?['water_ml'],
      350,
    );
  });
}
