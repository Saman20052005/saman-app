import 'dart:io';
import '../../../../config/app_translations.dart';
import '../widgets/community_comment_composer.dart';
import 'package:flutter/material.dart';
import '../widgets/community_activity_snapshot_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_post.dart';
import '../providers/community_providers.dart';
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
    final detailState =
        ref.watch(communityPostDetailProvider(widget.postId));
    final detailNotifier =
        ref.read(communityPostDetailProvider(widget.postId).notifier);
    final displayPost = detailState.post ?? widget.initialPost;

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(displayPost, detailNotifier),

            // Honest Preview Notice Banner
            _buildPreviewNoticeBanner(),

            // Main Content Scroll
            Expanded(
              child: (detailState.isLoading && displayPost == null)
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SamanHomeTokens.greenAccent,
                      ),
                    )
                  : displayPost == null
                      ? _buildNotFoundState(context, () {
                          detailNotifier.loadPost();
                        })
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 110),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Author Section
                              _buildAuthorSection(displayPost),

                              // Post Body
                              _buildPostBody(displayPost),

                              // Photo / Workout Attachment
                              _buildPostAttachment(displayPost),

                              // Engagement Action Bar
                              _buildActionBar(
                                displayPost,
                                detailNotifier,
                              ),

                              // Social Likes Preview
                              _buildSocialLikes(displayPost),

                              const SizedBox(height: 16),
                              const Divider(
                                color: Color(0xFF292A2B),
                                height: 1,
                              ),

                              // Discussion & Comments List
                              _buildDiscussionSection(displayPost, detailNotifier),
                              if (detailState.commentsCursor != null || detailState.commentErrorKey == 'community_comments_load_error')
                                TextButton(
                                  onPressed: detailState.isLoadingComments ? null
                                      : () => detailNotifier.loadComments(more: detailState.commentsCursor != null),
                                  child: Text(context.tr('community_comments_more')),
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

  Widget _buildPreviewNoticeBanner() {
    final isRemote = ref.watch(useRemoteCommunityProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF1B1C1D),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: SamanHomeTokens.greenAccent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isRemote
                  ? context.tr('community_remote_comments_notice')
                  : 'Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFBBCAAF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState(BuildContext context, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFF1F2021),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.article_outlined,
                size: 28,
                color: Color(0xFFBBCAAF),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                  ? 'This post may have been removed or does not exist in this preview.'
                  : 'Bài viết này có thể đã bị gỡ hoặc không tồn tại trong phiên xem trước này.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFBBCAAF),
              ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SamanHomeTokens.greenAccent,
                    foregroundColor: const Color(0xFF003824),
                  ),
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
                    foregroundColor: SamanHomeTokens.textWhite,
                    side: const BorderSide(color: Color(0xFF343536)),
                  ),
                  child: Text(
                    Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                        ? 'Retry'
                        : 'Thử lại',
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
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF1F2021),
            width: 1,
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
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: SamanHomeTokens.textWhite,
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: SamanHomeTokens.textWhite,
                        ),
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
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: Color(0xFFBBCAAF),
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
                        ? SamanHomeTokens.greenAccent
                        : const Color(0xFFBBCAAF),
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SamanHomeTokens.greenAccent,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: Color(0xFF003824),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorSection(CommunityPost post) {
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF343536),
                  ),
                  child: Center(
                    child: Text(
                      post.author.name.isNotEmpty ? post.author.name[0] : 'S',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: SamanHomeTokens.greenAccent,
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  SamanHomeTokens.greenAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 13,
                                  color: SamanHomeTokens.greenAccent,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Thành viên Saman',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: SamanHomeTokens.greenAccent,
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
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFBBCAAF),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF86948A),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.public_rounded,
                            size: 13,
                            color: Color(0xFF86948A),
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
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Color(0xFFBBCAAF),
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

  Widget _buildPostBody(CommunityPost post) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.type == CommunityPostType.qa && post.qaInfo != null) ...[
            Text(
              post.qaInfo!.question,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.4,
                color: SamanHomeTokens.textWhite,
              ),
            ),
            if (post.qaInfo!.details != null && post.qaInfo!.details!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.qaInfo!.details!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFFC5C6CF),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (post.caption.isNotEmpty)
            Text(
              post.caption,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: SamanHomeTokens.textWhite,
              ),
            ),
          if (post.nutritionInfo?.proTip != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1C1D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF292A2B),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: SamanHomeTokens.greenAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      post.nutritionInfo!.proTip!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE3E2E3),
                        height: 1.4,
                      ),
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
                    SamanHomeTokens.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.calories} kcal',
                    const Color(0xFFFC7C78),
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.carbsGrams.toStringAsFixed(0)}g Carbs',
                    const Color(0xFFC5C6CF),
                  ),
                  const SizedBox(width: 8),
                  _buildMacroTag(
                    '${post.nutritionInfo!.fatGrams.toStringAsFixed(0)}g Fat',
                    const Color(0xFF86948A),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroTag(String label, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
        borderRadius: BorderRadius.circular(8),
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: SamanHomeTokens.textWhite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoView(String path) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 48, color: Color(0xFFBBCAAF)),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return const Center(
      child: Icon(Icons.image, size: 48, color: Color(0xFFBBCAAF)),
    );
  }

  Widget _buildPostAttachment(CommunityPost post) {
    if (post.activitySnapshot != null) return CommunityActivitySnapshotCard(snapshot: post.activitySnapshot!);

    if (post.type == CommunityPostType.photo && post.photoUrls.isNotEmpty) {
      final photoUrl = post.photoUrls.first;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: const Color(0xFF292A2B),
              child: _buildPhotoView(photoUrl),
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
                    color: const Color(0xFF1B1C1D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        post.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: post.isLiked
                            ? const Color(0xFFFC7C78)
                            : const Color(0xFFBBCAAF),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likeCount}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SamanHomeTokens.textWhite,
                        ),
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
                  color: const Color(0xFF1B1C1D),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_rounded,
                      size: 18,
                      color: Color(0xFFBBCAAF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${post.commentCount}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.textWhite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1B1C1D),
                ),
                child: const Icon(
                  Icons.share_rounded,
                  size: 18,
                  color: Color(0xFFBBCAAF),
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
                  ? SamanHomeTokens.greenAccent
                  : const Color(0xFFBBCAAF),
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

  Widget _buildSocialLikes(CommunityPost post) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Row(
            children: [
              _buildSmallAvatar('MK', const Color(0xFF10B981)),
              _buildSmallAvatar('TH', const Color(0xFFFC7C78)),
              _buildSmallAvatar('HL', const Color(0xFF39393A)),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              post.likedBySummary,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFBBCAAF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAvatar(String initials, Color color) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.2),
        border: Border.all(
          color: const Color(0xFF121314),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionSection(
    CommunityPost post,
    CommunityPostDetailNotifier notifier,
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: SamanHomeTokens.textWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF292A2B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${post.commentCount}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFBBCAAF),
                        ),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFBBCAAF),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: Color(0xFFBBCAAF),
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFBBCAAF),
                  ),
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
              return _buildCommentThread(comment, notifier);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommentThread(
    CommunityComment comment,
    CommunityPostDetailNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSingleCommentBubble(comment, notifier),
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
    CommunityPostDetailNotifier notifier, {
    bool isNested = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isNested ? 32 : 38,
          height: isNested ? 32 : 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF292A2B),
          ),
          child: Center(
            child: Text(
              comment.author.name.isNotEmpty ? comment.author.name[0] : 'S',
              style: TextStyle(
                fontSize: isNested ? 13 : 15,
                fontWeight: FontWeight.bold,
                color: SamanHomeTokens.greenAccent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isNested
                  ? const Color(0xFF1F2021)
                  : const Color(0xFF1B1C1D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF292A2B),
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
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: SamanHomeTokens.textWhite,
                              ),
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
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Tác giả',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF003824),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF86948A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  comment.content,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFFE3E2E3),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.thumb_up_alt_rounded,
                          size: 13,
                          color: Color(0xFF86948A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${comment.likeCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF86948A),
                          ),
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
                      child: const Text(
                        'Trả lời',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: SamanHomeTokens.greenAccent,
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
    final activeUserId = ref.read(communityRepositoryProvider).activeUserId;
    final isAuthor = activeUserId != null && (post.author.id == activeUserId || activeUserId == 'me');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1C1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAuthor)
                ListTile(
                  key: const ValueKey('post-detail-delete-tile'),
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDeleteConfirmationDialog(context, post);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline, color: Colors.white),
                title: Text(
                  context.tr('post_action_save'),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(communityPostDetailProvider(widget.postId).notifier).toggleBookmark();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: Colors.white),
                title: Text(
                  context.tr('post_action_share'),
                  style: const TextStyle(color: Colors.white),
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
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2021),
        title: Text(
          context.tr('delete_post_confirm_title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              style: const TextStyle(color: Color(0xFFE5E7EB)),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-delete-post-button'),
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              context.tr('compose_discard'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            key: const ValueKey('confirm-delete-post-button'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              context.tr('post_action_delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF1F2021),
        content: Text(
          'Đã sao chép liên kết bài viết vào clipboard.',
          style: TextStyle(color: Colors.white),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
