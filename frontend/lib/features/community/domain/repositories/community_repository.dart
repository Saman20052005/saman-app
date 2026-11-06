import '../models/community_post.dart';
import '../models/community_comment.dart';
import '../models/community_discover_item.dart';
import '../models/community_author.dart';
import '../models/draft_post.dart';
import '../models/post_attachment_snapshot.dart';
import '../models/community_notification.dart';
import '../models/question_answer.dart';

abstract class CommunityRepository {
  /// Retrieves feed posts according to the active filter (`forYou`, `following`, `qa`).
  Future<List<CommunityPost>> getFeedPosts({
    required CommunityFeedFilter filter,
  });

  /// Retrieves a single post detail with full threaded comments.
  String? get activeUserId => null;

  Future<CommunityPost> getPostDetail(String postId);

  Future<bool> deletePost(String postId);

  /// Toggles like state for a post.
  Future<bool> toggleLike(String postId);

  /// Toggles bookmark state for a post.
  Future<bool> toggleBookmark(String postId);

  /// Toggles follow state for an author.
  Future<bool> toggleFollow(String authorId);

  Future<CommunityCommentsPage> getComments(String postId, {String? cursor});

  /// Adds a new comment or reply to a post. Retry must retain requestKey.
  Future<CommunityComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
    String? replyToAuthorName,
    String? requestKey,
  });

  /// Retrieves curated data for R04 Discover screen.
  Future<CommunityDiscoverData> getDiscoverData({
    String topic = 'all',
    String? searchQuery,
  });

  // JCOM-03: Publishing & Activity Attachments
  /// Publishes a new post (from R06D or text-only) into the in-memory store.
  Future<CommunityPost> publishPost({
    required String caption,
    String? requestKey,
    List<String> mediaUrls = const [],
    PostAttachmentSnapshot? attachment,
    String audience = 'Công khai',
    String topic = '#BữaĂn',
    bool allowComments = true,
  });

  /// Publishes a new Q&A question (from R08) into the in-memory store.
  Future<CommunityPost> publishQuestion({
    required String question,
    required String categoryTag,
    String? details,
    String audience = 'Công khai',
    String? requestKey,
  });

  /// Retrieves recent finished workouts for attachment selection (R07).
  Future<PostAttachmentSnapshot> previewActivity(PostAttachmentSnapshot source, {required bool duration, required bool items, required bool sensitive});

  Future<List<PostAttachmentSnapshot>> getRecentWorkoutActivities();

  /// Retrieves recent logged meals for attachment selection (R07).
  Future<List<PostAttachmentSnapshot>> getRecentMealActivities();

  /// Retrieves saved drafts for current user.
  Future<List<DraftPost>> getDrafts();

  /// Saves or updates a draft post.
  Future<void> saveDraft(DraftPost draft);

  /// Deletes a draft post.
  Future<void> deleteDraft(String draftId);

  // JCOM-04: Profile, Notifications, Saved, Q&A
  /// Retrieves bookmarked posts (R12).
  Future<List<CommunityPost>> getSavedPosts();

  /// Retrieves notifications (R11).
  Future<List<CommunityNotification>> getNotifications();

  /// Marks a notification as read (R11).
  Future<void> markNotificationRead(String id);

  /// Retrieves author profile and their posts (R09).
  Future<CommunityAuthor> getAuthorProfile(String authorId);

  /// Retrieves followers list (R10).
  Future<List<CommunityAuthor>> getFollowers(String authorId);

  /// Retrieves following list (R10).
  Future<List<CommunityAuthor>> getFollowing(String authorId);

  /// Retrieves answers for a Q&A question (R15).
  Future<List<QuestionAnswer>> getQuestionAnswers(String questionId);

  Future<QuestionAnswersPage> getAnswerPage(String questionId, {String? cursor});
  Future<QuestionAnswer> getAnswer(String questionId, String answerId);
  Future<QuestionAnswer> setAnswerHelpful(String questionId, String answerId, bool desired);

  /// Adds an answer to a Q&A question (R15).
  Future<QuestionAnswer> addQuestionAnswer({
    required String questionId,
    required String content,
    String? requestKey,
  });

  /// Upvotes an answer (R15).
  Future<bool> upvoteAnswer(String questionId, String answerId);
}
