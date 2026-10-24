import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/widgets.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

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
}
