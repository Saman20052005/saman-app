import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/qa/community_question_detail_screen.dart';

// Transport simulation only; standalone Mongo tests provide real persistence evidence.
class AnswerTransport {
  final Dio dio = Dio();
  final Map<String, Map<String,dynamic>> stored = {};
  final List<String> keys = [];
  bool loseAnswer = false, loseVote = false, failRead = false, denied = false, staleFeed = false;
  Completer<void>? holdAnswer, holdVote;
  Map<String,dynamic> get post => {'id':'q','type':'qa','author':{'id':'owner','name':'Owner'},
    'caption':'Question','qa_info':{'question':'Question?','category_tag':'Q&A',
    'respondent_count':staleFeed ? 0 : stored.length,'respondents_summary':''}};
  AnswerTransport() {
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async {
      void fail(DioExceptionType type, [int? status]) => h.reject(DioException(requestOptions:o,
          type:type, response:status == null ? null : Response(requestOptions:o,statusCode:status)));
      if (denied) { fail(DioExceptionType.badResponse,404); return; }
      Object data;
      if (o.method == 'POST') {
        final key=o.headers['X-Idempotency-Key'] as String; keys.add(key);
        final a=stored.putIfAbsent(key,()=>{'id':'a${stored.length}','question_id':'q',
          'author':{'id':'a','name':'Canonical A'},'content':(o.data as Map)['content'],
          'time_ago':'Now','upvote_count':0,'is_upvoted':false,'is_pinned_best':false});
        if (holdAnswer != null) await holdAnswer!.future;
        if (loseAnswer) { fail(DioExceptionType.receiveTimeout); return; }
        data={'answer':a,'answer_count':stored.length};
      } else if (o.path.endsWith('/helpful')) {
        final id=o.path.split('/')[6]; final a=stored.values.firstWhere((a)=>a['id']==id);
        a['is_upvoted']=o.method=='PUT'; a['upvote_count']=o.method=='PUT' ? 1 : 0;
        if (holdVote != null) await holdVote!.future;
        if (loseVote) { fail(DioExceptionType.receiveTimeout); return; }
        data=Map<String,dynamic>.from(a);
      } else if (o.path.endsWith('/answers')) {
        if (failRead) { fail(DioExceptionType.connectionError); return; }
        final offset=o.queryParameters['cursor']==null ? 0 : 1;
        final items=stored.values.skip(offset).take(1).map((a)=>Map<String,dynamic>.from(a)).toList();
        data={'items':items,'answer_count':stored.length,'next_cursor':offset+items.length<stored.length ? 'next' : null};
      } else if (o.path.contains('/answers/')) {
        if (failRead) { fail(DioExceptionType.connectionError); return; }
        data=Map<String,dynamic>.from(stored.values.firstWhere((a)=>a['id']==o.path.split('/').last));
      } else if (o.path.endsWith('/feed')) { data={'items':[post]}; }
      else { data=post; }
      h.resolve(Response(requestOptions:o,statusCode:200,data:data));
    }));
  }
}
Future<void> drain() async { for(var i=0;i<20;i++) { await Future<void>.delayed(Duration.zero); } }
void main() {
  late AnswerTransport t;
  late CommunityRepositoryImpl repo;
  late ProviderContainer c;
  late CommunityQuestionDetailNotifier n;
  setUp(() async {
    t=AnswerTransport(); repo=CommunityRepositoryImpl(useRemote:true,remoteDatasource:CommunityRemoteDatasourceImpl(dio:t.dio));
    repo.resetForUser('viewer');
    c=ProviderContainer(overrides:[communityRepositoryProvider.overrideWithValue(repo)]);
    n=c.read(communityQuestionDetailProvider('q').notifier); await drain();
  });
  tearDown(()=>c.dispose());
  test('canonical answer, count synchronization and stale feed guard',() async {
    await c.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.qa);
    expect(await n.submitAnswer('  answer  '),isTrue);
    expect(c.read(communityQuestionDetailProvider('q')).answerCount,1);
    expect(c.read(communityFeedProvider).posts.single.qaInfo!.respondentCount,1);
    t.staleFeed=true; await c.read(communityFeedProvider.notifier).loadPosts(CommunityFeedFilter.qa);
    expect(c.read(communityFeedProvider).posts.single.qaInfo!.respondentCount,1);
    expect(c.read(communityQuestionDetailProvider('q')).draft,isEmpty);
  });
  test('persisted timeout retains key and canonical retry never duplicates',() async {
    t.loseAnswer=true;
    expect(await n.submitAnswer('answer'),isFalse);
    expect(c.read(communityQuestionDetailProvider('q')).hasPendingAnswer,isTrue);
    n.updateDraft('different');
    expect(c.read(communityQuestionDetailProvider('q')).draft,'answer');
    t.loseAnswer=false; expect(await n.submitAnswer('different'),isTrue);
    expect(t.keys.length,2); expect(t.keys.toSet().length,1);
    expect(t.stored.length,1); expect(c.read(communityQuestionDetailProvider('q')).answers.single.content,'answer');
  });
  test('helpful timeout reconciles authoritative state then unvotes',() async {
    await n.submitAnswer('answer'); t.loseVote=true;
    await n.toggleUpvote('a0');
    expect(c.read(communityQuestionDetailProvider('q')).answers.single.isUpvoted,isTrue);
    expect(c.read(communityQuestionDetailProvider('q')).answers.single.upvoteCount,1);
    t.loseVote=false; await n.toggleUpvote('a0');
    expect(c.read(communityQuestionDetailProvider('q')).answers.single.upvoteCount,0);
    expect(c.read(communityQuestionDetailProvider('q')).answers.single.isPinnedBest,isFalse);
  });
  test('pagination merges IDs and revoked replay hides answers and Feed',() async {
    await n.submitAnswer('first'); await n.submitAnswer('second');
    await n.refresh(); expect(c.read(communityQuestionDetailProvider('q')).cursor,'next');
    await n.loadAnswers(more:true); expect(c.read(communityQuestionDetailProvider('q')).answers.length,2);
    t.loseAnswer=true; await n.submitAnswer('unknown'); t.denied=true;
    await n.submitAnswer('unknown');
    final s=c.read(communityQuestionDetailProvider('q'));
    expect(s.accessible,isFalse); expect(s.answers,isEmpty); expect(s.answerCount,0); expect(s.draft,'unknown');
    expect(c.read(communityFeedProvider).posts,isEmpty);
  });
  test('late answer response from A cannot update B or repository counts',() async {
    t.holdAnswer=Completer<void>(); final pending=n.submitAnswer('A only'); await drain();
    resetCommunityStateInContainer(c,'B');
    final b=c.read(communityQuestionDetailProvider('q').notifier); await drain();
    final beforeB=c.read(communityQuestionDetailProvider('q'));
    final countBefore=repo.answerCountFor('q');
    t.holdAnswer!.complete(); await pending;
    expect(identical(c.read(communityQuestionDetailProvider('q')),beforeB),isTrue);
    expect(repo.answerCountFor('q'),countBefore);
    expect(c.read(communityQuestionDetailProvider('q')).draft,isEmpty);
    expect(c.read(communityQuestionDetailProvider('q')).hasPendingAnswer,isFalse);
    expect(repo.activeUserId,'B'); expect(identical(n,b),isFalse);
  });
  test('late vote response does not update B and self vote is disabled',() async {
    await n.submitAnswer('answer'); t.holdVote=Completer<void>(); final pending=n.toggleUpvote('a0'); await drain();
    resetCommunityStateInContainer(c,'a');
    final b=c.read(communityQuestionDetailProvider('q').notifier); await drain();
    final before=c.read(communityQuestionDetailProvider('q')).answers.single;
    expect(b.canVote(before),isFalse);
    t.holdVote!.complete(); await pending;
    expect(c.read(communityQuestionDetailProvider('q')).answers.single.upvoteCount,before.upvoteCount);
  });
  testWidgets('pending and error rows preserve editor and account switch clears visible draft',(tester) async {
    tester.view.physicalSize=const Size(450,850); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MaterialApp(home:CommunityQuestionDetailScreen(questionId:'q'))));
    await tester.pumpAndSettle();
    final field=find.byKey(const ValueKey('community-answer-input'));
    await tester.enterText(field,'kept after timeout'); await tester.pump();
    final editor=tester.state<EditableTextState>(find.byType(EditableText));
    final controller=tester.widget<TextField>(field).controller;
    t.loseAnswer=true; await tester.tap(find.byIcon(Icons.send_rounded)); await tester.pumpAndSettle();
    expect(identical(tester.state<EditableTextState>(find.byType(EditableText)),editor),isTrue);
    expect(identical(tester.widget<TextField>(field).controller,controller),isTrue);
    expect(controller!.text,'kept after timeout'); expect(tester.widget<TextField>(field).readOnly,isTrue);
    t.loseAnswer=false; final retry=n.submitAnswer('kept after timeout');
    await tester.pumpAndSettle(); expect(await retry,isTrue);
    expect(identical(tester.state<EditableTextState>(find.byType(EditableText)),editor),isTrue);
    expect(controller.text,isEmpty);
    await tester.tap(field); await tester.pump();
    expect(tester.testTextInput.hasAnyClients,isTrue);
    await n.submitAnswer(''); await tester.pump();
    expect(identical(tester.state<EditableTextState>(find.byType(EditableText)),editor),isTrue);
    expect(tester.testTextInput.hasAnyClients,isTrue);
    tester.testTextInput.enterText('new connection retained'); await tester.pump();
    expect(controller.text,'new connection retained');
    resetCommunityStateInContainer(c,'B'); await tester.pumpAndSettle();
    expect(controller.text,isEmpty);
  });
}
