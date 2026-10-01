import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint 3 - ChatConversationSummary Model', () {
    test('parses json correctly and handles missing fields gracefully', () {
      final summary = ChatConversationSummary.fromJson({
        'id': 'conv_123',
        'title': 'Kế hoạch tăng cơ',
        'updated_at': '2026-09-26T12:00:00Z',
        'created_at': '2026-09-26T10:00:00Z',
      });

      expect(summary.id, 'conv_123');
      expect(summary.title, 'Kế hoạch tăng cơ');
      expect(summary.updatedAt, '2026-09-26T12:00:00Z');
      expect(summary.createdAt, '2026-09-26T10:00:00Z');

      final emptySummary = ChatConversationSummary.fromJson({});
      expect(emptySummary.id, '');
      expect(emptySummary.title, 'Cuộc trò chuyện');
      expect(emptySummary.updatedAt, '');
    });
  });

  group('Checkpoint 3 - ChatState Conversation History', () {
    test('copyWith updates and clears activeConversationId and recentConversations', () {
      final initial = ChatState();
      expect(initial.activeConversationId, isNull);
      expect(initial.recentConversations, isEmpty);
      expect(initial.isLoadingHistory, isFalse);

      final updated = initial.copyWith(
        activeConversationId: 'conv_abc',
        recentConversations: [
          ChatConversationSummary(id: 'conv_abc', title: 'Test Conv'),
        ],
        isLoadingHistory: true,
      );

      expect(updated.activeConversationId, 'conv_abc');
      expect(updated.recentConversations.length, 1);
      expect(updated.isLoadingHistory, isTrue);

      final cleared = updated.copyWith(
        clearActiveConversation: true,
        isLoadingHistory: false,
      );
      expect(cleared.activeConversationId, isNull);
      expect(cleared.recentConversations.length, 1);
      expect(cleared.isLoadingHistory, isFalse);
    });
  });

  group('Checkpoint 3 - ChatController API Integration & State Isolation', () {
    late Interceptor mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Tester',
        'user_height': 175,
        'user_weight': 70.0,
        'user_age': 25,
        'user_gender': 'Nam',
        'user_tdee': 2200.0,
      });
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'mock-token-user-a',
      });
    });

    tearDown(() {
      ApiClient.dio.interceptors.remove(mockInterceptor);
    });

    test('loadConversations fetches recent list and loadLatest loads first conversation', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'conversations': [
                  {
                    'id': 'c1',
                    'title': 'Buổi tập ngực',
                    'updated_at': '2026-09-26T10:00:00Z',
                  },
                  {
                    'id': 'c2',
                    'title': 'Bữa ăn sau tập',
                    'updated_at': '2026-09-25T10:00:00Z',
                  },
                ],
              },
            ));
          } else if (options.uri.path.endsWith('/api/chat/conversations/c1')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'id': 'c1',
                'title': 'Buổi tập ngực',
                'messages': [
                  {'role': 'user', 'content': 'Tập Bench Press mấy hiệp?'},
                  {'role': 'assistant', 'content': 'Nên tập 4 hiệp.'},
                ],
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      await controller.loadConversations(loadLatest: true);

      final state = container.read(chatControllerProvider);
      expect(state.recentConversations.length, 2);
      expect(state.recentConversations[0].id, 'c1');
      expect(state.activeConversationId, 'c1');
      expect(state.messages.length, 2);
      expect(state.messages[0].content, 'Tập Bench Press mấy hiệp?');
      expect(state.messages[1].content, 'Nên tập 4 hiệp.');
    });

    test('newConversation clears messages and activeConversationId', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c1',
        messages: [ChatMessage(role: 'user', content: 'Old chat')],
        recentConversations: [ChatConversationSummary(id: 'c1', title: 'Old chat')],
      );

      controller.newConversation();

      final state = container.read(chatControllerProvider);
      expect(state.activeConversationId, isNull);
      expect(state.messages, isEmpty);
      // Recent conversations list in drawer is preserved
      expect(state.recentConversations.length, 1);
    });

    test('race condition: late arriving conversation load is discarded after newConversation', () async {
      final completer = Completer<Response>();

      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.uri.path.endsWith('/api/chat/conversations/slow_c1')) {
            final res = await completer.future;
            return handler.resolve(res);
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      // Start slow load
      final loadFuture = controller.loadConversation('slow_c1');

      // User immediately clicks New conversation
      controller.newConversation();

      // Slow response completes later
      completer.complete(Response(
        requestOptions: RequestOptions(path: '/api/chat/conversations/slow_c1'),
        statusCode: 200,
        data: {
          'status': 'success',
          'id': 'slow_c1',
          'messages': [
            {'role': 'user', 'content': 'Late message that should NOT appear'},
          ],
        },
      ));

      await loadFuture;

      final state = container.read(chatControllerProvider);
      expect(state.activeConversationId, isNull);
      expect(state.messages, isEmpty);
    });

    test('account switch: token change purges previous user state', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'conversations': [
                  {'id': 'conv_b', 'title': 'User B Conversation'},
                ],
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      // User A state
      controller.state = ChatState(
        activeConversationId: 'conv_a',
        messages: [ChatMessage(role: 'user', content: 'Secret User A Note')],
        recentConversations: [ChatConversationSummary(id: 'conv_a', title: 'User A Conv')],
      );

      // Switch to User B token
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'mock-token-user-b',
      });

      await controller.loadConversations();

      final state = container.read(chatControllerProvider);
      // User A messages are completely wiped
      expect(state.messages, isEmpty);
      expect(state.activeConversationId, isNull);
      expect(state.recentConversations.length, 1);
      expect(state.recentConversations[0].id, 'conv_b');
      expect(state.recentConversations[0].title, 'User B Conversation');
    });

    test('sendMessage creates conversation when no activeConversationId and appends conversation_id', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat')) {
            expect(options.data['conversation_id'], isNull);
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'reply': 'Chào bạn, tôi là Saman Coach.',
                'conversation_id': 'new_created_conv_123',
              },
            ));
          } else if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'conversations': [
                  {'id': 'new_created_conv_123', 'title': 'Xin chào'},
                ],
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      expect(controller.state.activeConversationId, isNull);

      await controller.sendMessage('Xin chào');

      final state = container.read(chatControllerProvider);
      expect(state.activeConversationId, 'new_created_conv_123');
      expect(state.messages.length, 2);
      expect(state.messages[0].role, 'user');
      expect(state.messages[0].content, 'Xin chào');
      expect(state.messages[1].role, 'assistant');
      expect(state.messages[1].content, 'Chào bạn, tôi là Saman Coach.');
    });

    test('subsequent sendMessage sends active conversation_id in payload', () async {
      String? sentConvId;
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat')) {
            sentConvId = options.data['conversation_id']?.toString();
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'reply': 'Bạn nên nghỉ 60 giây giữa các hiệp.',
                'conversation_id': sentConvId,
              },
            ));
          } else if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'success', 'conversations': []},
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = controller.state.copyWith(
        activeConversationId: 'existing_conv_999',
        messages: [
          ChatMessage(role: 'user', content: 'Tập ngực mấy hiệp?'),
          ChatMessage(role: 'assistant', content: '4 hiệp.'),
        ],
      );

      await controller.sendMessage('Thời gian nghỉ bao lâu?');

      expect(sentConvId, 'existing_conv_999');
      final state = container.read(chatControllerProvider);
      expect(state.activeConversationId, 'existing_conv_999');
      expect(state.messages.length, 4);
    });

    test('retry after failure sends message without duplicating user turns', () async {
      int requestCount = 0;
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat')) {
            requestCount++;
            if (requestCount == 1) {
              return handler.reject(DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 503),
                type: DioExceptionType.badResponse,
              ));
            } else {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'reply': 'Thành công sau retry!',
                  'conversation_id': 'retry_conv_1',
                },
              ));
            }
          } else if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'success', 'conversations': []},
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      // Attempt 1: Fails with 503
      await controller.sendMessage('Cần tăng calo không?');
      var state = container.read(chatControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.failedUserMessage, 'Cần tăng calo không?');
      expect(state.messages.length, 1); // Only 1 user message

      // Retry: Succeeds
      await controller.retry();
      state = container.read(chatControllerProvider);
      expect(state.errorMessage, isNull);
      expect(state.messages.length, 2); // Exactly 1 user + 1 assistant
      expect(state.messages[0].content, 'Cần tăng calo không?');
      expect(state.messages[1].content, 'Thành công sau retry!');
    });
  });

  group('Checkpoint 3 - Drawer & ChatScreen UI Integration', () {
    testWidgets('Drawer renders real conversations and handles selection',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? selectedId;

      final testDrawer = SamanChatDrawer(
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
        recentConversations: [
          ChatConversationSummary(
            id: 'c101',
            title: 'Form deadlift chuẩn',
            updatedAt: 'Yesterday',
          ),
          ChatConversationSummary(
            id: 'c102',
            title: 'Kế hoạch ăn low carb',
            updatedAt: 'Mon',
          ),
        ],
        activeConversationId: 'c101',
        onSelectConversation: (id) => selectedId = id,
      );

      await tester.pumpWidget(MaterialApp(
        theme: SamanTheme.dark(),
        home: Scaffold(
          body: testDrawer,
        ),
      ));
      await tester.pumpAndSettle();

      // Verify real titles are rendered
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Form deadlift chuẩn'), findsOneWidget);
      expect(find.text('Kế hoạch ăn low carb'), findsOneWidget);

      // Tap on second conversation
      await tester.tap(find.text('Kế hoạch ăn low carb'));
      await tester.pumpAndSettle();
      expect(selectedId, 'c102');
    });

    testWidgets('Drawer triggers onNewChat callback when tapping New conversation',
        (tester) async {
      bool newChatTriggered = false;

      final testDrawer = SamanChatDrawer(
        onNewChat: () => newChatTriggered = true,
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
        recentConversations: const [],
      );

      await tester.pumpWidget(MaterialApp(
        theme: SamanTheme.dark(),
        home: Scaffold(
          body: testDrawer,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap on New conversation
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      expect(newChatTriggered, isTrue);
    });

    testWidgets('Drawer displays empty state when recentConversations is empty',
        (tester) async {
      final testDrawer = SamanChatDrawer(
        onNewChat: () {},
        onPromptSelected: (_) {},
        onOpenPreferences: () {},
        recentConversations: const [],
      );

      await tester.pumpWidget(MaterialApp(
        theme: SamanTheme.dark(),
        home: Scaffold(
          body: testDrawer,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No recent conversations'), findsOneWidget);
    });
  });

  group('Checkpoint 4a - Water Action Confirmation & Rejection', () {
    Interceptor? mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Tester',
        'user_height': 175,
        'user_weight': 70.0,
      });
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'mock-token-user-a',
      });
    });

    tearDown(() {
      if (mockInterceptor != null) {
        ApiClient.dio.interceptors.remove(mockInterceptor);
      }
    });

    test('ChatState pendingAction copyWith and clearPendingAction works', () {
      final initial = ChatState();
      expect(initial.pendingAction, isNull);

      final withAction = initial.copyWith(
        pendingAction: {
          'id': 'act_101',
          'type': 'log_water',
          'amount_ml': 250,
          'status': 'pending',
        },
      );
      expect(withAction.pendingAction?['id'], 'act_101');
      expect(withAction.pendingAction?['status'], 'pending');

      final cleared = withAction.copyWith(clearPendingAction: true);
      expect(cleared.pendingAction, isNull);
    });

    test('ChatController receives pending action from /api/chat proposal', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'success', 'conversations': []},
            ));
          } else if (options.uri.path.endsWith('/api/chat')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'reply': 'Bạn có muốn thêm 250 ml nước không?',
                'conversation_id': 'c_water_1',
                'action': {
                  'id': 'act_water_1',
                  'type': 'log_water',
                  'amount_ml': 250,
                  'status': 'pending',
                },
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      await controller.sendMessage('Tôi vừa uống 250ml nước');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNotNull);
      expect(state.pendingAction!['id'], 'act_water_1');
      expect(state.pendingAction!['status'], 'pending');
      expect(state.messages.last.content, 'Bạn có muốn thêm 250 ml nước không?');
    });

    test('ChatController confirmAction appends message and clears pendingAction on success', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_water_1');
            expect(data['action_id'], 'act_water_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'message': 'Đã thêm 250 ml nước vào nhật ký hôm nay của bạn. (Tổng: 750 ml)',
                'amount_ml': 750,
                'action_id': 'act_water_1',
                'conversation_id': 'c_water_1',
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_water_1',
        messages: [ChatMessage(role: 'assistant', content: 'Bạn có muốn thêm 250 ml nước không?')],
        pendingAction: {'id': 'act_water_1', 'status': 'pending'},
      );

      await controller.confirmAction('c_water_1', 'act_water_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, contains('Đã thêm 250 ml nước'));
      expect(state.errorMessage, isNull);
    });

    test('ChatController confirmAction error shows error without adding fake success message', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 503,
                data: {'detail': 'Water storage unavailable'},
              ),
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_water_1',
        messages: [ChatMessage(role: 'assistant', content: 'Bạn có muốn thêm 250 ml nước không?')],
        pendingAction: {'id': 'act_water_1', 'status': 'pending'},
      );

      await controller.confirmAction('c_water_1', 'act_water_1');

      final state = container.read(chatControllerProvider);
      // Length remains 1: NO fake success message added!
      expect(state.messages.length, 1);
      expect(state.errorMessage, isNotNull);
    });

    test('ChatController cancelAction appends cancellation message and clears pendingAction', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/cancel')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_water_1');
            expect(data['action_id'], 'act_water_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'cancelled',
                'message': 'Đã hủy thao tác thêm nước.',
                'action_id': 'act_water_1',
                'conversation_id': 'c_water_1',
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_water_1',
        messages: [ChatMessage(role: 'assistant', content: 'Bạn có muốn thêm 250 ml nước không?')],
        pendingAction: {'id': 'act_water_1', 'status': 'pending'},
      );

      await controller.cancelAction('c_water_1', 'act_water_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, 'Đã hủy thao tác thêm nước.');
    });

    testWidgets('ChatScreen renders Confirm and Cancel action buttons and dispatches actions',
        (tester) async {
      final notifier = _TestChatNotifier(
        ChatState(
          activeConversationId: 'c_water_1',
          messages: [
            ChatMessage(role: 'user', content: 'Tôi vừa uống 250ml nước'),
            ChatMessage(role: 'assistant', content: 'Bạn có muốn thêm 250 ml nước không?'),
          ],
          pendingAction: {
            'id': 'act_water_1',
            'type': 'log_water',
            'amount_ml': 250,
            'status': 'pending',
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Xác nhận (+250 ml nước)'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      await tester.tap(find.text('Xác nhận (+250 ml nước)'));
      await tester.pump();
      expect(notifier.confirmCalled, isTrue);

      await tester.tap(find.text('Hủy'));
      await tester.pump();
      expect(notifier.cancelCalled, isTrue);
    });
  });

  group('Checkpoint 6 - Meal Action Confirmation & Rejection', () {
    Interceptor? mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Tester',
        'user_height': 175,
        'user_weight': 70.0,
      });
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'mock-token-user-a',
      });
    });

    tearDown(() {
      if (mockInterceptor != null) {
        ApiClient.dio.interceptors.remove(mockInterceptor);
      }
    });

    test('ChatState pendingAction meal model fields copyWith and clearPendingAction', () {
      final initial = ChatState();
      expect(initial.pendingAction, isNull);

      final withAction = initial.copyWith(
        pendingAction: {
          'id': 'act_meal_101',
          'type': 'log_meal',
          'meal_type': 'breakfast',
          'total_calories': 450,
          'total_protein': 25.0,
          'total_carbs': 50.0,
          'total_fat': 12.0,
          'foods': [
            {'name': 'Phở bò', 'calories': 450}
          ],
          'status': 'pending',
        },
      );
      expect(withAction.pendingAction?['id'], 'act_meal_101');
      expect(withAction.pendingAction?['type'], 'log_meal');
      expect(withAction.pendingAction?['total_calories'], 450);
      expect(withAction.pendingAction?['status'], 'pending');

      final cleared = withAction.copyWith(clearPendingAction: true);
      expect(cleared.pendingAction, isNull);
    });

    test('ChatController receives pending meal action from /api/chat proposal', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'success', 'conversations': []},
            ));
          } else if (options.uri.path.endsWith('/api/chat')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'reply': 'Bạn có muốn ghi nhận bữa sáng: Phở bò (450 kcal) không?',
                'conversation_id': 'c_meal_1',
                'action': {
                  'id': 'act_meal_1',
                  'type': 'log_meal',
                  'meal_type': 'breakfast',
                  'total_calories': 450,
                  'total_protein': 25.0,
                  'total_carbs': 50.0,
                  'total_fat': 12.0,
                  'foods': [
                    {'name': 'Phở bò', 'calories': 450}
                  ],
                  'status': 'pending',
                },
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      await controller.sendMessage('Log bữa sáng: Phở bò, 450 calo, 25g protein, 50g carbs, 12g fat');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNotNull);
      expect(state.pendingAction!['id'], 'act_meal_1');
      expect(state.pendingAction!['type'], 'log_meal');
      expect(state.pendingAction!['total_calories'], 450);
      expect(state.pendingAction!['status'], 'pending');
      expect(state.messages.last.content, contains('Bạn có muốn ghi nhận bữa sáng: Phở bò'));
    });

    test('ChatController confirmAction for meal appends message and clears pendingAction', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_meal_1');
            expect(data['action_id'], 'act_meal_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'message': 'Đã ghi nhận bữa ăn: Phở bò (450 kcal, 25.0g protein, 50.0g carbs, 12.0g fat) vào nhật ký hôm nay của bạn.',
                'action_id': 'act_meal_1',
                'conversation_id': 'c_meal_1',
                'meal': {
                  'meal_type': 'breakfast',
                  'total_calories': 450,
                },
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_meal_1',
        messages: [ChatMessage(role: 'assistant', content: 'Bạn có muốn ghi nhận bữa sáng: Phở bò (450 kcal) không?')],
        pendingAction: {
          'id': 'act_meal_1',
          'type': 'log_meal',
          'total_calories': 450,
          'status': 'pending',
        },
      );

      await controller.confirmAction('c_meal_1', 'act_meal_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, contains('Đã ghi nhận bữa ăn: Phở bò'));
      expect(state.errorMessage, isNull);
    });

    test('ChatController cancelAction for meal appends cancellation message and clears pendingAction', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/cancel')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_meal_1');
            expect(data['action_id'], 'act_meal_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'cancelled',
                'message': 'Đã hủy thao tác ghi nhận bữa ăn.',
                'action_id': 'act_meal_1',
                'conversation_id': 'c_meal_1',
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_meal_1',
        messages: [ChatMessage(role: 'assistant', content: 'Bạn có muốn ghi nhận bữa sáng: Phở bò (450 kcal) không?')],
        pendingAction: {
          'id': 'act_meal_1',
          'type': 'log_meal',
          'total_calories': 450,
          'status': 'pending',
        },
      );

      await controller.cancelAction('c_meal_1', 'act_meal_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, 'Đã hủy thao tác ghi nhận bữa ăn.');
    });

    testWidgets('ChatScreen renders meal preview details without hardcoded water labels',
        (tester) async {
      final notifier = _TestChatNotifier(
        ChatState(
          activeConversationId: 'c_meal_1',
          messages: [
            ChatMessage(role: 'user', content: 'Log bữa sáng: Phở bò, 450 calo, 25g protein, 50g carbs, 12g fat'),
            ChatMessage(role: 'assistant', content: 'Bạn có muốn ghi nhận bữa sáng: Phở bò (450 kcal) không?'),
          ],
          pendingAction: {
            'id': 'act_meal_1',
            'type': 'log_meal',
            'total_calories': 450,
            'foods': [
              {'name': 'Phở bò', 'calories': 450}
            ],
            'status': 'pending',
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      // Meal label rendered dynamically
      expect(find.text('Xác nhận (Phở bò: 450 kcal)'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Must NOT contain hardcoded water labels
      expect(find.text('Xác nhận (+250 ml nước)'), findsNothing);

      await tester.tap(find.text('Xác nhận (Phở bò: 450 kcal)'));
      await tester.pump();
      expect(notifier.confirmCalled, isTrue);

      await tester.tap(find.text('Hủy'));
      await tester.pump();
      expect(notifier.cancelCalled, isTrue);
    });
  });

  group('Checkpoint 6 - Workout Action Confirmation & Rejection', () {
    Interceptor? mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Tester',
        'user_height': 175,
        'user_weight': 70.0,
      });
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'mock-token-user-a',
      });
    });

    tearDown(() {
      if (mockInterceptor != null) {
        ApiClient.dio.interceptors.remove(mockInterceptor);
      }
    });

    test('ChatState pendingAction copyWith and clearPendingAction works for adjust_workout', () {
      final initial = ChatState();
      expect(initial.pendingAction, isNull);

      final withAction = initial.copyWith(
        pendingAction: {
          'id': 'act_workout_1',
          'type': 'adjust_workout',
          'plan_id': 'p1',
          'plan_name': 'Leg Day',
          'before': {'duration_minutes': 45},
          'after': {'duration_minutes': 30},
          'changes': {'duration_minutes': 30},
          'status': 'pending',
        },
      );
      expect(withAction.pendingAction?['id'], 'act_workout_1');
      expect(withAction.pendingAction?['type'], 'adjust_workout');
      expect(withAction.pendingAction?['status'], 'pending');

      final cleared = withAction.copyWith(clearPendingAction: true);
      expect(cleared.pendingAction, isNull);
    });

    test('ChatController receives pending workout action from /api/chat proposal', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/conversations')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'status': 'success', 'conversations': []},
            ));
          } else if (options.uri.path.endsWith('/api/chat')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'reply': "Bạn có muốn điều chỉnh kế hoạch tập 'Leg Day' (thời lượng: 45 phút -> 30 phút) không?",
                'conversation_id': 'c_workout_1',
                'action': {
                  'id': 'act_workout_1',
                  'type': 'adjust_workout',
                  'plan_id': 'p1',
                  'plan_name': 'Leg Day',
                  'before': {'duration_minutes': 45},
                  'after': {'duration_minutes': 30},
                  'changes': {'duration_minutes': 30},
                  'status': 'pending',
                },
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      await controller.sendMessage('Điều chỉnh kế hoạch tập Leg Day từ 45 phút xuống 30 phút');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNotNull);
      expect(state.pendingAction!['id'], 'act_workout_1');
      expect(state.pendingAction!['type'], 'adjust_workout');
      expect(state.pendingAction!['plan_name'], 'Leg Day');
      expect(state.pendingAction!['status'], 'pending');
      expect(state.messages.last.content, contains("Bạn có muốn điều chỉnh kế hoạch tập 'Leg Day'"));
    });

    test('ChatController confirmAction for workout appends message and clears pendingAction', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/confirm')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_workout_1');
            expect(data['action_id'], 'act_workout_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'message': "Đã điều chỉnh kế hoạch tập 'Leg Day' (thời lượng: 30 phút) thành công.",
                'action_id': 'act_workout_1',
                'conversation_id': 'c_workout_1',
                'workout': {
                  'plan_id': 'p1',
                  'name': 'Leg Day',
                  'duration_minutes': 30,
                },
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_workout_1',
        messages: [ChatMessage(role: 'assistant', content: "Bạn có muốn điều chỉnh kế hoạch tập 'Leg Day' (thời lượng: 45 phút -> 30 phút) không?")],
        pendingAction: {
          'id': 'act_workout_1',
          'type': 'adjust_workout',
          'plan_id': 'p1',
          'plan_name': 'Leg Day',
          'status': 'pending',
        },
      );

      await controller.confirmAction('c_workout_1', 'act_workout_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, contains("Đã điều chỉnh kế hoạch tập 'Leg Day'"));
      expect(state.errorMessage, isNull);
    });

    test('ChatController cancelAction for workout appends cancellation message and clears pendingAction', () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.endsWith('/api/chat/actions/cancel')) {
            final data = options.data as Map;
            expect(data['conversation_id'], 'c_workout_1');
            expect(data['action_id'], 'act_workout_1');
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'cancelled',
                'message': 'Đã hủy thao tác điều chỉnh kế hoạch tập.',
                'action_id': 'act_workout_1',
                'conversation_id': 'c_workout_1',
              },
            ));
          }
          return handler.next(options);
        },
      );
      ApiClient.dio.interceptors.insert(0, mockInterceptor!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.state = ChatState(
        activeConversationId: 'c_workout_1',
        messages: [ChatMessage(role: 'assistant', content: "Bạn có muốn điều chỉnh kế hoạch tập 'Leg Day' (thời lượng: 45 phút -> 30 phút) không?")],
        pendingAction: {
          'id': 'act_workout_1',
          'type': 'adjust_workout',
          'plan_id': 'p1',
          'plan_name': 'Leg Day',
          'status': 'pending',
        },
      );

      await controller.cancelAction('c_workout_1', 'act_workout_1');

      final state = container.read(chatControllerProvider);
      expect(state.pendingAction, isNull);
      expect(state.messages.length, 2);
      expect(state.messages.last.content, 'Đã hủy thao tác điều chỉnh kế hoạch tập.');
    });

    testWidgets('ChatScreen renders workout preview details without hardcoded water/meal labels',
        (tester) async {
      final notifier = _TestChatNotifier(
        ChatState(
          activeConversationId: 'c_workout_1',
          messages: [
            ChatMessage(role: 'user', content: 'Điều chỉnh kế hoạch tập Leg Day từ 45 phút xuống 30 phút'),
            ChatMessage(role: 'assistant', content: "Bạn có muốn điều chỉnh kế hoạch tập 'Leg Day' (thời lượng: 45 phút -> 30 phút) không?"),
          ],
          pendingAction: {
            'id': 'act_workout_1',
            'type': 'adjust_workout',
            'plan_id': 'p1',
            'plan_name': 'Leg Day',
            'before': {'duration_minutes': 45},
            'after': {'duration_minutes': 30},
            'changes': {'duration_minutes': 30},
            'status': 'pending',
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      // Workout label rendered dynamically
      expect(find.text('Xác nhận (Điều chỉnh Leg Day: 30 phút)'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);

      // Must NOT contain hardcoded water/meal labels
      expect(find.text('Xác nhận (+250 ml nước)'), findsNothing);
      expect(find.text('Xác nhận ghi nhận bữa ăn'), findsNothing);

      await tester.tap(find.text('Xác nhận (Điều chỉnh Leg Day: 30 phút)'));
      await tester.pump();
      expect(notifier.confirmCalled, isTrue);

      await tester.tap(find.text('Hủy'));
      await tester.pump();
      expect(notifier.cancelCalled, isTrue);
    });
  });
}

class _TestChatNotifier extends StateNotifier<ChatState>
    implements ChatController, ChatActionDelegate {
  _TestChatNotifier(super.state);

  bool confirmCalled = false;
  bool cancelCalled = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> handleConfirmAction(String conversationId, String actionId) async {
    confirmCalled = true;
  }

  @override
  Future<void> handleCancelAction(String conversationId, String actionId) async {
    cancelCalled = true;
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}
}
