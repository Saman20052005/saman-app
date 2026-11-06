import 'dart:async';
import 'package:dio/dio.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_composer_provider.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/community_select_attachment_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/community_activity_snapshot_card.dart';
import 'package:health_ai_app/features/community/presentation/screens/compose/post_compose_publish_screen.dart';

class AttachmentTransport {
 final dio=Dio();final writes=<Map<String,dynamic>>[];final keys=<String>[];
 bool fail=false,lose=false,conflict=false,empty=false;Completer<void>? holdPreview;
 Map<String,dynamic> snapshot={'kind':'workout','title':'Owned workout','date':'2026-11-03','category':'Saman Kinetic','duration_minutes':40,'exercises':[{'name':'Squat'}],'exercise_count':1};
 Map<String,dynamic> preview(Map<String,dynamic> options) {
  final snap=Map<String,dynamic>.from(snapshot);
  if(options['include_duration']==false)snap.remove('duration_minutes');
  if(options['include_exercises_or_foods']==false){snap.remove('exercises');snap.remove('exercise_count');}
  if(options['include_load_or_macros']==true){snap['load_kg']=900;snap['set_count']=3;}
  return {'source_id':'source-a','preview_hash':'a'*64,'snapshot':snap};
 }
 AttachmentTransport(){dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async {
  if(fail){h.reject(DioException(requestOptions:o,type:DioExceptionType.connectionError));return;}
  if(o.method=='POST'){
   writes.add(Map<String,dynamic>.from(o.data as Map));keys.add(o.headers['X-Idempotency-Key'] as String);
   if(lose||conflict){h.reject(DioException(requestOptions:o,type:lose?DioExceptionType.receiveTimeout:DioExceptionType.badResponse,response:conflict?Response(requestOptions:o,statusCode:409):null));return;}
   h.resolve(Response(requestOptions:o,statusCode:200,data:{'id':'canonical','type':'workout','author':{'id':'a','name':'Canonical'},'caption':o.data['content'],'attachment_snapshot':preview(Map<String,dynamic>.from(o.data['attachment'] as Map))['snapshot'],'privacy':'public','topic':'#ChiaSẻ'}));return;
  }
  if(o.path.contains('attachment-sources')){
   if(o.path.endsWith('source-a')){if(holdPreview!=null)await holdPreview!.future;h.resolve(Response(requestOptions:o,statusCode:200,data:preview(o.queryParameters)));return;}
   h.resolve(Response(requestOptions:o,statusCode:200,data:{'items':empty||o.path.endsWith('meal')?[]:[preview({})]}));return;
  }
  h.resolve(Response(requestOptions:o,statusCode:200,data:{'items':[]}));
 }));}
}
void main(){
 late AttachmentTransport t;late ProviderContainer c;late CommunityRepositoryImpl repo;
 setUp((){t=AttachmentTransport();repo=CommunityRepositoryImpl(useRemote:true,remoteDatasource:CommunityRemoteDatasourceImpl(dio:t.dio));c=ProviderContainer(overrides:[communityRepositoryProvider.overrideWithValue(repo),useRemoteCommunityProvider.overrideWith((ref)=>true)]);});
 tearDown(()=>c.dispose());
 test('owned source preview selection and canonical snapshot merge',()async{
  final sources=await repo.getRecentWorkoutActivities();expect(sources.single.id,'source-a');expect(sources.single.includeLoadOrMacros,isFalse);
  final preview=await repo.previewActivity(sources.single,duration:false,items:false,sensitive:true);
  expect(preview.sharedSnapshot!.containsKey('exercises'),isFalse);expect(preview.sharedSnapshot!['set_count'],3);
  final n=c.read(communityComposerProvider.notifier);n.setCaption('kept');n.setAttachment(preview);
  final post=await n.publish();expect(post!.activitySnapshot!.title,'Owned workout');expect(post.activitySnapshot!.id,isEmpty);expect(post.activitySnapshot!.sharedSnapshot!.containsKey('exercises'),isFalse);expect(post.activitySnapshot!.sharedSnapshot!['set_count'],3);
  expect(t.writes.single['attachment'],preview.publicationSelection());expect(c.read(communityFeedProvider).posts.single.activitySnapshot!.title,'Owned workout');
 });
 test('unknown attachment payload/key frozen; removing confirmed draft attachment preserves text',()async{
  final n=c.read(communityComposerProvider.notifier);final source=(await repo.getRecentWorkoutActivities()).single;n.setCaption('draft');n.setAttachment(source);t.lose=true;await n.publish();
  n.clearAttachment();n.setAudience('private');expect(c.read(communityComposerProvider).attachedActivity,same(source));
  t.lose=false;await n.publish();expect(t.keys.toSet().length,1);expect(t.writes[0],t.writes[1]);
  n.setCaption('new text');n.setAttachment(source);n.clearAttachment();expect(c.read(communityComposerProvider).caption,'new text');
 });
 test('preview mismatch keeps draft editable without automatic resubmit',()async{
  final n=c.read(communityComposerProvider.notifier);n.setCaption('review me');n.setAttachment((await repo.getRecentWorkoutActivities()).single);t.conflict=true;await n.publish();
  expect(c.read(communityComposerProvider).caption,'review me');expect(c.read(communityComposerProvider).hasPendingSubmission,isFalse);expect(c.read(communityComposerProvider).errorMessage,'community_attachment_review');expect(t.writes.length,1);
 });
 test('late preview rejected after account reset',()async{
  final source=(await repo.getRecentWorkoutActivities()).single;t.holdPreview=Completer<void>();final pending=repo.previewActivity(source,duration:true,items:true,sensitive:true);
  resetCommunityStateInContainer(c,'B');final rejected=expectLater(pending,throwsStateError);t.holdPreview!.complete();await rejected;expect(c.read(communityComposerProvider).attachedActivity,isNull);
 });
 testWidgets('R06D removing snapshot retains caption without publishing',(tester)async{
  tester.view.physicalSize=const Size(450,850);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final n=c.read(communityComposerProvider.notifier);n.setCaption('Retained caption');n.setAttachment(PostAttachmentSnapshot.fromPreview(t.preview({})));
  await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MaterialApp(home:PostComposePublishScreen())));await tester.pumpAndSettle();
  await tester.tap(find.text('Remove attachment'));await tester.pumpAndSettle();expect(c.read(communityComposerProvider).attachedActivity,isNull);expect(c.read(communityComposerProvider).caption,'Retained caption');expect(t.writes,isEmpty);
 });
 testWidgets('R07 error retry selection and account isolation',(tester)async{
  tester.view.physicalSize=const Size(450,850);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  t.fail=true;await tester.pumpWidget(UncontrolledProviderScope(container:c,child:const MaterialApp(home:CommunitySelectAttachmentScreen())));await tester.pumpAndSettle();expect(find.text('Retry'),findsOneWidget);
  final retryText=tester.widget<RichText>(find.descendant(of:find.text('Retry'),matching:find.byType(RichText)));
  final foreground = retryText.text.style!.color!.computeLuminance();
  final background = tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!.computeLuminance();
  expect((foreground + 0.05)/(background + 0.05),greaterThanOrEqualTo(4.5),reason:'Retry must remain readable on the dark R07 surface');
  t.fail=false;await tester.tap(find.text('Retry'));await tester.pumpAndSettle();expect(find.text('Owned workout'),findsWidgets);expect(find.byType(CommunityActivitySnapshotCard),findsOneWidget);
  t.empty=true;resetCommunityStateInContainer(c,'B');await tester.pumpAndSettle();expect(find.text('Owned workout'),findsNothing);expect(find.byType(CommunityActivitySnapshotCard),findsNothing);
 });
}
