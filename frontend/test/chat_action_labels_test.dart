import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/screens/chat/widgets/widgets.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:health_ai_app/utils/auth_helper.dart';

class _FakeChatController extends StateNotifier<ChatState>
    implements ChatController, ChatActionDelegate {
  String? lastConfirmedConvId;
  String? lastConfirmedActionId;
  String? lastCancelledConvId;
  String? lastCancelledActionId;

  _FakeChatController(ChatState initialState) : super(initialState);

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> handleConfirmAction(String conversationId, String actionId) async {
    lastConfirmedConvId = conversationId;
    lastConfirmedActionId = actionId;
  }

  @override
  Future<void> handleCancelAction(String conversationId, String actionId) async {
    lastCancelledConvId = conversationId;
    lastCancelledActionId = actionId;
  }

  @override
  Future<void> sendMessage(String text) async {}

  @override
  void clearChat() {}

  @override
  Future<void> retry() async {}

  @override
  void clearError() {}

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption, String? mode}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {}

  @override
  void newConversation() {}
}

Widget _wrap(Widget child, _FakeChatController controller) {
  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => controller),
    ],
    child: MaterialApp(
      theme: SamanTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('renders log_water action button and handles tap', (tester) async {
    final controller = _FakeChatController(
      ChatState(
        activeConversationId: 'conv-123',
        pendingAction: {
          'id': 'act-water-1',
          'type': 'log_water',
          'status': 'pending',
          'amount_ml': 250,
        },
        messages: [
          ChatMessage(role: 'assistant', content: 'Bạn có muốn ghi nhận nước?'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(const ChatScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận (+250 ml nước)'), findsOneWidget);
    expect(find.text('Hủy'), findsOneWidget);

    await tester.tap(find.text('Xác nhận (+250 ml nước)'));
    await tester.pump();

    expect(controller.lastConfirmedConvId, 'conv-123');
    expect(controller.lastConfirmedActionId, 'act-water-1');
  });

  testWidgets('renders log_meal action button with food name and calories', (tester) async {
    final controller = _FakeChatController(
      ChatState(
        activeConversationId: 'conv-456',
        pendingAction: {
          'id': 'act-meal-1',
          'type': 'log_meal',
          'status': 'pending',
          'total_calories': 450,
          'foods': [
            {'name': 'Phở bò', 'calories': 450}
          ],
        },
        messages: [
          ChatMessage(role: 'assistant', content: 'Tôi đã tính xong calo bữa ăn.'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(const ChatScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận (Phở bò: 450 kcal)'), findsOneWidget);
    expect(find.text('Hủy'), findsOneWidget);

    await tester.tap(find.text('Hủy'));
    await tester.pump();

    expect(controller.lastCancelledConvId, 'conv-456');
    expect(controller.lastCancelledActionId, 'act-meal-1');
  });

  testWidgets('renders adjust_workout action button with duration changes', (tester) async {
    final controller = _FakeChatController(
      ChatState(
        activeConversationId: 'conv-789',
        pendingAction: {
          'id': 'act-workout-1',
          'type': 'adjust_workout',
          'status': 'pending',
          'plan_name': 'Cardio',
          'changes': {'duration_minutes': 30},
        },
        messages: [
          ChatMessage(role: 'assistant', content: 'Tôi đề xuất giảm thời gian tập.'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(const ChatScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận (Điều chỉnh Cardio: 30 phút)'), findsOneWidget);

    await tester.tap(find.text('Xác nhận (Điều chỉnh Cardio: 30 phút)'));
    await tester.pump();

    expect(controller.lastConfirmedConvId, 'conv-789');
    expect(controller.lastConfirmedActionId, 'act-workout-1');
  });

  testWidgets('does not render action buttons when status is not pending', (tester) async {
    final controller = _FakeChatController(
      ChatState(
        activeConversationId: 'conv-000',
        pendingAction: {
          'id': 'act-water-done',
          'type': 'log_water',
          'status': 'confirmed',
        },
        messages: [
          ChatMessage(role: 'assistant', content: 'Đã hoàn thành.'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(const ChatScreen(), controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('Xác nhận'), findsNothing);
    expect(find.text('Hủy'), findsNothing);
  });

  group('CP-20A Frontend Action Session Isolation & Error Semantics', () {
    Interceptor? mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({'user_name': 'User A'});
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'token-user-a'});
    });

    tearDown(() {
      if (mockInterceptor != null) {
        ApiClient.dio.interceptors.remove(mockInterceptor!);
        mockInterceptor = null;
      }
    });

    test('late confirmAction response from Account A arriving after Account A->B switch does not apply to Account B', () async {
      final confirmCompleter = Completer<Response>();

      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
            final res = await confirmCompleter.future;
            return handler.resolve(res);
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'conv-a-1',
        messages: [ChatMessage(role: 'assistant', content: 'Ghi nhận bữa ăn Phở bò?')],
        pendingAction: {
          'id': 'act-meal-a1',
          'type': 'log_meal',
          'status': 'pending',
          'total_calories': 450,
        },
      );

      // User A taps Confirm (request is now in-flight)
      final confirmFuture = controller.confirmAction('conv-a-1', 'act-meal-a1');
      await Future<void>.delayed(Duration.zero);

      // Account switches from User A to User B while confirm request is in-flight
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'token-user-b'});
      container.read(workoutAuthScopeProvider.notifier).state++;

      // Set User B's clean state
      controller.state = ChatState(
        activeConversationId: 'conv-b-1',
        messages: [ChatMessage(role: 'assistant', content: 'Xin chào User B!')],
      );

      // Now Account A's confirm response arrives late
      confirmCompleter.complete(Response(
        requestOptions: RequestOptions(path: '/api/chat/actions/confirm'),
        statusCode: 200,
        data: {
          'status': 'success',
          'message': 'Đã ghi nhận bữa ăn: Phở bò (450 kcal) của User A.',
          'action_id': 'act-meal-a1',
          'conversation_id': 'conv-a-1',
        },
      ));

      await confirmFuture;

      final stateB = container.read(chatControllerProvider);
      expect(stateB.activeConversationId, 'conv-b-1');
      expect(stateB.messages.length, 1);
      expect(stateB.messages.single.content, 'Xin chào User B!');
      expect(
        stateB.messages.any((m) => m.content.contains('Phở bò')),
        isFalse,
        reason: 'Late confirm response from Account A must never pollute Account B',
      );
    });

    test('confirmAction and cancelAction 403/500 errors set error feedback without fake success or auto-logout', () async {
      int statusCodeToReturn = 403;
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/confirm') ||
              options.uri.path.endsWith('/api/chat/actions/cancel')) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: statusCodeToReturn,
                data: {'detail': 'Error $statusCodeToReturn'},
              ),
              type: DioExceptionType.badResponse,
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialScope = container.read(workoutAuthScopeProvider);
      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'conv-workout-1',
        messages: [ChatMessage(role: 'assistant', content: 'Điều chỉnh Cardio xuống 30 phút?')],
        pendingAction: {
          'id': 'act-wk-1',
          'type': 'adjust_workout',
          'status': 'pending',
          'plan_name': 'Cardio',
          'changes': {'duration_minutes': 30},
        },
      );

      // 1. 403 on confirmAction -> sets errorMessage, keeps pendingAction, no fake success message, no logout
      statusCodeToReturn = 403;
      await controller.confirmAction('conv-workout-1', 'act-wk-1');
      var state = container.read(chatControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, "I couldn't confirm that action.");
      expect(state.pendingAction?['id'], 'act-wk-1');
      expect(state.messages.length, 1);
      expect(container.read(workoutAuthScopeProvider), initialScope);
      expect(container.read(authLoggingOutProvider), isFalse);

      // 2. 500 on cancelAction -> sets errorMessage, keeps pendingAction, no fake cancel message, no logout
      statusCodeToReturn = 500;
      await controller.cancelAction('conv-workout-1', 'act-wk-1');
      state = container.read(chatControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, "I couldn't cancel that action.");
      expect(state.pendingAction?['id'], 'act-wk-1');
      expect(state.messages.length, 1);
      expect(container.read(workoutAuthScopeProvider), initialScope);
      expect(container.read(authLoggingOutProvider), isFalse);
    });
  });
}
