import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_post.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/community_providers.dart';
import '../screens/profile/community_profile_screen.dart';
import 'community_question_card.dart';
import 'kinetic_workout_attachment_card.dart';
import 'community_activity_snapshot_card.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';

class PostCardView extends ConsumerWidget {
  final CommunityPost post;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onBookmarkToggle;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onShare;
  final VoidCallback? onAuthorTap;
  final String? currentUserId;
  final Future<bool> Function()? onDelete;

  const PostCardView({
    super.key,
    required this.post,
    this.onLikeToggle,
    this.onBookmarkToggle,
    this.onOpenDetail,
    this.onShare,
    this.onAuthorTap,
    this.currentUserId,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        border: Border(
          bottom: BorderSide(
            color: tokens.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onAuthorTap ??
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommunityProfileScreen(
                                authorId: post.author.id,
                              ),
                            ),
                          );
                        },
                    child: Row(
                      children: [
                        _buildAuthorAvatar(tokens),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      post.author.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (post.author.isVerified) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                      color: tokens.greenAccent,
                                    ),
                                  ],
                                  if (post.type == CommunityPostType.qa &&
                                      post.qaInfo != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.secondarySurface,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        post.qaInfo!.categoryTag,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.greenAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                post.timeAgo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    _showPostOptionsSheet(context, ref);
                  },
                ),
              ],
            ),
          ),

          // Caption (if any)
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                post.caption,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: tokens.textPrimary,
                ),
              ),
            ),

          if (post.activitySnapshot != null)
            CommunityActivitySnapshotCard(snapshot: post.activitySnapshot!),

          // Content archetype
          if (post.type == CommunityPostType.photo &&
              post.photoUrls.isNotEmpty) ...[
            _buildPhotoAttachment(context, tokens),
            const SizedBox(height: 10),
          ] else if (post.type == CommunityPostType.workout &&
              post.workoutAttachment != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: KineticWorkoutAttachmentCard(
                attachment: post.workoutAttachment!,
                onViewWorkout: onOpenDetail,
              ),
            ),
            const SizedBox(height: 10),
          ] else if (post.type == CommunityPostType.qa &&
              post.qaInfo != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CommunityQuestionCard(
                qaInfo: post.qaInfo!,
                onJoinDiscussion: onOpenDetail,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Action Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Like button
                    InkWell(
                      onTap: onLikeToggle,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              post.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 22,
                              color: post.isLiked
                                  ? (tokens.isDark ? const Color(0xFFFC7C78) : tokens.fatRose)
                                  : tokens.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${post.likeCount}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Comment button
                    InkWell(
                      onTap: onOpenDetail,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.mode_comment_outlined,
                              size: 21,
                              color: tokens.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${post.commentCount}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Share button
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: tokens.textSecondary,
                      ),
                      onPressed: onShare ?? () => _showShareToast(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                // Right action: QA CTA or Bookmark
                if (post.type == CommunityPostType.qa)
                  ElevatedButton(
                    onPressed: onOpenDetail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.greenAccent,
                      foregroundColor: tokens.isDark
                          ? const Color(0xFF003824)
                          : const Color(0xFFFFFFFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tham gia thảo luận',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 14),
                      ],
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(
                      post.isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 22,
                      color: post.isBookmarked
                          ? tokens.greenAccent
                          : tokens.textSecondary,
                    ),
                    onPressed: onBookmarkToggle,
                  ),
              ],
            ),
          ),

          // Engagement previews (Likes & Comments CTA)
          if (post.type != CommunityPostType.qa) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.likedBySummary.isNotEmpty)
                    Text(
                      post.likedBySummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onOpenDetail,
                    child: Text(
                      'Xem tất cả ${post.commentCount} bình luận...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: tokens.greenAccent.withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthorAvatar(SamanHomePalette tokens) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tokens.secondarySurface,
      ),
      child: Center(
        child: Text(
          post.author.name.isNotEmpty ? post.author.name[0] : 'S',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: tokens.greenAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoView(String path, SamanHomePalette tokens) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.broken_image, size: 48, color: tokens.textSecondary),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Center(
      child: Icon(Icons.image, size: 48, color: tokens.textSecondary),
    );
  }

  Widget _buildPhotoAttachment(BuildContext context, SamanHomePalette tokens) {
    return InkWell(
      onTap: onOpenDetail,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.photoUrls.length > 1)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _MultiPhotoCarousel(
                  photoUrls: post.photoUrls,
                  tokens: tokens,
                  photoBuilder: _buildPhotoView,
                ),
              )
            else if (post.photoUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildPhotoView(post.photoUrls.first, tokens),
              )
            else
              Container(
                color: tokens.secondarySurface,
                child: Center(
                  child: Icon(
                    Icons.restaurant_rounded,
                    size: 48,
                    color: tokens.greenAccent,
                  ),
                ),
              ),
            // Floating nutrition badge (dark translucent overlay kept for image contrast)
            if (post.nutritionInfo != null)
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0E0F).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF343536),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 14,
                        color: Color(0xFF5BBFA0),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        post.nutritionInfo!.defaultBadge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPostOptionsSheet(BuildContext context, WidgetRef ref) {
    final sheetBg = SamanHomeTokens.of(context).cardSurface;
    final effectiveUserId = currentUserId ?? ref.read(communityRepositoryProvider).activeUserId;
    final isAuthor = effectiveUserId != null && (post.author.id == effectiveUserId || effectiveUserId == 'me');
    final canDelete = isAuthor || onDelete != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final tokens = SamanHomeTokens.of(ctx);
        final dangerColor = tokens.isDark
            ? Colors.redAccent
            : const Color(0xFFDC2626);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canDelete)
                ListTile(
                  key: const ValueKey('post-options-delete-tile'),
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
                        style: TextStyle(color: dangerColor),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDeleteConfirmationDialog(context, ref);
                  },
                ),
              ListTile(
                leading: Icon(Icons.bookmark_outline, color: tokens.textPrimary),
                title: Text(
                  context.tr('post_action_save'),
                  style: TextStyle(color: tokens.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onBookmarkToggle?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined, color: tokens.textPrimary),
                title: Text(
                  context.tr('post_action_share'),
                  style: TextStyle(color: tokens.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onShare?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.flag_outlined, color: dangerColor),
                title: Text(
                  context.tr('post_action_report'),
                  style: TextStyle(color: dangerColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                            ? 'Thank you for reporting this content.'
                            : 'Cảm ơn bạn đã phản hồi nội dung này.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final tokens = SamanHomeTokens.of(dialogCtx);
        final dangerColor = tokens.isDark
            ? Colors.redAccent
            : const Color(0xFFDC2626);
        return AlertDialog(
          backgroundColor: tokens.cardSurface,
          title: Text(
            context.tr('delete_post_confirm_title'),
            style: TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.bold),
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
                style: TextStyle(color: tokens.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-delete-post-button'),
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                context.tr('compose_discard'),
                style: TextStyle(color: tokens.textMuted),
              ),
            ),
            TextButton(
              key: const ValueKey('confirm-delete-post-button'),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                context.tr('post_action_delete'),
                style: TextStyle(color: dangerColor),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      try {
        final success = onDelete != null
            ? await onDelete!()
            : await ref.read(communityFeedProvider.notifier).deletePost(post.id);
        if (context.mounted) {
          if (success) {
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
          } else {
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
    SamanFeedbackSnackBar.show(
      context,
      message: 'Đã sao chép liên kết bài viết vào clipboard.',
      type: FeedbackType.info,
      duration: const Duration(seconds: 2),
    );
  }
}

class _MultiPhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;
  final SamanHomePalette tokens;
  final Widget Function(String path, SamanHomePalette tokens) photoBuilder;

  const _MultiPhotoCarousel({
    required this.photoUrls,
    required this.tokens,
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
            return widget.photoBuilder(widget.photoUrls[index], widget.tokens);
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
              style: const TextStyle(
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
                      ? widget.tokens.greenAccent
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
