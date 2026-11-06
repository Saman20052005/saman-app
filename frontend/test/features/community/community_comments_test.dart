import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';

// Controlled transport faults only. Real persistence/concurrency is covered by Mongo tests.
class CommentTransport {
  final Dio dio = Dio();
  final Map<String, Map<String, dynamic>> stored = {};
  final List<String> keys = [];
  bool loseResponse = false;
  bool rejectWrite = false;
  bool failRead = false;
  Completer<void>? holdWrite;
  Map<String, dynamic> get post => {
    'id': 'post', 'type': 'photo', 'author': {'id':'owner','name':'Owner'},
    'caption':'Post', 'time_ago':'Today','comment_count':stored.length,
  };
  CommentTransport() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      Object data;
      if (options.method == 'POST') {
        final key = options.headers['X-Idempotency-Key'] as String;
        keys.add(key);
        if (rejectWrite) {
          handler.reject(DioException(requestOptions: options,
            response: Response(requestOptions: options,statusCode:422),type:DioExceptionType.badResponse));
          return;
        }
        final body=options.data as Map;
        final comment=stored.putIfAbsent(key, () => {
          'id':'c${stored.length}', 'author':{'id':'a','name':'Canonical A'},
          'content':body['content'],'parent_comment_id':body['parent_comment_id'],
          'created_at':'2026-11-02T00:00:00Z','time_ago':'2026-11-02T00:00:00Z',
        });
        if (holdWrite != null) await holdWrite!.future;
        if (loseResponse) {
          handler.reject(DioException(requestOptions:options,type:DioExceptionType.receiveTimeout));
          return;
        }
        data={'comment':comment,'comment_count':stored.length};
      } else if (options.path.endsWith('/comments')) {
        if (failRead) {
          handler.reject(DioException(requestOptions:options,type:DioExceptionType.connectionError));
          return;
        }
        final offset=options.queryParameters['cursor']==null ? 0 : int.parse(options.queryParameters['cursor'] as String);
        final items=stored.values.skip(offset).take(20).toList();
        data={'items':items,'next_cursor':offset+items.length<stored.length ? '${offset+items.length}' : null,
          'comment_count':stored.length};
      } else if (options.path.endsWith('/feed')) {
        data={'items':[post]};
      } else {
        data=post;
      }
      handler.resolve(Response(requestOptions:options,statusCode:200,data:data));
    }));
  }
}

