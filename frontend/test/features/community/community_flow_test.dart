import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_discover_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_post_detail_screen.dart';

void main() {
  group('Community Repository & State Machine Unit Tests', () {
    late CommunityFakeDatasource datasource;
    late CommunityRepositoryImpl repository;

    setUp(() {
      datasource = CommunityFakeDatasource();
      repository = CommunityRepositoryImpl(datasource: datasource);
    });

    test('getFeedPosts returns 3 default posts for forYou', () async {
      final posts =
          await repository.getFeedPosts(filter: CommunityFeedFilter.forYou);
      expect(posts.length, 3);
      expect(posts[0].type, CommunityPostType.photo);
      expect(posts[1].type, CommunityPostType.workout);
      expect(posts[2].type, CommunityPostType.qa);
    });

    test('getFeedPosts filters correctly for qa tab', () async {
      final posts =
          await repository.getFeedPosts(filter: CommunityFeedFilter.qa);
      expect(posts.length, 1);
      expect(posts[0].id, 'post_03_qa');
    });

    test('toggleLike updates like status and counter correctly', () async {
      final initialPost = await repository.getPostDetail('post_01_meal');
      final initialLiked = initialPost.isLiked;
      final initialCount = initialPost.likeCount;

      final result = await repository.toggleLike('post_01_meal');
      expect(result, !initialLiked);

      final updatedPost = await repository.getPostDetail('post_01_meal');
      expect(updatedPost.isLiked, !initialLiked);
      expect(
        updatedPost.likeCount,
        result ? initialCount + 1 : initialCount - 1,
      );
    });

    test('toggleBookmark updates bookmark status', () async {
      final initialPost = await repository.getPostDetail('post_01_meal');
      expect(initialPost.isBookmarked, isFalse);

      final result = await repository.toggleBookmark('post_01_meal');
      expect(result, isTrue);

      final updatedPost = await repository.getPostDetail('post_01_meal');
      expect(updatedPost.isBookmarked, isTrue);
    });

    test('toggleFollow updates author follow state', () async {
      final result = await repository.toggleFollow('creator_long');
      expect(result, isTrue);

      final data = await repository.getDiscoverData();
      final creator =
          data.recommendedCreators.firstWhere((c) => c.id == 'creator_long');
      expect(creator.isFollowing, isTrue);
    });

    test('addComment appends new comment and increments counter', () async {
      final postBefore = await repository.getPostDetail('post_01_meal');
      final beforeCount = postBefore.commentCount;

      final newComment = await repository.addComment(
        postId: 'post_01_meal',
        content: 'Tuyệt vời quá Linh ơi!',
      );

      expect(newComment.content, 'Tuyệt vời quá Linh ơi!');
      expect(newComment.author.name, 'Bạn');

      final postAfter = await repository.getPostDetail('post_01_meal');
      expect(postAfter.commentCount, beforeCount + 1);
      expect(postAfter.comments.first.content, 'Tuyệt vời quá Linh ơi!');
    });

    test('addComment with parentCommentId creates nested reply', () async {
      final newReply = await repository.addComment(
        postId: 'post_01_meal',
        content: 'Cảm ơn Khang đã hỏi nhé!',
        parentCommentId: 'c1',
        replyToAuthorName: 'Minh Khang',
      );

      expect(newReply.replyToAuthorName, 'Minh Khang');
      final postAfter = await repository.getPostDetail('post_01_meal');
      final parentComment =
          postAfter.comments.firstWhere((c) => c.id == 'c1');
      expect(
        parentComment.replies.any((r) => r.content == 'Cảm ơn Khang đã hỏi nhé!'),
        isTrue,
      );
    });

    test('getDiscoverData returns 9 grid items and trending topics', () async {
      final data = await repository.getDiscoverData(topic: 'workout');
      expect(data.activeTopic, 'workout');
      expect(data.gridItems.length, 9);
      expect(data.trendingTopics.length, 3);
      expect(data.recommendedCreators.length, 2);
    });
  });

  group('Community Riverpod Providers Flow Tests', () {
    testWidgets('CommunityFeedNotifier manages filter and likes',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final feedNotifier = container.read(communityFeedProvider.notifier);

      // Wait initial load
      await container.read(communityFeedProvider.notifier).loadPosts(
            CommunityFeedFilter.forYou,
          );
      var state = container.read(communityFeedProvider);
      expect(state.posts.length, 3);

      // Switch to qa
      await feedNotifier.setFilter(CommunityFeedFilter.qa);
      state = container.read(communityFeedProvider);
      expect(state.activeFilter, CommunityFeedFilter.qa);
      expect(state.posts.length, 1);

      // Switch back and like
      await feedNotifier.setFilter(CommunityFeedFilter.forYou);
      await feedNotifier.toggleLike('post_02_workout');
      state = container.read(communityFeedProvider);
      final workoutPost =
          state.posts.firstWhere((p) => p.id == 'post_02_workout');
      expect(workoutPost.isLiked, isTrue);
      expect(workoutPost.likeCount, 90);
    });

    testWidgets('CommunityPostDetailNotifier submits comment', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final detailNotifier =
          container.read(communityPostDetailProvider('post_01_meal').notifier);
      await detailNotifier.loadPost();

      var state = container.read(communityPostDetailProvider('post_01_meal'));
      final initialCount = state.post!.commentCount;

      final success = await detailNotifier.submitComment('Bài viết rất hữu ích!');
      expect(success, isTrue);

      state = container.read(communityPostDetailProvider('post_01_meal'));
      expect(state.post!.commentCount, initialCount + 1);
      expect(
        state.post!.comments.any((c) => c.content == 'Bài viết rất hữu ích!'),
        isTrue,
      );
    });
  });

  group('Community Screen Widget Tests', () {
    Widget buildTestApp(Widget child) {
      return ProviderScope(
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('CommunityFeedScreen renders headers, tabs, and posts',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp(const CommunityFeedScreen()));
      await tester.pumpAndSettle();

      // Top bar
      expect(find.text('Saman Community'), findsOneWidget);

      // 3 Filter Tabs
      expect(find.text('Dành cho bạn'), findsOneWidget);
      expect(find.text('Đang theo dõi'), findsOneWidget);
      expect(find.text('Hỏi đáp'), findsOneWidget);

      // Post 1: Meal post
      expect(find.text('Linh Nguyễn'), findsWidgets);
      expect(find.textContaining('ức gà áp chảo sốt tiêu'), findsOneWidget);
      expect(find.text('510 kcal • 48g Protein'), findsOneWidget);

      // Post 2: Workout post
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Upper Body Hypertrophy'), findsOneWidget);
      expect(find.text('BUỔI TẬP ĐÃ HOÀN THÀNH'), findsOneWidget);

      // Bring QA tab into view and tap
      await tester.ensureVisible(find.text('Hỏi đáp'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hỏi đáp'));
      await tester.pumpAndSettle();

      // In QA tab, meal post should not be visible
      expect(find.textContaining('ức gà áp chảo sốt tiêu'), findsNothing);
      expect(
        find.text('Bạn thường chuẩn bị bữa ăn cho cả tuần như thế nào?'),
        findsOneWidget,
      );
    });

    testWidgets('CommunityDiscoverScreen renders 3x3 grid, trends, and creators',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp(const CommunityDiscoverScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Khám phá cộng đồng'), findsOneWidget);
      expect(find.text('Không gian truyền cảm hứng'), findsOneWidget);
      expect(find.text('Khoảnh khắc tiêu biểu'), findsOneWidget);
      expect(find.text('Chủ đề đang được quan tâm'), findsOneWidget);
      expect(find.text('#MealPrepCuoiTuan'), findsOneWidget);
      expect(find.text('#TangCoGiamMo'), findsOneWidget);
      expect(find.text('Có thể bạn muốn theo dõi'), findsOneWidget);
      expect(find.text('Hoàng Long'), findsOneWidget);
      expect(find.text('Thảo Mai'), findsOneWidget);

      // Scroll down to make follow button visible
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // Tap follow on Hoàng Long
      final followButtons = find.widgetWithText(ElevatedButton, 'Theo dõi');
      expect(followButtons, findsWidgets);

      await tester.tap(followButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Đang theo dõi'), findsOneWidget);
    });

    testWidgets('CommunityPostDetailScreen renders details, tips, and comments',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp(
        const CommunityPostDetailScreen(postId: 'post_01_meal'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chi tiết bài viết'), findsOneWidget);
      expect(find.text('Thành viên Saman'), findsWidgets);
      expect(find.textContaining('Mẹo nhỏ: Ướp gà trước'), findsOneWidget);
      expect(find.text('48g Protein'), findsOneWidget);
      expect(find.text('510 kcal'), findsOneWidget);
      expect(find.text('Clean Eating'), findsOneWidget);
      expect(find.text('Bình luận & Thảo luận'), findsOneWidget);

      // Author reply
      expect(find.text('Tác giả'), findsOneWidget);
      expect(find.textContaining('Mình set 180 độ trong 15 phút'), findsOneWidget);

      // Enter comment and submit
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      await tester.enterText(inputFinder, 'Bữa ăn trông rất ngon miệng!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Bữa ăn trông rất ngon miệng!'), findsOneWidget);
    });
  });
}
