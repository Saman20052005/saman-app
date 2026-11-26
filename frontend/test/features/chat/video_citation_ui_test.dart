import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/models/video_citation.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_assistant_response.dart';
import 'package:health_ai_app/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoCitation model', () {
    test('fromJson parses snake_case and camelCase and clamps seekSec', () {
      final snake = VideoCitation.fromJson(const {
        'video_story_id': 'story_1',
        'video_url': 'https://cdn.example.com/lat.mp4',
        'label': 'Xem Lat Pulldown — Rep 7 (0:19)',
        'seek_sec': 19.5,
        'exercise_slug': 'lat-pulldown',
        'rep_index': 7,
        'issue_type': 'torso_swing',
      });

      expect(snake.videoStoryId, 'story_1');
      expect(snake.videoUrl, 'https://cdn.example.com/lat.mp4');
      expect(snake.label, 'Xem Lat Pulldown — Rep 7 (0:19)');
      expect(snake.seekSec, 19.5);
      expect(snake.exerciseSlug, 'lat-pulldown');
      expect(snake.repIndex, 7);
      expect(snake.issueType, 'torso_swing');
      expect(snake.formattedTimestamp, '0:19');

      final camel = VideoCitation.fromJson(const {
        'videoStoryId': 'story_2',
        'videoUrl': 'https://cdn.example.com/squat.mp4',
        'label': 'Xem Squat — Rep 3 (1:15)',
        'seekSec': 75,
        'exerciseSlug': 'barbell-squat',
        'repIndex': 3,
        'issueType': 'knee_valgus',
      });

      expect(camel.videoStoryId, 'story_2');
      expect(camel.seekSec, 75.0);
      expect(camel.formattedTimestamp, '1:15');

      final clamped = VideoCitation.fromJson(const {
        'video_story_id': 'story_3',
        'video_url': 'https://cdn.example.com/dl.mp4',
        'label': 'Test',
        'seek_sec': -12.4,
      });
      expect(clamped.seekSec, 0.0);
      expect(clamped.formattedTimestamp, '0:00');
    });

    test('parseList handles null, malformed items, and empty videoUrl safely', () {
      expect(VideoCitation.parseList(null), isEmpty);
      expect(VideoCitation.parseList('invalid'), isEmpty);
      expect(VideoCitation.parseList({'not': 'a_list'}), isEmpty);

      final parsed = VideoCitation.parseList([
        'bad_item',
        {'video_story_id': 'empty_url', 'video_url': '', 'label': 'Ignored'},
        {
          'video_story_id': 'valid_1',
          'video_url': 'https://cdn.example.com/rep7.mp4',
          'label': 'Xem Lat Pulldown — Rep 7 (0:19)',
          'seek_sec': 19.5,
        },
      ]);

      expect(parsed, hasLength(1));
      expect(parsed.first.videoStoryId, 'valid_1');
      expect(parsed.first.toJson()['seek_sec'], 19.5);
    });
  });

  group('SamanAssistantResponse video citations UI', () {
    Widget wrapWidget(Widget child) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    }

    testWidgets('renders no video chips when videoCitations is empty',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Hôm nay bạn tập tốt lắm.',
      );

      await tester.pumpWidget(
        wrapWidget(SamanAssistantResponse(message: msg)),
      );

      expect(find.text('Hôm nay bạn tập tốt lắm.'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
    });

    testWidgets('renders citation chips and triggers onCitationTap with exact seekSec',
        (tester) async {
      final citations = [
        const VideoCitation(
          videoStoryId: 'story_lat',
          videoUrl: 'https://cdn.example.com/lat.mp4',
          label: 'Xem Lat Pulldown — Rep 7 (0:19)',
          seekSec: 19.5,
          exerciseSlug: 'lat-pulldown',
          repIndex: 7,
        ),
        const VideoCitation(
          videoStoryId: 'story_row',
          videoUrl: 'https://cdn.example.com/row.mp4',
          label: 'Xem Cable Row — Rep 4 (1:15)',
          seekSec: 75.0,
          exerciseSlug: 'cable-row',
          repIndex: 4,
        ),
      ];

      final msg = ChatMessage(
        role: 'assistant',
        content: 'Bạn hơi ngả người ở rep cuối.',
        videoCitations: citations,
      );

      VideoCitation? tappedCitation;

      await tester.pumpWidget(
        wrapWidget(
          SamanAssistantResponse(
            message: msg,
            onCitationTap: (citation) => tappedCitation = citation,
          ),
        ),
      );

      expect(find.text('Xem Lat Pulldown — Rep 7 (0:19)'), findsOneWidget);
      expect(find.text('Xem Cable Row — Rep 4 (1:15)'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNWidgets(2));

      await tester.tap(find.text('Xem Lat Pulldown — Rep 7 (0:19)'));
      await tester.pump();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.videoStoryId, 'story_lat');
      expect(tappedCitation!.seekSec, 19.5);
    });
  });

  group('ChatController video citations parsing (SSE & history)', () {
    late Interceptor mockInterceptor;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'test_token'});
    });

    tearDown(() {
      ApiClient.dio.interceptors.remove(mockInterceptor);
    });

    test('parses SSE citations + done without duplicates', () async {
      final ssePayload = [
        'event: delta',
        'data: ${jsonEncode({'delta': 'Rep 7 hơi bị văng thân.'})}',
        '',
        'event: citations',
        'data: ${jsonEncode({
              'video_citations': [
                {
                  'video_story_id': 'story_1',
                  'video_url': 'https://cdn.example.com/lat.mp4',
                  'label': 'Xem Lat Pulldown — Rep 7 (0:19)',
                  'seek_sec': 19.5,
                  'rep_index': 7,
                },
              ],
            })}',
        '',
        'event: done',
        'data: ${jsonEncode({
              'conversation_id': 'conv_video_1',
              'video_citations': [
                {
                  'video_story_id': 'story_1',
                  'video_url': 'https://cdn.example.com/lat.mp4',
                  'label': 'Xem Lat Pulldown — Rep 7 (0:19)',
                  'seek_sec': 19.5,
                  'rep_index': 7,
                },
                {
                  'video_story_id': 'story_1',
                  'video_url': 'https://cdn.example.com/lat.mp4',
                  'label': 'Xem Lat Pulldown — Rep 9 (0:28)',
                  'seek_sec': 28.0,
                  'rep_index': 9,
                },
              ],
            })}',
        '',
      ].join('\n');

      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/api/chat/stream')) {
            final bytes = Uint8List.fromList(utf8.encode(ssePayload));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody.fromBytes(
                  bytes,
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['text/event-stream'],
                  },
                ),
              ),
            );
            return;
          }
          if (options.path.endsWith('/api/chat/conversations')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'conversations': []},
              ),
            );
            return;
          }
          handler.next(options);
        },
      );
      ApiClient.dio.interceptors.add(mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      await controller.sendMessageStreaming('Kiểm tra bài Lat Pulldown');

      final state = container.read(chatControllerProvider);
      expect(state.messages, hasLength(2));
      final assistantMsg = state.messages.last;
      expect(assistantMsg.role, 'assistant');
      expect(assistantMsg.content, 'Rep 7 hơi bị văng thân.');
      expect(assistantMsg.videoCitations, hasLength(2));
      expect(assistantMsg.videoCitations[0].repIndex, 7);
      expect(assistantMsg.videoCitations[0].seekSec, 19.5);
      expect(assistantMsg.videoCitations[1].repIndex, 9);
      expect(assistantMsg.videoCitations[1].seekSec, 28.0);
    });

    test('loadConversation restores video_citations from history messages',
        () async {
      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/api/chat/conversations/conv_hist_1')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'messages': [
                    {
                      'role': 'user',
                      'content': 'Form Squat hôm qua sao rồi?',
                    },
                    {
                      'role': 'assistant',
                      'content': 'Rep 3 gối hơi đổ vào trong.',
                      'video_citations': [
                        {
                          'video_story_id': 'story_sq',
                          'video_url': 'https://cdn.example.com/squat.mp4',
                          'label': 'Xem Squat — Rep 3 (1:15)',
                          'seek_sec': 75.0,
                          'exercise_slug': 'barbell-squat',
                          'rep_index': 3,
                        },
                      ],
                    },
                  ],
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      );
      ApiClient.dio.interceptors.add(mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      await controller.loadConversation('conv_hist_1');

      final state = container.read(chatControllerProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages.first.videoCitations, isEmpty);
      expect(state.messages.last.videoCitations, hasLength(1));
      expect(
        state.messages.last.videoCitations.first.label,
        'Xem Squat — Rep 3 (1:15)',
      );
      expect(state.messages.last.videoCitations.first.seekSec, 75.0);
    });

    test('updates live SSE status label before first delta and clears on delta',
        () async {
      final streamController = StreamController<Uint8List>();

      mockInterceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/api/chat/stream')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody(
                  streamController.stream,
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['text/event-stream'],
                  },
                ),
              ),
            );
            return;
          }
          if (options.path.endsWith('/api/chat/conversations')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'conversations': []},
              ),
            );
            return;
          }
          handler.next(options);
        },
      );
      ApiClient.dio.interceptors.add(mockInterceptor);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      final sendFuture =
          controller.sendMessageStreaming('Kiểm tra form Lat Pulldown');

      // Immediately after send: user message + typing placeholder with default status
      var state = container.read(chatControllerProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages.last.role, 'assistant');
      expect(state.messages.last.isTyping, isTrue);
      expect(state.messages.last.content, isEmpty);
      expect(state.messages.last.statusLabel, 'Analyzing your request...');

      // Emit retrieving status event
      streamController.add(
        Uint8List.fromList(
          utf8.encode(
            'event: status\n'
            'data: ${jsonEncode({'stage': 'retrieving', 'label': 'Retrieving workout & form data...'})}\n\n',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = container.read(chatControllerProvider);
      expect(state.messages.last.isTyping, isTrue);
      expect(
        state.messages.last.statusLabel,
        'Retrieving workout & form data...',
      );

      // Emit generating status event
      streamController.add(
        Uint8List.fromList(
          utf8.encode(
            'event: status\n'
            'data: ${jsonEncode({'stage': 'generating', 'label': 'Generating personalized insights...'})}\n\n',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = container.read(chatControllerProvider);
      expect(state.messages.last.isTyping, isTrue);
      expect(
        state.messages.last.statusLabel,
        'Generating personalized insights...',
      );

      // Emit first delta + done -> typing indicator and statusLabel clear immediately
      streamController.add(
        Uint8List.fromList(
          utf8.encode(
            'event: delta\n'
            'data: ${jsonEncode({'text': 'Rep 7 hơi nhanh.'})}\n\n'
            'event: done\n'
            'data: ${jsonEncode({'conversation_id': 'conv_status_1'})}\n\n',
          ),
        ),
      );
      await streamController.close();
      await sendFuture;

      state = container.read(chatControllerProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages.last.isTyping, isFalse);
      expect(state.messages.last.statusLabel, isNull);
      expect(state.messages.last.content, 'Rep 7 hơi nhanh.');
    });
  });

  group('SamanAssistantResponse loading dots & status label UI', () {
    Widget wrapWidget(Widget child, {Brightness brightness = Brightness.dark}) {
      return MaterialApp(
        theme: brightness == Brightness.dark
            ? ThemeData.dark()
            : ThemeData.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    }

    testWidgets(
        'shows animated typing dots with default English status and hides when delta arrives',
        (tester) async {
      final loadingMsg = ChatMessage(
        role: 'assistant',
        content: '',
        isTyping: true,
      );

      await tester.pumpWidget(
        wrapWidget(SamanAssistantResponse(message: loadingMsg)),
      );

      expect(find.byKey(const ValueKey('saman_typing_indicator')), findsOneWidget);
      expect(find.text('Analyzing your request...'), findsOneWidget);

      // Update status label live
      await tester.pumpWidget(
        wrapWidget(
          SamanAssistantResponse(
            message: loadingMsg.copyWith(
              statusLabel: 'Retrieving workout & form data...',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('saman_typing_indicator')), findsOneWidget);
      expect(find.text('Retrieving workout & form data...'), findsOneWidget);

      // First text delta arrives -> hides typing indicator, renders content + citations
      final streamedMsg = ChatMessage(
        role: 'assistant',
        content: 'Rep 7 bài Lat Pulldown hơi nhanh.',
        isTyping: false,
        videoCitations: const [
          VideoCitation(
            videoStoryId: 'story_lat',
            videoUrl: 'https://cdn.example.com/lat.mp4',
            label: 'Xem Lat Pulldown — Rep 7 (0:19)',
            seekSec: 19.5,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWidget(SamanAssistantResponse(message: streamedMsg)),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('saman_typing_indicator')), findsNothing);
      expect(find.text('Retrieving workout & form data...'), findsNothing);
      expect(find.text('Rep 7 bài Lat Pulldown hơi nhanh.'), findsOneWidget);
      expect(find.text('Xem Lat Pulldown — Rep 7 (0:19)'), findsOneWidget);
    });

    testWidgets('renders typing indicator cleanly in light theme',
        (tester) async {
      final loadingMsg = ChatMessage(
        role: 'assistant',
        content: '',
        isTyping: true,
        statusLabel: 'Checking muscle recovery & fatigue...',
      );

      await tester.pumpWidget(
        wrapWidget(
          SamanAssistantResponse(message: loadingMsg),
          brightness: Brightness.light,
        ),
      );

      expect(find.byKey(const ValueKey('saman_typing_indicator')), findsOneWidget);
      expect(find.text('Checking muscle recovery & fatigue...'), findsOneWidget);
    });
  });
}
