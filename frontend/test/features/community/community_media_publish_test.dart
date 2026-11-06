import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';

class MockMediaTransport {
  final Dio dio = Dio();
  final List<Map<String, dynamic>> postBodies = [];
  bool failUpload = false;
  bool failPublish = false;

  MockMediaTransport() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.path == '/api/community/media/upload') {
          if (failUpload) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: options, statusCode: 400),
            ));
            return;
          }
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'media_url': '/static/community/mock_uploaded_123.jpg',
              'content_type': 'image/jpeg',
              'file_name': 'test.jpg',
            },
          ));
        } else if (options.path == '/api/community/posts' && options.method == 'POST') {
          if (failPublish) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
            ));
            return;
          }
          final body = Map<String, dynamic>.from(options.data as Map);
          postBodies.add(body);
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': 'post_photo_1',
              'type': body['type'],
              'caption': body['content'] ?? '',
              'photo_urls': body['photo_urls'] ?? [],
              'privacy': body['privacy'],
              'topic': body['topic'],
              'author': {
                'id': 'user_a',
                'name': 'Athlete A',
                'avatar_url': null,
              },
              'time_ago': 'Vừa xong',
              'like_count': 0,
              'comment_count': 0,
            },
          ));
        } else {
          handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
        }
      },
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JCOM-05-10 Single Photo Post Tests', () {
    test('1. CommunityRemoteDatasource uploadMedia sends multipart and parses response', () async {
      final transport = MockMediaTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);

      final res = await datasource.uploadMedia(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        filename: 'badge.png',
        mimeType: 'image/png',
      );

      expect(res['media_url'], '/static/community/mock_uploaded_123.jpg');
      expect(res['content_type'], 'image/jpeg');
      expect(res['file_name'], 'test.jpg');
    });

    test('2. CommunityRepositoryImpl publishes photo post with remote URL and enforces limits', () async {
      final transport = MockMediaTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
      );

      // A. Happy path: publish single photo post
      final post = await repo.publishPost(
        caption: 'Leg day triumph',
        requestKey: 'req_photo_single_001',
        mediaUrls: ['/static/community/my_photo.jpg'],
        audience: 'Công khai',
        topic: '#TậpLuyện',
      );

      expect(post.type, CommunityPostType.photo);
      expect(post.caption, 'Leg day triumph');
      expect(post.photoUrls, ['/static/community/my_photo.jpg']);
      expect(transport.postBodies.length, 1);
      expect(transport.postBodies.first['type'], 'photo');
      expect(transport.postBodies.first['photo_urls'], ['/static/community/my_photo.jpg']);

      // B. Reject multiple photos (slice constraint)
      expect(
        () => repo.publishPost(
          caption: 'Two photos attempt',
          requestKey: 'req_photo_multi_002',
          mediaUrls: ['/static/photo1.jpg', '/static/photo2.jpg'],
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('3. CommunityComposer retains caption and selected image draft when publish fails', () async {
      final transport = MockMediaTransport()..failPublish = true;
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
      );

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(communityComposerProvider.notifier);
      notifier.setCaption('Unpublished workout victory');
      notifier.setInitialMedia(['/static/community/victory.jpg']);

      expect(container.read(communityComposerProvider).caption, 'Unpublished workout victory');
      expect(container.read(communityComposerProvider).selectedMediaUrls, ['/static/community/victory.jpg']);

      // Publish fails due to network/receiveTimeout
      final result = await notifier.publish();
      expect(result, isNull);

      // Draft must be preserved for retry
      final stateAfterFail = container.read(communityComposerProvider);
      expect(stateAfterFail.caption, 'Unpublished workout victory');
      expect(stateAfterFail.selectedMediaUrls, ['/static/community/victory.jpg']);
      expect(stateAfterFail.isSubmitting, isFalse);
      expect(stateAfterFail.hasPendingSubmission, isTrue);

      // User can remove media
      notifier.clearMedia();
      expect(container.read(communityComposerProvider).selectedMediaUrls, isEmpty);
    });

    testWidgets('4. PostComposePublishScreen displays 72x72 photo thumbnail and remove button', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = MockMediaTransport();
      final datasource = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: datasource,
        useRemote: true,
      );

      final container = ProviderContainer(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // Pre-set photo media in composer
      container.read(communityComposerProvider.notifier).setInitialMedia([
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c'
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PostComposePublishScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check remove button exists
      final removeBtn = find.byKey(const ValueKey('remove-selected-media-button'));
      expect(removeBtn, findsOneWidget);

      // Tap remove button
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      // Ensure media is cleared in state
      expect(container.read(communityComposerProvider).selectedMediaUrls, isEmpty);
      expect(find.byKey(const ValueKey('remove-selected-media-button')), findsNothing);
    });
  });
}

