import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/community/data/datasources/community_dm_ws_service.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_dm.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_dm_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_social_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockDio extends Mock implements Dio {}

class FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> added = [];
  bool closed = false;

  @override
  void add(dynamic data) {
    added.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final item in stream) {
      added.add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  Future<void> get done => Future.value();
}

class FakeWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> incomingController =
      StreamController<dynamic>.broadcast();
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => incomingController.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  void emitJson(Map<String, dynamic> payload) {
    incomingController.add(jsonEncode(payload));
  }

  Future<void> dispose() async {
    await incomingController.close();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  group('Wave 4 Remote Datasource & Models (Mock Dio)', () {
    late MockDio mockDio;
    late CommunityRemoteDatasourceImpl datasource;
    late CommunityRepositoryImpl repository;

    setUp(() {
      mockDio = MockDio();
      datasource = CommunityRemoteDatasourceImpl(dio: mockDio);
      repository = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
        activeUserId: 'user_me',
      );
    });

    test('getSettings and updateSettings parse and PATCH correctly', () async {
      when(() => mockDio.get('/api/community/settings')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/community/settings'),
          statusCode: 200,
          data: {
            'is_private_account': true,
            'who_can_dm': 'followers',
            'who_can_comment': 'everyone',
            'hide_like_counts': true,
            'show_activity_status': false,
            'muted_keywords': ['spam', 'ads'],
          },
        ),
      );

      final settings = await repository.getSettings();
      expect(settings.isPrivateAccount, isTrue);
      expect(settings.whoCanDm, 'followers');
      expect(settings.hideLikeCounts, isTrue);
      expect(settings.showActivityStatus, isFalse);
      expect(settings.mutedKeywords, ['spam', 'ads']);

      when(
        () => mockDio.patch(
          '/api/community/settings',
          data: {'who_can_dm': 'nobody', 'hide_like_counts': false},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/community/settings'),
          statusCode: 200,
          data: {
            'is_private_account': true,
            'who_can_dm': 'nobody',
            'who_can_comment': 'everyone',
            'hide_like_counts': false,
            'show_activity_status': false,
            'muted_keywords': ['spam', 'ads'],
          },
        ),
      );

      final updated = await repository.updateSettings(
        whoCanDm: 'nobody',
        hideLikeCounts: false,
      );
      expect(updated.whoCanDm, 'nobody');
      expect(updated.hideLikeCounts, isFalse);
    });

    test('block, mute, lists, and reportContent work via HTTP', () async {
      when(() => mockDio.put('/api/community/users/u2/block')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'target_user_id': 'u2', 'is_blocked': true},
        ),
      );
      when(() => mockDio.delete('/api/community/users/u2/block')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'target_user_id': 'u2', 'is_blocked': false},
        ),
      );
      when(() => mockDio.get('/api/community/settings/blocked')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {'id': 'u2', 'name': 'User Two'}
            ],
            'total_count': 1,
          },
        ),
      );

      expect(await repository.blockUser('u2'), isTrue);
      expect((await repository.getBlockedUsers()).first.id, 'u2');
      expect(await repository.unblockUser('u2'), isFalse);

      when(() => mockDio.put('/api/community/users/u3/mute')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'target_user_id': 'u3', 'is_muted': true},
        ),
      );
      when(() => mockDio.delete('/api/community/users/u3/mute')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'target_user_id': 'u3', 'is_muted': false},
        ),
      );
      when(() => mockDio.get('/api/community/settings/muted')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {'id': 'u3', 'name': 'User Three'}
            ],
            'total_count': 1,
          },
        ),
      );

      expect(await repository.muteUser('u3'), isTrue);
      expect((await repository.getMutedUsers()).first.id, 'u3');
      expect(await repository.unmuteUser('u3'), isFalse);

      when(
        () => mockDio.post(
          '/api/community/reports',
          data: {
            'target_type': 'post',
            'target_id': 'p1',
            'reason': 'spam',
            'details': 'Spam link',
          },
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'report_id': 'rep_1',
            'target_type': 'post',
            'target_id': 'p1',
            'reason': 'spam',
            'status': 'received',
            'created_at': '2026-11-22T10:00:00Z',
            'already_reported': false,
          },
        ),
      );

      final receipt = await repository.reportContent(
        targetType: 'post',
        targetId: 'p1',
        reason: 'spam',
        details: 'Spam link',
      );
      expect(receipt.reportId, 'rep_1');
      expect(receipt.status, 'received');
    });

    test('stories 24h CRUD and post share + _parsePost fields', () async {
      when(() => mockDio.get('/api/community/stories')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'author': {'id': 'user_me', 'name': 'Me'},
                'is_self': true,
                'has_unviewed': true,
                'latest_created_at': '2026-11-22T10:00:00Z',
                'stories': [
                  {
                    'id': 'st_1',
                    'author_id': 'user_me',
                    'media_type': 'photo',
                    'media_url': '/static/community/story.jpg',
                    'caption': 'Morning run',
                    'privacy': 'public',
                    'created_at': '2026-11-22T10:00:00Z',
                    'expires_at': '2026-11-23T10:00:00Z',
                    'view_count': 3,
                    'is_viewed': false,
                  }
                ],
              }
            ],
          },
        ),
      );

      final groups = await repository.getStories();
      expect(groups.length, 1);
      expect(groups.first.isSelf, isTrue);
      expect(
        groups.first.stories.first.mediaUrl,
        '${ApiConfig.baseUrl}/static/community/story.jpg',
      );

      when(
        () => mockDio.post(
          '/api/community/stories',
          data: {
            'media_type': 'text',
            'caption': 'Hello',
            'background_color': '#112233',
            'privacy': 'public',
          },
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'id': 'st_2',
            'author_id': 'user_me',
            'media_type': 'text',
            'caption': 'Hello',
            'background_color': '#112233',
            'privacy': 'public',
            'created_at': '2026-11-22T10:05:00Z',
            'expires_at': '2026-11-23T10:05:00Z',
            'view_count': 0,
            'is_viewed': false,
          },
        ),
      );

      final created = await repository.createStory(
        mediaType: 'text',
        caption: 'Hello',
        backgroundColor: '#112233',
      );
      expect(created.id, 'st_2');

      when(() => mockDio.post('/api/community/stories/st_1/view')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'story_id': 'st_1', 'is_viewed': true, 'view_count': 4},
        ),
      );
      expect(await repository.markStoryViewed('st_1'), 4);

      when(() => mockDio.delete('/api/community/stories/st_1')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'success': true, 'story_id': 'st_1'},
        ),
      );
      expect(await repository.deleteStory('st_1'), isTrue);

      when(() => mockDio.post('/api/community/posts/post_1/share')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'post_id': 'post_1', 'share_count': 7},
        ),
      );
      expect(await repository.sharePost('post_1'), 7);

      when(
        () => mockDio.get(
          '/api/community/feed',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'post_1',
                'type': 'text',
                'author': {'id': 'u1', 'name': 'A'},
                'time_ago': '1m',
                'caption': 'Hi',
                'like_count': 10,
                'share_count': 7,
                'is_like_count_hidden': true,
              }
            ],
          },
        ),
      );
      final feed = await repository.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(feed.first.shareCount, 7);
      expect(feed.first.isLikeCountHidden, isTrue);
    });

    test('DM endpoints, media upload, URL resolution, and message types', () async {
      when(
        () => mockDio.post(
          '/api/community/dm/media/upload',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'media_url': '/static/community_dm/voice1.m4a',
            'media_kind': 'audio',
            'content_type': 'audio/mp4',
            'file_name': 'voice1.m4a',
            'size_bytes': 1234,
          },
        ),
      );

      final upload = await repository.uploadDmMedia(
        bytes: [1, 2, 3, 4],
        filename: 'voice1.m4a',
        mimeType: 'audio/mp4',
      );
      expect(
        upload.mediaUrl,
        '${ApiConfig.baseUrl}/static/community_dm/voice1.m4a',
      );
      expect(upload.mediaKind, 'audio');

      when(
        () => mockDio.post(
          '/api/community/dm/conversations',
          data: {'target_user_id': 'peer_1'},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'id': 'conv_1',
            'peer': {
              'id': 'peer_1',
              'name': 'Peer One',
              'avatar_url': '/static/community/avatar.jpg',
              'is_verified': true,
              'show_activity_status': true,
            },
            'last_message_preview': '',
            'unread_count': 0,
            'updated_at': '2026-11-22T10:00:00Z',
          },
        ),
      );
      final conv = await repository.createOrGetConversation('peer_1');
      expect(conv.id, 'conv_1');
      expect(conv.peer.avatarUrl, '${ApiConfig.baseUrl}/static/community/avatar.jpg');

      when(
        () => mockDio.get(
          '/api/community/dm/conversations',
          queryParameters: {'limit': 20},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'conv_1',
                'peer': {'id': 'peer_1', 'name': 'Peer One'},
                'last_message_preview': 'Hello',
                'last_message_type': 'text',
                'last_message_at': '2026-11-22T10:05:00Z',
                'unread_count': 2,
                'updated_at': '2026-11-22T10:05:00Z',
              }
            ],
            'total_unread_count': 2,
          },
        ),
      );
      final convPage = await repository.getConversations();
      expect(convPage.totalUnreadCount, 2);

      when(
        () => mockDio.get(
          '/api/community/dm/conversations/conv_1/messages',
          queryParameters: {'limit': 30},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'm_text',
                'conversation_id': 'conv_1',
                'sender_id': 'peer_1',
                'type': 'text',
                'content': 'Hi',
                'created_at': '2026-11-22T10:01:00Z',
              },
              {
                'id': 'm_voice',
                'conversation_id': 'conv_1',
                'sender_id': 'user_me',
                'type': 'voice',
                'media_url': '/static/community_dm/v.m4a',
                'duration_seconds': 5.5,
                'created_at': '2026-11-22T10:02:00Z',
              },
              {
                'id': 'm_photo',
                'conversation_id': 'conv_1',
                'sender_id': 'user_me',
                'type': 'photo',
                'media_url': '/static/community_dm/p.jpg',
                'created_at': '2026-11-22T10:03:00Z',
              },
              {
                'id': 'm_video',
                'conversation_id': 'conv_1',
                'sender_id': 'user_me',
                'type': 'video',
                'media_url': '/static/community_dm/v.mp4',
                'duration_seconds': 12.0,
                'created_at': '2026-11-22T10:04:00Z',
              },
              {
                'id': 'm_share',
                'conversation_id': 'conv_1',
                'sender_id': 'user_me',
                'type': 'post_share',
                'shared_post_id': 'post_1',
                'shared_post_preview': {
                  'id': 'post_1',
                  'type': 'photo',
                  'author_name': 'Linh',
                  'caption': 'Lunch',
                  'thumbnail_url': '/static/community/thumb.jpg',
                },
                'created_at': '2026-11-22T10:05:00Z',
              },
            ],
          },
        ),
      );
      final msgs = await repository.getMessages('conv_1');
      expect(msgs.items.length, 5);
      expect(msgs.items[0].type, DmMessageType.text);
      expect(msgs.items[1].type, DmMessageType.voice);
      expect(
        msgs.items[1].mediaUrl,
        '${ApiConfig.baseUrl}/static/community_dm/v.m4a',
      );
      expect(msgs.items[2].type, DmMessageType.photo);
      expect(msgs.items[3].type, DmMessageType.video);
      expect(msgs.items[4].type, DmMessageType.postShare);
      expect(
        msgs.items[4].sharedPostPreview?.thumbnailUrl,
        '${ApiConfig.baseUrl}/static/community/thumb.jpg',
      );

      when(
        () => mockDio.post(
          '/api/community/dm/conversations/conv_1/messages',
          data: {
            'type': 'post_share',
            'content': '',
            'shared_post_id': 'post_1',
          },
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'id': 'm_new',
            'conversation_id': 'conv_1',
            'sender_id': 'user_me',
            'type': 'post_share',
            'shared_post_id': 'post_1',
            'created_at': '2026-11-22T10:06:00Z',
          },
        ),
      );
      final sent = await repository.sendMessage(
        conversationId: 'conv_1',
        type: DmMessageType.postShare,
        sharedPostId: 'post_1',
        idempotencyKey: 'key_123',
      );
      expect(sent.id, 'm_new');

      when(() => mockDio.post('/api/community/dm/conversations/conv_1/read'))
          .thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'conversation_id': 'conv_1', 'unread_count': 0},
        ),
      );
      await repository.markConversationRead('conv_1');

      when(() => mockDio.get('/api/community/dm/unread-count')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'unread_count': 4},
        ),
      );
      expect(await repository.getDmUnreadCount(), 4);
    });
  });

  group('WebSocket Service, Thread Notifier & User Isolation Reset', () {
    test('CommunityDmWsService builds ws/wss URI and handles events + disconnect',
        () async {
      expect(
        CommunityDmWsService.buildWsUri('http://10.0.2.2:18090', 'tok1').toString(),
        'ws://10.0.2.2:18090/api/community/ws/chat?token=tok1',
      );
      expect(
        CommunityDmWsService.buildWsUri('https://api.saman.vn/', 'tok2')
            .toString(),
        'wss://api.saman.vn/api/community/ws/chat?token=tok2',
      );

      final fakeChannel = FakeWebSocketChannel();
      final service = CommunityDmWsService(
        baseUrl: 'http://localhost:8000',
        channelFactory: (_) => fakeChannel,
        tokenProvider: () async => 'jwt_abc',
      );

      final received = <DmWsEvent>[];
      final sub = service.events.listen(received.add);

      await service.connect();
      expect(service.isConnected, isTrue);

      service.sendTyping('conv_1', true);
      expect(fakeChannel.fakeSink.added.length, 1);
      final sentJson =
          jsonDecode(fakeChannel.fakeSink.added.first as String) as Map;
      expect(sentJson['event'], 'typing');
      expect(sentJson['conversation_id'], 'conv_1');
      expect(sentJson['is_typing'], isTrue);

      fakeChannel.emitJson({
        'event': 'message.created',
        'conversation_id': 'conv_1',
        'message': {
          'id': 'ws_m1',
          'conversation_id': 'conv_1',
          'sender_id': 'peer_1',
          'type': 'voice',
          'media_url': '/static/community_dm/a.m4a',
          'created_at': '2026-11-22T10:10:00Z',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      expect(received.first.event, 'message.created');
      expect(
        received.first.message?.mediaUrl,
        'http://localhost:8000/static/community_dm/a.m4a',
      );

      await service.disconnect();
      expect(service.isConnected, isFalse);
      expect(fakeChannel.fakeSink.closed, isTrue);

      await sub.cancel();
      await service.dispose();
      await fakeChannel.dispose();
    });

    test(
        'CommunityChatThreadNotifier dedups WS message, handles typing/read/delete, and resetCommunityStateInContainer clears all Wave 4 state',
        () async {
      final mockDio = MockDio();
      final fakeChannel = FakeWebSocketChannel();
      final wsService = CommunityDmWsService(
        baseUrl: 'http://localhost:8000',
        channelFactory: (_) => fakeChannel,
        tokenProvider: () async => 'jwt_user_a',
      );
      await wsService.connect();

      final remoteDs = CommunityRemoteDatasourceImpl(dio: mockDio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: remoteDs,
        useRemote: true,
        activeUserId: 'user_a',
      );

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
          communityDmWsServiceProvider.overrideWithValue(wsService),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await fakeChannel.dispose();
      });

      // Populate settings & stories
      when(() => mockDio.get('/api/community/settings')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {'is_private_account': true, 'who_can_dm': 'followers'},
        ),
      );
      await container.read(communitySettingsProvider.notifier).loadSettings();
      expect(
        container.read(communitySettingsProvider).settings.isPrivateAccount,
        isTrue,
      );

      when(() => mockDio.get('/api/community/stories')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'author': {'id': 'user_a', 'name': 'User A'},
                'is_self': true,
                'has_unviewed': true,
                'stories': [
                  {
                    'id': 's1',
                    'author_id': 'user_a',
                    'media_type': 'text',
                    'caption': 'Hi',
                    'created_at': '2026-11-22T10:00:00Z',
                    'expires_at': '2026-11-23T10:00:00Z',
                  }
                ],
              }
            ],
          },
        ),
      );
      await container.read(communityStoriesProvider.notifier).loadStories();
      expect(container.read(communityStoriesProvider).groups.length, 1);

      // Populate inbox & unread
      when(
        () => mockDio.get(
          '/api/community/dm/conversations',
          queryParameters: {'limit': 20},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'conv_1',
                'peer': {'id': 'peer_1', 'name': 'Peer'},
                'last_message_preview': 'Yo',
                'unread_count': 3,
                'updated_at': '2026-11-22T10:00:00Z',
              }
            ],
            'total_unread_count': 3,
          },
        ),
      );
      await container.read(communityInboxProvider.notifier).loadConversations();
      expect(container.read(communityDmUnreadProvider), 3);

      // Send message optimistically and dedup with WS message.created
      when(
        () => mockDio.post(
          '/api/community/dm/conversations/conv_1/messages',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'id': 'msg_100',
            'conversation_id': 'conv_1',
            'sender_id': 'user_a',
            'type': 'text',
            'content': 'Hello WS',
            'created_at': '2026-11-22T10:12:00Z',
          },
        ),
      );

      final threadNotifier =
          container.read(communityChatThreadProvider('conv_1').notifier);
      final sent = await threadNotifier.sendMessage(
        type: DmMessageType.text,
        content: 'Hello WS',
      );
      expect(sent?.id, 'msg_100');
      expect(
        container.read(communityChatThreadProvider('conv_1')).messages.length,
        1,
      );

      // Duplicate WS message.created for msg_100 must NOT duplicate
      fakeChannel.emitJson({
        'event': 'message.created',
        'conversation_id': 'conv_1',
        'message': {
          'id': 'msg_100',
          'conversation_id': 'conv_1',
          'sender_id': 'user_a',
          'type': 'text',
          'content': 'Hello WS',
          'created_at': '2026-11-22T10:12:00Z',
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(communityChatThreadProvider('conv_1')).messages.length,
        1,
      );

      // Typing & message.deleted WS events
      fakeChannel.emitJson({
        'event': 'typing',
        'conversation_id': 'conv_1',
        'user_id': 'peer_1',
        'is_typing': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(communityChatThreadProvider('conv_1')).peerIsTyping,
        isTrue,
      );

      fakeChannel.emitJson({
        'event': 'message.deleted',
        'conversation_id': 'conv_1',
        'message_id': 'msg_100',
        'deleted_by': 'user_a',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(communityChatThreadProvider('conv_1'))
            .messages
            .first
            .isDeleted,
        isTrue,
      );

      // Reset community state for user isolation
      resetCommunityStateInContainer(container, 'user_b');
      await Future<void>.delayed(Duration.zero);

      expect(wsService.isConnected, isFalse);
      expect(fakeChannel.fakeSink.closed, isTrue);
      expect(
        container.read(communitySettingsProvider).settings.isPrivateAccount,
        isFalse,
      );
      expect(container.read(communityStoriesProvider).groups, isEmpty);
      expect(container.read(communityInboxProvider).conversations, isEmpty);
      expect(container.read(communityDmUnreadProvider), 0);
      expect(
        container.read(communityChatThreadProvider('conv_1')).messages,
        isEmpty,
      );
    });
  });
}
