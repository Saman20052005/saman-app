import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/draft_post.dart';
import 'package:health_ai_app/features/community/domain/models/post_attachment_snapshot.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';

void main() {
  setUp(() {
    CommunityFakeDatasource.resetStorage();
  });

  group('PostAttachmentSnapshot Privacy & sanitize() Unit Tests', () {
    final rawExercises = [
      const ExerciseThumbnailPreview(title: 'Bench Press'),
      const ExerciseThumbnailPreview(title: 'Incline Dumbbell Press'),
      const ExerciseThumbnailPreview(title: 'Cable Fly'),
    ];

    test('Disabling each flag strictly strips corresponding fields from snapshot payload', () {
      final snapshot = PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_snap_01',
        title: 'Buổi tập ngực & tay sau',
        dateFormatted: 'Hôm nay, 14:30',
        includeDuration: false,
        includeExercisesOrFoods: false,
        includeLoadOrMacros: false,
        durationFormatted: '48 phút',
        exerciseCount: 3,
        setCount: 12,
        loadSummaryFormatted: '2,450 kg',
        calories: 320,
        macrosSummaryFormatted: '320 kcal • 28g P',
        exercises: rawExercises,
      );

      final clean = snapshot.sanitize();

      // Verified stripping
      expect(clean.durationFormatted, isNull);
      expect(clean.exerciseCount, isNull);
      expect(clean.setCount, isNull);
      expect(clean.loadSummaryFormatted, isNull);
      expect(clean.calories, isNull);
      expect(clean.macrosSummaryFormatted, isNull);
      expect(clean.exercises, isEmpty);

      // Public / non-sensitive identifiers remain intact
      expect(clean.id, 'workout_snap_01');
      expect(clean.title, 'Buổi tập ngực & tay sau');
      expect(clean.dateFormatted, 'Hôm nay, 14:30');
    });

    test('Enabling selective flags retains ONLY permitted fields', () {
      final snapshot = PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_snap_02',
        title: 'Buổi tập ngực',
        dateFormatted: 'Hôm qua',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false, // OFF by default
        durationFormatted: '55 phút',
        exerciseCount: 3,
        setCount: 14,
        loadSummaryFormatted: '3,100 kg (Sensitive)',
        calories: 410,
        exercises: rawExercises,
      );

      final clean = snapshot.sanitize();

      // Permitted fields retained
      expect(clean.durationFormatted, '55 phút');
      expect(clean.exerciseCount, 3);
      expect(clean.setCount, 14);
      expect(clean.exercises.length, 3);

      // Excluded load/macros strictly null
      expect(clean.loadSummaryFormatted, isNull);
      expect(clean.calories, isNull);
      expect(clean.macrosSummaryFormatted, isNull);
    });

    test('Immutability: mutating external source list does not affect sanitized snapshot', () {
      final mutableExercises = [
        const ExerciseThumbnailPreview(title: 'Deadlift'),
        const ExerciseThumbnailPreview(title: 'Barbell Row'),
      ];

      final snapshot = PostAttachmentSnapshot(
        type: AttachmentType.workout,
        id: 'workout_snap_03',
        title: 'Kéo lưng xô',
        dateFormatted: '01/11/2026',
        includeExercisesOrFoods: true,
        exercises: mutableExercises,
      ).sanitize();

      expect(snapshot.exercises.length, 2);

      // Mutate external source list
      mutableExercises.add(const ExerciseThumbnailPreview(title: 'Lat Pulldown'));
      expect(mutableExercises.length, 3);

      // Snapshot internal list remains untouched at 2 items
      expect(snapshot.exercises.length, 2);
      expect(snapshot.exercises.last.title, 'Barbell Row');

      // Modifying sanitized list directly throws UnsupportedError
      expect(
        () => snapshot.exercises.add(const ExerciseThumbnailPreview(title: 'Shrug')),
        throwsUnsupportedError,
      );
    });

    test('Idempotency: multiple sanitize() calls yield identical results', () {
      const snapshot = PostAttachmentSnapshot(
        type: AttachmentType.meal,
        id: 'meal_snap_01',
        title: 'Bữa trưa ức gà áp chảo',
        dateFormatted: '12:00',
        includeDuration: true,
        includeExercisesOrFoods: true,
        includeLoadOrMacros: false,
        durationFormatted: '20 phút nấu',
        calories: 520,
        macrosSummaryFormatted: '520 kcal • 48g P',
      );

      final firstPass = snapshot.sanitize();
      final secondPass = firstPass.sanitize();
      final thirdPass = secondPass.sanitize();

      expect(firstPass.durationFormatted, secondPass.durationFormatted);
      expect(firstPass.calories, secondPass.calories);
      expect(firstPass.loadSummaryFormatted, secondPass.loadSummaryFormatted);
      expect(secondPass.durationFormatted, thirdPass.durationFormatted);
      expect(secondPass.calories, isNull);
      expect(thirdPass.calories, isNull);
    });

    test('Draft and publish lifecycle: stripped fields never reappear in preview store', () async {
      final ds = CommunityFakeDatasource(currentUserId: 'test_user_privacy');
      final repo = CommunityRepositoryImpl(datasource: ds);

      final privateSnapshot = const PostAttachmentSnapshot(
        type: AttachmentType.meal,
        id: 'meal_sensitive_01',
        title: 'Bữa phụ nhẹ',
        dateFormatted: '16:00',
        includeLoadOrMacros: false, // Sensitive calories disabled
        calories: 250,
        macrosSummaryFormatted: '250 kcal • 20g P',
      ).sanitize();

      // 1. Save into draft
      final draft = DraftPost(
        id: 'draft_privacy_01',
        userId: 'test_user_privacy',
        caption: 'Bữa phụ chiều giàu đạm',
        attachment: privateSnapshot,
        updatedAt: DateTime.now(),
      );
      await repo.saveDraft(draft);

      // Retrieve draft from store
      final loadedDrafts = await repo.getDrafts();
      final loadedDraft = loadedDrafts.firstWhere((d) => d.id == 'draft_privacy_01');
      expect(loadedDraft.attachment!.calories, isNull);
      expect(loadedDraft.attachment!.macrosSummaryFormatted, isNull);

      // 2. Publish post using that attachment
      final published = await repo.publishPost(
        caption: loadedDraft.caption,
        attachment: loadedDraft.attachment,
      );

      // Check stored object in repository/feed
      final feedPost = await repo.getPostDetail(published.id);
      expect(feedPost.nutritionInfo?.calories, 0); // Excluded calories default to 0 / safe display
      expect(feedPost.nutritionInfo?.badgeLabel, 'Bữa ăn cân bằng (Mẫu)');
    });
  });

  group('Account Isolation via DI and Fake Datasource Tests', () {
    test('Identity A drafts and bookmarks are strictly isolated from Identity B', () async {
      final dsUserA = CommunityFakeDatasource(currentUserId: 'user_alice');
      final dsUserB = CommunityFakeDatasource(currentUserId: 'user_bob');

      final repoA = CommunityRepositoryImpl(datasource: dsUserA);
      final repoB = CommunityRepositoryImpl(datasource: dsUserB);

      // 1. User Alice saves a draft
      final draftAlice = DraftPost(
        id: 'draft_alice_01',
        caption: 'Bí quyết squat chuẩn form của Alice',
        topic: '#TậpLuyện',
        updatedAt: DateTime.now(),
      );
      await repoA.saveDraft(draftAlice);

      // 2. User Alice bookmarks post_01_meal
      await repoA.toggleBookmark('post_01_meal');

      // Assert Alice has 1 draft and 1 saved post
      final draftsA = await repoA.getDrafts();
      expect(draftsA.length, 1);
      expect(draftsA.first.id, 'draft_alice_01');

      final savedA = await repoA.getSavedPosts();
      expect(savedA.any((p) => p.id == 'post_01_meal'), isTrue);

      // 3. User Bob accesses repo
      final draftsB = await repoB.getDrafts();
      expect(draftsB, isEmpty, reason: 'Bob must not see Alice drafts');

      final savedB = await repoB.getSavedPosts();
      expect(savedB, isEmpty, reason: 'Bob must not inherit Alice bookmarks');

      // 4. Bob attempts to delete Alice draft
      await repoB.deleteDraft('draft_alice_01');

      // Switch back to Alice: Alice draft remains completely intact!
      final draftsAAfterBobAttempt = await repoA.getDrafts();
      expect(draftsAAfterBobAttempt.length, 1);
      expect(draftsAAfterBobAttempt.first.id, 'draft_alice_01');
      expect(draftsAAfterBobAttempt.first.caption, 'Bí quyết squat chuẩn form của Alice');

      // Alice bookmarks remain intact
      final savedAAfter = await repoA.getSavedPosts();
      expect(savedAAfter.any((p) => p.id == 'post_01_meal'), isTrue);
    });

    test('Riverpod DI container override maintains account isolation when switching identities', () async {
      // Container 1: User Alpha
      final containerAlpha = ProviderContainer(
        overrides: [
          communityFakeDatasourceProvider.overrideWithValue(
            CommunityFakeDatasource(currentUserId: 'user_alpha'),
          ),
        ],
      );
      addTearDown(containerAlpha.dispose);

      final repoAlpha = containerAlpha.read(communityRepositoryProvider);
      await repoAlpha.saveDraft(
        DraftPost(
          id: 'draft_alpha_1',
          caption: 'Bản nháp của Alpha',
          updatedAt: DateTime.now(),
        ),
      );

      expect((await repoAlpha.getDrafts()).length, 1);

      // Container 2: User Beta
      final containerBeta = ProviderContainer(
        overrides: [
          communityFakeDatasourceProvider.overrideWithValue(
            CommunityFakeDatasource(currentUserId: 'user_beta'),
          ),
        ],
      );
      addTearDown(containerBeta.dispose);

      final repoBeta = containerBeta.read(communityRepositoryProvider);
      expect((await repoBeta.getDrafts()), isEmpty);

      // Beta creates their own draft
      await repoBeta.saveDraft(
        DraftPost(
          id: 'draft_beta_1',
          caption: 'Bản nháp riêng của Beta',
          updatedAt: DateTime.now(),
        ),
      );

      expect((await repoBeta.getDrafts()).length, 1);
      expect((await repoBeta.getDrafts()).first.id, 'draft_beta_1');

      // Alpha still only has Alpha's draft
      final alphaDraftsAgain = await repoAlpha.getDrafts();
      expect(alphaDraftsAgain.length, 1);
      expect(alphaDraftsAgain.first.id, 'draft_alpha_1');
    });
  });
}
