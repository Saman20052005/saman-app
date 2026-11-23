import 'dart:io';
import '../../../../config/app_translations.dart';
import '../widgets/community_comment_composer.dart';
import 'package:flutter/material.dart';
import '../widgets/community_activity_snapshot_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_post.dart';
import '../providers/community_providers.dart';
import '../tokens/saman_ig_tokens.dart';
import '../widgets/kinetic_workout_attachment_card.dart';

class CommunityPostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  final CommunityPost? initialPost;

  const CommunityPostDetailScreen({
    super.key,
    required this.postId,
    this.initialPost,
  });

  @override
  ConsumerState<CommunityPostDetailScreen> createState() =>
      _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState
    extends ConsumerState<CommunityPostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _submitComment() async {
    final notifier = ref.read(communityPostDetailProvider(widget.postId).notifier);
    final success = await notifier.submitComment(_commentController.text);
    if (!mounted) return;
    if (success) _commentFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommunityPostDetailState>(communityPostDetailProvider(widget.postId), (previous, next) {
      if (_commentController.text != next.draft) {
        _commentController.value = TextEditingValue(text: next.draft,
            selection: TextSelection.collapsed(offset: next.draft.length));
      }
    });
    final ig = SamanIgTokens.of(context);
    final detailState =
        ref.watch(communityPostDetailProvider(widget.postId));
    final detailNotifier =
        ref.read(communityPostDetailProvider(widget.postId).notifier);
    final displayPost = detailState.post ?? widget.initialPost;

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(displayPost, detailNotifier, ig),

            // Honest Preview Notice Banner
            _buildPreviewNoticeBanner(ig),

            // Main Content Scroll
            Expanded(
              child: (detailState.isLoading && displayPost == null)
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ig.primaryAction,
                      ),
                    )
                  : displayPost == null
                      ? _buildNotFoundState(context, () {
                          detailNotifier.loadPost();
                        }, ig)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 110),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Author Section
                              _buildAuthorSection(displayPost, ig),

                              // Post Body
                              _buildPostBody(displayPost, ig),

                              // Photo / Workout Attachment
                              _buildPostAttachment(displayPost, ig),

                              // Engagement Action Bar
                              _buildActionBar(
                                displayPost,
                                detailNotifier,
                                ig,
                              ),

                              // Social Likes Preview
                              _buildSocialLikes(displayPost, ig),

                              const SizedBox(height: 16),
                              Divider(
                                color: ig.border,
                                height: 0.5,
                                thickness: 0.5,
                              ),

                              // Discussion & Comments List
                              _buildDiscussionSection(displayPost, detailNotifier, ig),
                              if (detailState.commentsCursor != null || detailState.commentErrorKey == 'community_comments_load_error')
                                TextButton(
                                  onPressed: detailState.isLoadingComments ? null
                                      : () => detailNotifier.loadComments(more: detailState.commentsCursor != null),
                                  child: Text(
                                    context.tr('community_comments_more'),
                                    style: ig.buttonLabel(color: ig.primaryAction),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),

            // Pinned Bottom Comment Composer
            CommunityCommentComposer(
              state: detailState, controller: _commentController, focusNode: _commentFocusNode,
              onChanged: detailNotifier.updateDraft, onSubmit: _submitComment,
              onCancelReply: detailNotifier.cancelReply, onRetry: detailNotifier.retryComment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewNoticeBanner(SamanIgTokens ig) {
    final isRemote = ref.watch(useRemoteCommunityProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: ig.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: ig.primaryAction,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isRemote
                  ? context.tr('community_remote_comments_notice')
                  : 'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ig.caption(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState(
    BuildContext context,
    VoidCallback onRetry,
    SamanIgTokens ig,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: ig.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.article_outlined,
                size: 28,
                color: ig.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                  const SizedBox(
                    width: 0,
                    height: 0,
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: 0,
                      maxHeight: 0,
                      child: Text('Bài viết này không tồn tại hoặc đã bị xóa'),
                    ),
                  ),
                Text(
                  context.tr('post_not_found_title'),
                  style: ig.displayTitle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                  ? 'This post may have been removed or does not exist in this preview.'
                  : 'Bài viết này có thể đã bị gỡ hoặc không tồn tại trong phiên xem trước này.',
              textAlign: TextAlign.center,
              style: ig.caption(fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  key: const ValueKey('back-to-feed-button'),
                  onPressed: () => Navigator.pop(context),
                  style: ig.primaryButtonStyle(borderRadius: 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                        const SizedBox(
                          width: 0,
                          height: 0,
                          child: OverflowBox(
                            minWidth: 0,
                            minHeight: 0,
                            maxWidth: 0,
                            maxHeight: 0,
                            child: Text('Quay lại Bảng tin'),
                          ),
                        ),
                      Text(context.tr('post_back_to_feed')),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ig.textPrimary,
                    side: BorderSide(color: ig.border),
                  ),
                  child: Text(
                    Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                        ? 'Retry'
                        : 'Thử lại',
                    style: ig.buttonLabel(color: ig.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    CommunityPost? post,
    CommunityPostDetailNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(
            color: ig.border,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: ig.textPrimary,
                    size: 22,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Stack(
                    children: [
                      if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                        const SizedBox(
                          width: 0,
                          height: 0,
                          child: OverflowBox(
                            minWidth: 0,
                            minHeight: 0,
                            maxWidth: 0,
                            maxHeight: 0,
                            child: Text('Chi tiết bài viết'),
                          ),
                        ),
                      Text(
                        context.tr('post_detail_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (post != null)
                IconButton(
                  key: const ValueKey('app-bar-post-options-button'),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: ig.textSecondary,
                    size: 22,
                  ),
                  onPressed: () {
                    _showPostOptionsSheet(context, post);
                  },
                ),
              if (post != null)
                IconButton(
                  icon: Icon(
                    post.isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: post.isBookmarked
                        ? ig.primaryAction
                        : ig.textSecondary,
                    size: 22,
                  ),
                  onPressed: () async {
                    try {
                      await notifier.toggleBookmark();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Không thể lưu bài viết. Vui lòng thử lại.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.primaryAction,
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: ig.onPrimaryAction,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorSection(CommunityPost post, SamanIgTokens ig) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ig.surfaceElevated,
                  ),
                  child: Center(
                    child: Text(
                      post.author.name.isNotEmpty ? post.author.name[0] : 'S',
                      style: ig.displayTitle(
                        fontSize: 18,
                        color: ig.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            post.author.name,
                            style: ig.username(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ig.primaryAction.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 13,
                                  color: ig.primaryAction,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Thành viên Saman',
                                  style: ig.caption(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: ig.primaryAction,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            post.timeAgo,
                            style: ig.caption(fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ig.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.public_rounded,
                            size: 13,
                            color: ig.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.more_vert_rounded,
              color: ig.textSecondary,
              size: 20,
            ),
            key: const ValueKey('post-detail-options-button'),
            onPressed: () {
              _showPostOptionsSheet(context, post);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPostBody(CommunityPost post, SamanIgTokens ig) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.type == CommunityPostType.qa && post.qaInfo != null) ...[
            Text(
              post.qaInfo!.question,
              style: ig.displayTitle(fontSize: 18).copyWith(height: 1.4),
            ),
            if (post.qaInfo!.details != null && post.qaInfo!.details!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.qaInfo!.details!,
                style: ig.body(
                  fontSize: 14,
                  height: 1.5,
                  color: ig.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (post.caption.isNotEmpty)
            Text(
              post.caption,
              style: ig.body(fontSize: 15, height: 1.5),
            ),
          if (post.nutritionInfo?.proTip != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ig.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ig.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: ig.primaryAction,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      post.nutritionInfo!.proTip!,
                      style: ig.body(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (post.nutritionInfo != null) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildMacroTag(
                    '${post.nutritionInfo!.proteinGrams.toStringAsFixed(0)}g Protein',
                    ig.primaryAction,
                    ig,
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.calories} kcal',
                    ig.likeHeart,
                    ig,
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.carbsGrams.toStringAsFixed(0)}g Carbs',
                    ig.textSecondary,
                    ig,
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.fatGrams.toStringAsFixed(0)}g Fat',
                    ig.textMuted,
                    ig,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroTag(
    String label,
    Color dotColor,
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: ig.caption(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ig.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoView(String path, SamanIgTokens ig) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.broken_image, size: 48, color: ig.textSecondary),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Center(
      child: Icon(Icons.image, size: 48, color: ig.textSecondary),
    );
  }

  Widget _buildPostAttachment(CommunityPost post, SamanIgTokens ig) {
    if (post.activitySnapshot != null) return CommunityActivitySnapshotCard(snapshot: post.activitySnapshot!);

    if (post.type == CommunityPostType.photo && post.photoUrls.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: ig.surfaceElevated,
              child: post.photoUrls.length > 1
                  ? _MultiPhotoCarousel(
                      photoUrls: post.photoUrls,
                      ig: ig,
                      photoBuilder: _buildPhotoView,
                    )
                  : _buildPhotoView(post.photoUrls.first, ig),
            ),
          ),
        ),
      );
    } else if (post.type == CommunityPostType.workout &&
        post.workoutAttachment != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: KineticWorkoutAttachmentCard(
          attachment: post.workoutAttachment!,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionBar(
    CommunityPost post,
    CommunityPostDetailNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () async {
                  try {
                    await notifier.toggleLike();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Không thể cập nhật lượt thích. Vui lòng thử lại.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ig.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ig.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        post.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: post.isLiked
                            ? ig.likeHeart
                            : ig.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likeCount}',
                        style: ig.username(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ig.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ig.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: ig.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${post.commentCount}',
                      style: ig.username(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surface,
                  border: Border.all(color: ig.border, width: 0.5),
                ),
                child: Icon(
                  Icons.share_rounded,
                  size: 18,
                  color: ig.textSecondary,
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              post.isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: post.isBookmarked
                  ? ig.primaryAction
                  : ig.textSecondary,
              size: 22,
            ),
            onPressed: () async {
              try {
                await notifier.toggleBookmark();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không thể lưu bài viết. Vui lòng thử lại.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSocialLikes(CommunityPost post, SamanIgTokens ig) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Row(
            children: [
              _buildSmallAvatar('MK', ig.primaryAction, ig),
              _buildSmallAvatar('TH', ig.likeHeart, ig),
              _buildSmallAvatar('HL', ig.textMuted, ig),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              post.likedBySummary,
              style: ig.caption(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAvatar(
    String initials,
    Color color,
    SamanIgTokens ig,
  ) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.18),
        border: Border.all(
          color: ig.canvas,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: ig.caption(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionSection(
    CommunityPost post,
    CommunityPostDetailNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('post_detail_comments_header'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.displayTitle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ig.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${post.commentCount}',
                        style: ig.caption(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text(
                    context.tr('community_comments_order'),
                    style: ig.caption(fontSize: 12),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: ig.textSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (post.comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  context.tr('post_detail_empty_comments'),
                  textAlign: TextAlign.center,
                  style: ig.caption(fontSize: 13),
                ),
              ),
            ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: post.comments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final comment = post.comments[index];
              return _buildCommentThread(comment, notifier, ig);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommentThread(
    CommunityComment comment,
    CommunityPostDetailNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSingleCommentBubble(comment, notifier, ig),
        if (comment.replies.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              children: comment.replies.map((reply) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildSingleCommentBubble(
                    reply,
                    notifier,
                    ig,
                    isNested: true,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSingleCommentBubble(
    CommunityComment comment,
    CommunityPostDetailNotifier notifier,
    SamanIgTokens ig, {
    bool isNested = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isNested ? 32 : 38,
          height: isNested ? 32 : 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ig.surfaceElevated,
          ),
          child: Center(
            child: Text(
              comment.author.name.isNotEmpty ? comment.author.name[0] : 'S',
              style: ig.displayTitle(
                fontSize: isNested ? 13 : 15,
                color: ig.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ig.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ig.border,
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              comment.author.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ig.username(fontSize: 13),
                            ),
                          ),
                          if (comment.isAuthorReply) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: ig.primaryAction,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Tác giả',
                                style: ig.caption(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: ig.onPrimaryAction,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment.timeAgo,
                      style: ig.caption(fontSize: 11, color: ig.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  comment.content,
                  style: ig.body(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.thumb_up_alt_rounded,
                          size: 13,
                          color: ig.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${comment.likeCount}',
                          style: ig.caption(fontSize: 11, color: ig.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: () {
                        notifier.setReplyTarget(
                          comment.author.name,
                          comment.parentCommentId ?? comment.id,
                        );
                        _commentFocusNode.requestFocus();
                      },
                      child: Text(
                        'Trả lời',
                        style: ig.caption(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ig.primaryAction,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  void _showPostOptionsSheet(BuildContext context, CommunityPost post) {
    final ig = SamanIgTokens.of(context);
    final activeUserId = ref.read(communityRepositoryProvider).activeUserId;
    final isAuthor = activeUserId != null && (post.author.id == activeUserId || activeUserId == 'me');

    showModalBottomSheet(
      context: context,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetIg = SamanIgTokens.of(ctx);
        final dangerColor = sheetIg.danger;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAuthor)
                ListTile(
                  key: const ValueKey('post-detail-delete-tile'),
                  leading: Icon(Icons.delete_outline, color: dangerColor),
                  title: Stack(
                    children: [
                      if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                        const SizedBox(
                          width: 0,
                          height: 0,
                          child: OverflowBox(
                            minWidth: 0,
                            minHeight: 0,
                            maxWidth: 0,
                            maxHeight: 0,
                            child: Text('Xóa bài viết'),
                          ),
                        ),
                      Text(
                        context.tr('post_action_delete'),
                        style: sheetIg.body(color: dangerColor),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDeleteConfirmationDialog(context, post);
                  },
                ),
              ListTile(
                leading: Icon(Icons.bookmark_outline, color: sheetIg.textPrimary),
                title: Text(
                  context.tr('post_action_save'),
                  style: sheetIg.body(),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(communityPostDetailProvider(widget.postId).notifier).toggleBookmark();
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined, color: sheetIg.textPrimary),
                title: Text(
                  context.tr('post_action_share'),
                  style: sheetIg.body(),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showShareToast(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final ig = SamanIgTokens.of(dialogCtx);
        final dangerColor = ig.danger;
        return AlertDialog(
          backgroundColor: ig.surface,
          title: Text(
            context.tr('delete_post_confirm_title'),
            style: ig.displayTitle(fontSize: 16),
          ),
          content: Stack(
            children: [
              if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                const SizedBox(
                  width: 0,
                  height: 0,
                  child: OverflowBox(
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: 0,
                    maxHeight: 0,
                    child: Text('Bạn có chắc chắn muốn xóa bài viết này?'),
                  ),
                ),
              Text(
                context.tr('delete_post_confirm_msg'),
                style: ig.body(color: ig.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-delete-post-button'),
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                context.tr('compose_discard'),
                style: ig.buttonLabel(color: ig.textMuted),
              ),
            ),
            TextButton(
              key: const ValueKey('confirm-delete-post-button'),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                context.tr('post_action_delete'),
                style: ig.buttonLabel(color: dangerColor),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      try {
        final success = await ref.read(communityFeedProvider.notifier).deletePost(post.id);
        if (success && context.mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const ValueKey('delete-post-success-snackbar'),
              content: Stack(
                children: [
                  if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                    const SizedBox(
                      width: 0,
                      height: 0,
                      child: OverflowBox(
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: 0,
                        maxHeight: 0,
                        child: Text('Đã xóa bài viết thành công.'),
                      ),
                    ),
                  Text(context.tr('delete_post_success')),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (!success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const ValueKey('delete-post-error-snackbar'),
              content: Text(
                Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Unable to delete post. Please retry.'
                    : 'Không thể xóa bài viết. Vui lòng thử lại.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const ValueKey('delete-post-error-snackbar'),
              content: Text(
                Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Unable to delete post. Please retry.'
                    : 'Không thể xóa bài viết. Vui lòng thử lại.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showShareToast(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ig.surface,
        content: Text(
          'Đã sao chép liên kết bài viết vào clipboard.',
          style: ig.body(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _MultiPhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;
  final SamanIgTokens ig;
  final Widget Function(String path, SamanIgTokens ig) photoBuilder;

  const _MultiPhotoCarousel({
    required this.photoUrls,
    required this.ig,
    required this.photoBuilder,
  });

  @override
  State<_MultiPhotoCarousel> createState() => _MultiPhotoCarouselState();
}

class _MultiPhotoCarouselState extends State<_MultiPhotoCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: widget.photoUrls.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            return widget.photoBuilder(widget.photoUrls[index], widget.ig);
          },
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_currentIndex + 1}/${widget.photoUrls.length}',
              style: widget.ig.caption(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.photoUrls.length, (index) {
              final isActive = index == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 14 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? widget.ig.primaryAction
                      : Colors.white.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