Future<void> settleCalls() async {
  for (var i=0; i<12; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  late CommentTransport transport;
  late ProviderContainer container;
  late CommunityPostDetailNotifier notifier;
  setUp(() async {
    transport=CommentTransport();
    container=ProviderContainer(overrides:[
      useRemoteCommunityProvider.overrideWith((ref)=>true),
      communityRemoteDatasourceProvider.overrideWithValue(CommunityRemoteDatasourceImpl(dio:transport.dio)),
    ]);
    container.read(communityFeedProvider);
    notifier=container.read(communityPostDetailProvider('post').notifier);
    await settleCalls();
  });
  tearDown(() { container.dispose(); transport.dio.close(); });

  test('canonical comment/reply, feed count, reload and ID reconciliation',() async {
    expect(await notifier.submitComment('  root  '),isTrue);
    var state=notifier.state;
    expect(state.post!.comments.single.author.name,'Canonical A');
    expect(state.post!.comments.single.content,'root');
    final root=state.post!.comments.single.id;
    notifier.setReplyTarget('Canonical A',root);
    expect(await notifier.submitComment('reply'),isTrue);
    state=notifier.state;
    expect(state.post!.comments.single.replies.single.content,'reply');
    expect(state.post!.commentCount,2);
    expect(container.read(communityFeedProvider).posts.single.commentCount,2);
    await notifier.loadComments();
    await notifier.loadComments();
    expect(notifier.state.post!.comments,hasLength(1));
    expect(notifier.state.post!.comments.single.replies,hasLength(1));
    expect(notifier.state.draft,isEmpty);
    expect(notifier.state.replyToCommentId,isNull);
  });

  test('double tap sends exactly one operation',() async {
    transport.holdWrite=Completer<void>();
    final first=notifier.submitComment('once');
    await settleCalls();
    expect(await notifier.submitComment('once'),isFalse);
    expect(transport.keys,hasLength(1));
    transport.holdWrite!.complete();
    expect(await first,isTrue);
    expect(transport.stored,hasLength(1));
  });

  test('persist then timeout keeps draft/target/key and retry deduplicates',() async {
    await notifier.submitComment('root');
    final root=notifier.state.post!.comments.single.id;
    notifier.setReplyTarget('Canonical A',root);
    transport.loseResponse=true;
    expect(await notifier.submitComment('uncertain reply'),isFalse);
    final key=transport.keys.last;
    expect(notifier.state.hasPendingSubmission,isTrue);
    expect(notifier.state.draft,'uncertain reply');
    expect(notifier.state.replyToCommentId,root);
    expect(notifier.state.commentErrorKey,'community_comment_unconfirmed');
    notifier.updateInteraction(isLiked: true);
    expect(notifier.state.commentErrorKey,'community_comment_unconfirmed');
    notifier.cancelReply();
    notifier.updateDraft('different text');
    expect(notifier.state.draft,'uncertain reply');
    expect(notifier.state.replyToCommentId,root);
    transport.loseResponse=false;
    expect(await notifier.submitComment('different text'),isTrue);
    expect(transport.keys.last,key);
    expect(transport.stored,hasLength(2));
    expect(notifier.state.post!.commentCount,2);
    await notifier.loadComments();
    expect(notifier.state.post!.comments.single.replies,hasLength(1));
  });

  test('a later rejection cannot discard an earlier unknown commit key',() async {
    transport.loseResponse=true;
    expect(await notifier.submitComment('unknown commit'),isFalse);
    final originalKey=transport.keys.single;
    transport.loseResponse=false;
    transport.rejectWrite=true;
    expect(await notifier.submitComment('unknown commit'),isFalse);
    expect(notifier.state.hasPendingSubmission,isTrue);
    expect(notifier.state.draft,'unknown commit');
    notifier.updateDraft('replacement');
    expect(notifier.state.draft,'unknown commit');
    transport.rejectWrite=false;
    expect(await notifier.submitComment('replacement'),isTrue);
    expect(transport.keys.toSet(),{originalKey});
    expect(transport.stored,hasLength(1));
  });

  test('definitive rejection preserves editable draft and reply cancellation keeps text',() async {
    await notifier.submitComment('root');
    notifier.setReplyTarget('Canonical A',notifier.state.post!.comments.single.id);
    transport.rejectWrite=true;
    expect(await notifier.submitComment('draft'),isFalse);
    expect(notifier.state.draft,'draft');
    expect(notifier.state.replyToCommentId,isNotNull);
    expect(notifier.state.hasPendingSubmission,isFalse);
    notifier.cancelReply();
    expect(notifier.state.draft,'draft');
    expect(notifier.state.replyToCommentId,isNull);
    notifier.updateDraft('edited');
    transport.rejectWrite=false;
    expect(await notifier.submitComment('edited'),isTrue);
    expect(notifier.state.post!.comments.last.content,'edited');
  });

  test('account switch discards late write response and private composer state',() async {
    transport.holdWrite=Completer<void>();
    final old=notifier.submitComment('A private draft');
    await settleCalls();
    resetCommunityStateInContainer(container,'b');
    transport.stored.clear();
    final next=container.read(communityPostDetailProvider('post').notifier);
    await settleCalls();
    expect(next.state.draft,isEmpty);
    expect(next.state.replyToCommentId,isNull);
    transport.holdWrite!.complete();
    expect(await old,isFalse);
    expect(next.state.draft,isEmpty);
    expect(next.state.post!.comments,isEmpty);
    expect((container.read(communityRepositoryProvider) as CommunityRepositoryImpl).commentCountFor('post'),0);
  });

  test('flat pagination exposes all roots and replies without duplicates',() async {
    for (var i=0;i<23;i++) {
      transport.stored['seed$i']={'id':'s$i','author':{'id':'a','name':'A'},'content':'seed $i',
        'parent_comment_id':i==22?'s0':null,'time_ago':'today'};
    }
    await notifier.loadComments();
    expect(notifier.state.commentsCursor,'20');
    await notifier.loadComments(more:true);
    expect(notifier.state.commentsCursor,isNull);
    expect(notifier.state.post!.comments,hasLength(22));
    expect(notifier.state.post!.comments.first.replies,hasLength(1));
    expect(notifier.state.post!.commentCount,23);
  });

  testWidgets('reply banner preserves active editing connection after first send',(tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container:container,
      child:const MaterialApp(home:CommunityPostDetailScreen(postId:'post'))));
    await tester.pumpAndSettle();
    final field=find.byKey(const ValueKey('community-comment-input'));
    await tester.enterText(field,'root from widget');
    await tester.tap(find.byKey(const ValueKey('community-comment-send')));
    await tester.pumpAndSettle();
    expect(notifier.state.post!.commentCount,1);
    final root=notifier.state.post!.comments.single.id;
    final beforeField=tester.widget<TextField>(field);
    expect(beforeField.readOnly,isFalse);
    final beforeEditor=tester.state<EditableTextState>(find.byType(EditableText));
    await tester.tap(find.text('Tr\u1ea3 l\u1eddi'));
    await tester.pumpAndSettle();
    final afterField=tester.widget<TextField>(field);
    expect(afterField.controller,same(beforeField.controller));
    expect(afterField.focusNode,same(beforeField.focusNode));
    expect(tester.state<EditableTextState>(find.byType(EditableText)),same(beforeEditor),
        reason:'Adding the reply banner must preserve the active editor subtree');
    expect(afterField.focusNode!.hasFocus,isTrue);
    expect(afterField.readOnly,isFalse);
    expect(afterField.enabled,isTrue);
    expect(notifier.state.isSubmitting,isFalse);
    expect(notifier.state.hasPendingSubmission,isFalse);
    expect(tester.testTextInput.hasAnyClients,isTrue);
    // Use the connection opened by tapping Reply; showKeyboard/enterText would
    // reconnect a broken editor and mask this lifecycle regression.
    tester.testTextInput.enterText('reply through existing connection');
    await tester.pump();
    expect(afterField.controller!.text,'reply through existing connection');
    await tester.tap(find.byKey(const ValueKey('community-comment-send')));
    await tester.pumpAndSettle();
    expect(transport.stored.values.last['parent_comment_id'],root);
    expect(notifier.state.post!.comments.single.replies.single.content,
        'reply through existing connection');
    expect(notifier.state.post!.commentCount,2);
    expect(tester.state<EditableTextState>(find.byType(EditableText)),same(beforeEditor),
        reason:'Removing the reply banner must also retain the editor subtree');
  });

  testWidgets('account switch clears visible composer text and reply target',(tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container:container,
      child:const MaterialApp(home:CommunityPostDetailScreen(postId:'post'))));
    await tester.pumpAndSettle();
    final field=find.byKey(const ValueKey('community-comment-input'));
    await tester.enterText(field,'A private text');
    notifier.setReplyTarget('A private target','private-root');
    await tester.pump();
    resetCommunityStateInContainer(container,'b');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,isEmpty);
    expect(find.textContaining('A private target'),findsNothing);
    expect(find.text('A private text'),findsNothing);
  });

  testWidgets('comment load retry invokes read recovery without sending draft',(tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container:container,
      child:const MaterialApp(home:CommunityPostDetailScreen(postId:'post'))));
    await tester.pumpAndSettle();
    transport.failRead=true;
    await tester.runAsync(() => notifier.loadComments());
    await tester.pumpAndSettle();
    expect(find.text('Cannot load comments. Please retry.'),findsOneWidget);
    transport.failRead=false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(notifier.state.commentErrorKey,isNull);
    expect(transport.keys,isEmpty);
  });

  testWidgets('composer keeps draft on timeout, retry succeeds and stays above keyboard',(tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(container:container,
      child:const MaterialApp(home:CommunityPostDetailScreen(postId:'post'))));
    await tester.pumpAndSettle();
    final field=find.byKey(const ValueKey('community-comment-input'));
    await tester.enterText(field,'widget draft');
    transport.loseResponse=true;
    await tester.tap(find.byKey(const ValueKey('community-comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('Sending is unconfirmed. Retry safely with the same request.'),findsOneWidget);
    expect(find.text('widget draft'),findsOneWidget);
    transport.loseResponse=false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(transport.stored,hasLength(1));
    expect(tester.widget<TextField>(field).controller!.text,isEmpty);
    tester.view.viewInsets=const FakeViewPadding(bottom:300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.getRect(field).bottom,lessThanOrEqualTo(
      (tester.view.physicalSize.height-tester.view.viewInsets.bottom)/tester.view.devicePixelRatio));
    expect(tester.takeException(),isNull);
  });
}
