import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_ask_question_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/create_content_bottom_sheet.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_select_attachment_screen.dart';

// Controlled HTTP simulation; real persistence is independently verified with MongoDB.
class PublishTransport {
  final Dio dio=Dio();
  final Map<String,Map<String,dynamic>> posts={};
  final List<String> keys=[];
  final List<Map> bodies=[];
  bool lose=false, reject=false, failFeed=false;
  Completer<void>? holdWrite,holdFeed;
  PublishTransport() {
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async {
      if(o.method=='POST') {
        final body=Map<String,dynamic>.from(o.data as Map); bodies.add(body);
        final key=o.headers['X-Idempotency-Key'] as String; keys.add(key);
        if(reject) { h.reject(DioException(requestOptions:o,type:DioExceptionType.badResponse,
          response:Response(requestOptions:o,statusCode:422))); return; }
        final post=posts.putIfAbsent(key,()=>{'id':'canonical${posts.length}','type':body['type'],
          'author':{'id':'canonical-author','name':'Server author'},'caption':body['type']=='qa' ? '' : body['content'],
          if(body['type']=='qa') 'qa_info':{'question':body['title'],'details':body['body'],'category_tag':body['topic'],'respondent_count':0},
          'privacy':body['privacy'],'topic':body['topic'],'comment_count':0,'like_count':0});
        if(holdWrite!=null)await holdWrite!.future;
        if(lose) { h.reject(DioException(requestOptions:o,type:DioExceptionType.receiveTimeout)); return; }
        h.resolve(Response(requestOptions:o,statusCode:200,data:post));
      } else {
        final data={'items':posts.values.toList()};
        if(holdFeed!=null)await holdFeed!.future;
        if(failFeed){h.reject(DioException(requestOptions:o,type:DioExceptionType.connectionError));return;}
        h.resolve(Response(requestOptions:o,statusCode:200,data:data));
      }
    }));
  }
}
Future<void> drain() async {for(var i=0;i<20;i++){await Future<void>.delayed(Duration.zero);}}
void main() {
  late PublishTransport t;
  late CommunityRepositoryImpl repo;
  late ProviderContainer c;
  late CommunityComposerNotifier n;
  setUp(() {
    t=PublishTransport(); repo=CommunityRepositoryImpl(useRemote:true,remoteDatasource:CommunityRemoteDatasourceImpl(dio:t.dio));
    c=ProviderContainer(overrides:[communityRepositoryProvider.overrideWithValue(repo),useRemoteCommunityProvider.overrideWith((ref)=>true)]);
    n=c.read(communityComposerProvider.notifier);
  });
  tearDown(()=>c.dispose());
  test('canonical text publication, audience and Feed upsert',() async {
    n.setCaption('  text  '); n.setAudience('private');
    final post=await n.publish(); expect(post!.id,'canonical0'); expect(post.type,CommunityPostType.text);
    expect(post.author.id,'canonical-author'); expect(post.privacy,'private');
    expect(t.bodies.single.keys.toSet(),{'type','content','privacy','topic','allow_comments'});
    expect(t.bodies.single['content'],'text'); expect(c.read(communityComposerProvider).caption,isEmpty);
    c.read(communityFeedProvider.notifier).acceptPublished(post);
    expect(c.read(communityFeedProvider).posts.length,1);
  });
  test('persisted response loss freezes payload/key, retry returns same ID',() async {
    n.setCaption('frozen'); n.setAudience('followers_only'); final topic=c.read(communityComposerProvider).topic;
    t.lose=true; expect(await n.publish(),isNull);
    final s=c.read(communityComposerProvider); expect(s.hasPendingSubmission,isTrue); expect(s.errorMessage,'community_publish_unconfirmed');
    n.setCaption('replacement'); n.setAudience('public'); n.setTopic('different');
    expect(c.read(communityComposerProvider).caption,'frozen'); expect(c.read(communityComposerProvider).audience,'followers_only');
    t.lose=false; final result=await n.publish(); expect(result!.id,'canonical0');
    expect(t.keys.length,2); expect(t.keys.toSet().length,1); expect(t.posts.length,1);
    expect(t.bodies.last['topic'],topic); expect(c.read(communityFeedProvider).posts.length,1);
  });
  test('initial validation rejection keeps editable content and unknown key survives later rejection',() async {
    n.setCaption('kept'); t.reject=true; await n.publish();
    expect(c.read(communityComposerProvider).caption,'kept'); expect(c.read(communityComposerProvider).hasPendingSubmission,isFalse);
    t.reject=false; t.lose=true; await n.publish(); final key=t.keys.last;
    t.reject=true; t.lose=false; await n.publish(); expect(t.keys.last,key);
    expect(c.read(communityComposerProvider).hasPendingSubmission,isTrue);
  });
  test('double tap locked and stale refetch cannot replace canonical Feed item',() async {
    t.holdFeed=Completer<void>(); final fetch=c.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou); await drain();
    n.setCaption('one'); t.holdWrite=Completer<void>(); final send=n.publish(); await drain();
    expect(await n.publish(),isNull); expect(t.keys.length,1);
    t.holdWrite!.complete(); await send; t.holdFeed!.complete(); await fetch;
    expect(c.read(communityFeedProvider).posts.single.id,'canonical0');
  });
  test('stale failed refetch cannot hide confirmed publication',() async {
    t.holdFeed=Completer<void>(); final fetch=c.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.forYou); await drain();
    n.setCaption('canonical despite old failure'); await n.publish();
    t.failFeed=true; t.holdFeed!.complete(); await fetch;
    expect(c.read(communityFeedProvider).errorMessage,isNull);
    expect(c.read(communityFeedProvider).posts.single.id,'canonical0');
  });
  test('late A response cannot update B state or Feed',() async {
    n.setCaption('A private'); t.holdWrite=Completer<void>(); final send=n.publish(); await drain();
    resetCommunityStateInContainer(c,'B'); final b=c.read(communityComposerProvider.notifier); b.setCaption('B draft');
    t.holdWrite!.complete(); expect(await send,isNull);
    expect(c.read(communityComposerProvider).caption,'B draft'); expect(c.read(communityFeedProvider).posts,isEmpty);
  });
  test('new draft revision is not cleared by old confirmed response',() async {
    n.setCaption('old'); t.holdWrite=Completer<void>(); final send=n.publish(); await drain();
    n.reset(); n.setCaption('new'); t.holdWrite!.complete(); expect(await send,isNull);
    expect(c.read(communityComposerProvider).caption,'new');
  });
  test('unsupported audience/media never silently publishes',() async {
    n.setCaption('text'); n.setAudience('Friends'); expect(await n.publish(),isNull);
    expect(t.posts,isEmpty); expect(c.read(communityComposerProvider).caption,'text');
    n.setAudience('public'); n.setInitialMedia(['fake.jpg']); expect(await n.publish(),isNull); expect(t.posts,isEmpty);
  });
  testWidgets('composer error retains editor/content and account change clears visible text',(tester) async {
    tester.view.physicalSize=const Size(450,850); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MaterialApp(home:PostComposePublishScreen())));
    await tester.pumpAndSettle();
    final field=find.byKey(const ValueKey('publication-text-input'));
    await tester.enterText(field,'typed publication'); await tester.pump();
    final editor=tester.state<EditableTextState>(find.byType(EditableText));
    final input=find.descendant(of:field,matching:find.byType(TextField));
    final controller=tester.widget<TextField>(input).controller!;
    t.lose=true; final pending=n.publish(); await tester.pumpAndSettle(); await pending;
    expect(identical(editor,tester.state<EditableTextState>(find.byType(EditableText))),isTrue);
    expect(controller.text,'typed publication'); expect(tester.widget<TextField>(input).readOnly,isTrue);
    resetCommunityStateInContainer(c,'B'); await tester.pumpAndSettle(); expect(controller.text,isEmpty);
  });
  testWidgets('R08 shows audience and retains pending inputs across account changes',(tester) async {
    tester.view.physicalSize=const Size(450,850); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MaterialApp(home:CommunityAskQuestionScreen())));
    await tester.pumpAndSettle(); expect(find.text('Public'),findsOneWidget); expect(t.keys,isEmpty);
    for (final field in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      final input = tester.widget<TextField>(find.descendant(of: find.byWidget(field), matching: find.byType(TextField)));
      expect(input.decoration!.filled, isFalse);
    }
    await tester.enterText(find.byKey(const ValueKey('question-title-input')),'Typed question');
    await tester.enterText(find.byKey(const ValueKey('question-details-input')),'Typed details'); await tester.pump();
    t.lose=true; await tester.tap(find.text('Đăng')); await tester.pumpAndSettle();
    expect(t.bodies.single['type'],'qa'); expect(t.bodies.single['body'],'Typed details');
    final field=find.descendant(of:find.byKey(const ValueKey('question-title-input')),matching:find.byType(TextField));
    final controller=tester.widget<TextField>(field).controller!;expect(controller.text,'Typed question');expect(tester.widget<TextField>(field).readOnly,isTrue);
    resetCommunityStateInContainer(c,'B');await tester.pumpAndSettle();expect(controller.text,isEmpty);
    final details=find.descendant(of:find.byKey(const ValueKey('question-details-input')),matching:find.byType(TextField));
    expect(tester.widget<TextField>(details).controller!.text,isEmpty);
  });
  test('question canonical QA Feed and stable same-key payload recovery',() async {
    final q=c.read(communityQuestionComposerProvider.notifier);
    q.setCaption('Question?');q.setQuestionDetails('Context');q.setTopic('Tập luyện');q.setAudience('followers_only');t.lose=true;
    expect(await q.publish(),isNull);q.setCaption('replacement');q.setQuestionDetails('replacement');q.setAudience('private');
    t.lose=false;final post=await q.publish();expect(post!.type,CommunityPostType.qa);expect(post.qaInfo!.question,'Question?');expect(post.qaInfo!.details,'Context');
    expect(t.keys.toSet().length,1);expect(t.posts.length,1);expect(t.bodies.last,{'type':'qa','title':'Question?','body':'Context','privacy':'followers_only','topic':'Tập luyện'});
    expect(c.read(communityFeedProvider).activeFilter,CommunityFeedFilter.qa);expect(c.read(communityFeedProvider).posts.single.id,post.id);
    expect(c.read(communityQuestionComposerProvider).caption,isEmpty);expect(c.read(communityComposerProvider).caption,isEmpty);
  });
  test('late question response isolated from B and separate text draft',() async {
    final q=c.read(communityQuestionComposerProvider.notifier);q.setCaption('A question');n.setCaption('A text');t.holdWrite=Completer<void>();final pending=q.publish();await drain();
    resetCommunityStateInContainer(c,'B');c.read(communityQuestionComposerProvider.notifier).setCaption('B question');t.holdWrite!.complete();expect(await pending,isNull);
    expect(c.read(communityQuestionComposerProvider).caption,'B question');expect(c.read(communityComposerProvider).caption,isEmpty);expect(c.read(communityFeedProvider).posts,isEmpty);
  });
  test('invalid question never submits and unknown key survives later rejection',() async {
    final q=c.read(communityQuestionComposerProvider.notifier);q.setCaption('x'*151);expect(await q.publish(),isNull);expect(t.keys,isEmpty);
    q.setCaption('Valid?');t.lose=true;await q.publish();final key=t.keys.single;t.lose=false;t.reject=true;await q.publish();expect(t.keys.last,key);expect(c.read(communityQuestionComposerProvider).hasPendingSubmission,isTrue);
  });
  testWidgets('attachment action opens R07 without auto-publish',(tester) async {
    tester.view.physicalSize=const Size(450,850); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container:c,child:MaterialApp(home:Scaffold(
      body:Builder(builder:(context)=>TextButton(onPressed:()=>CreateContentBottomSheet.show(context),child:const Text('Create')))))));
    await tester.tap(find.text('Create')); await tester.pumpAndSettle();
    await tester.tap(find.text('Chia s\u1ebb bu\u1ed5i t\u1eadp')); await tester.pumpAndSettle();
    expect(find.byType(CreateContentBottomSheet),findsNothing);
    expect(find.byType(CommunitySelectAttachmentScreen),findsOneWidget);
    expect(find.text('Chưa có dữ liệu hoạt động gần đây.'),findsOneWidget);
    expect(t.keys,isEmpty);
  });

}
