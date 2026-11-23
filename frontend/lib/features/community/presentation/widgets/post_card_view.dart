import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_translations.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';
import '../../domain/models/community_dm.dart';
import '../../domain/models/community_post.dart';
import '../providers/community_dm_provider.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';
import '../screens/profile/community_profile_screen.dart';
import '../tokens/saman_ig_tokens.dart';
import 'community_question_card.dart';
import 'ig_post_attachment_sticker.dart';
import 'ig_post_media_carousel.dart';

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
    final ig = SamanIgTokens.of(context);
    final hasPhotos = post.photoUrls.isNotEmpty;
    final hasActiveStory = ref.watch(
      communityStoriesProvider.select(
        (s) => s.groups.any(
          (g) => g.author.id == post.author.id && g.stories.isNotEmpty,
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(
            color: ig.borderSubtle,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IgPostHeader(
            post: post,
            ig: ig,
            hasActiveStory: hasActiveStory,
            onAuthorTap: onAuthorTap ??
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
            onOptionsTap: () => _showPostOptionsSheet(context, ref),
          ),
          IgPostDoubleTapOverlay(
            onTap: onOpenDetail,
            onDoubleTap: () {
              if (!post.isLiked) {
                onLikeToggle?.call();
              }
            },
            child: hasPhotos
                ? IgPostMediaCarousel(photoUrls: post.photoUrls)
                : _IgNonPhotoContent(
                    post: post,
                    onOpenDetail: onOpenDetail,
                  ),
          ),
          _IgPostActionBar(
            post: post,
            ig: ig,
            onLikeToggle: onLikeToggle,
            onOpenDetail: onOpenDetail,
            onShare: onShare ?? () => _showShareToDmSheet(context),
            onBookmarkToggle: onBookmarkToggle,
          ),
          _IgPostFooter(
            post: post,
            ig: ig,
            showInlineCaption: hasPhotos,
            showStickersInFooter: hasPhotos,
            onOpenDetail: onOpenDetail,
          ),
        ],
      ),
    );
  }

  void _showPostOptionsSheet(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final effectiveUserId =
        currentUserId ?? ref.read(communityRepositoryProvider).activeUserId;
    final isAuthor = effectiveUserId != null &&
        (post.author.id == effectiveUserId || effectiveUserId == 'me');
    final canDelete = isAuthor || onDelete != null;
    final isOtherAuthor = effectiveUserId == null ||
        (post.author.id != effectiveUserId && post.author.id != 'me');

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
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetIg.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (canDelete)
                ListTile(
                  key: const ValueKey('post-options-delete-tile'),
                  leading: Icon(Icons.delete_outline, color: dangerColor),
                  title: Stack(
                    children: [
                      if (Localizations.maybeLocaleOf(context)?.languageCode !=
                          'vi')
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
                    _showDeleteConfirmationDialog(context, ref);
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.bookmark_outline,
                  color: sheetIg.textPrimary,
                ),
                title: Text(
                  context.tr('post_action_save'),
                  style: sheetIg.body(color: sheetIg.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onBookmarkToggle?.call();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share_outlined,
                  color: sheetIg.textPrimary,
                ),
                title: Text(
                  context.tr('post_action_share'),
                  style: sheetIg.body(color: sheetIg.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (onShare != null) {
                    onShare!.call();
                  } else {
                    _showShareToDmSheet(context);
                  }
                },
              ),
              if (isOtherAuthor) ...[
                ListTile(
                  key: const ValueKey('post-options-mute-tile'),
                  leading: Icon(
                    Icons.volume_off_outlined,
                    color: sheetIg.textPrimary,
                  ),
                  title: Text(
                    context.tr('post_action_mute_author'),
                    style: sheetIg.body(color: sheetIg.textPrimary),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _handleMuteAuthor(context, ref);
                  },
                ),
                ListTile(
                  key: const ValueKey('post-options-block-tile'),
                  leading: Icon(Icons.block_rounded, color: dangerColor),
                  title: Text(
                    context.tr('post_action_block_author'),
                    style: sheetIg.body(color: dangerColor),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showBlockAuthorConfirmation(context, ref);
                  },
                ),
              ],
              ListTile(
                key: const ValueKey('post-options-report-tile'),
                leading: Icon(Icons.flag_outlined, color: dangerColor),
                title: Text(
                  context.tr('post_action_report'),
                  style: sheetIg.body(color: dangerColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportReasonSheet(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final ig = SamanIgTokens.of(dialogCtx);
        return AlertDialog(
          backgroundColor: ig.surface,
          title: Text(
            context.tr('delete_post_confirm_title'),
            style: ig.displayTitle(fontSize: 17, color: ig.textPrimary),
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
                style: ig.buttonLabel(color: ig.danger),
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
                    if (Localizations.maybeLocaleOf(context)?.languageCode !=
                        'vi')
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

  Future<void> _handleMuteAuthor(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(communitySettingsProvider.notifier)
          .muteUser(post.author.id);
      await ref.read(communityFeedProvider.notifier).refresh();
      if (context.mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: context.tr('post_mute_success'),
          type: FeedbackType.info,
        );
      }
    } catch (_) {
      if (context.mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: context.tr('post_report_error'),
          type: FeedbackType.error,
        );
      }
    }
  }

  Future<void> _showBlockAuthorConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final ig = SamanIgTokens.of(dialogCtx);
        return AlertDialog(
          backgroundColor: ig.surface,
          title: Text(
            context.tr('post_block_confirm_title'),
            style: ig.displayTitle(fontSize: 17, color: ig.textPrimary),
          ),
          content: Text(
            context.tr('post_block_confirm_msg'),
            style: ig.body(color: ig.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(
                context.tr('compose_discard'),
                style: ig.buttonLabel(color: ig.textMuted),
              ),
            ),
            TextButton(
              key: const ValueKey('confirm-block-author-button'),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                context.tr('post_block_confirm_btn'),
                style: ig.buttonLabel(color: ig.danger),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(communitySettingsProvider.notifier)
            .blockUser(post.author.id);
        await ref.read(communityFeedProvider.notifier).refresh();
        if (context.mounted) {
          SamanFeedbackSnackBar.show(
            context,
            message: context.tr('post_block_success'),
            type: FeedbackType.info,
          );
        }
      } catch (_) {
        if (context.mounted) {
          SamanFeedbackSnackBar.show(
            context,
            message: context.tr('post_report_error'),
            type: FeedbackType.error,
          );
        }
      }
    }
  }

  void _showReportReasonSheet(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final reasons = <({String key, String labelKey})>[
      (key: 'spam', labelKey: 'post_report_reason_spam'),
      (key: 'harassment', labelKey: 'post_report_reason_harassment'),
      (key: 'misinformation', labelKey: 'post_report_reason_misinformation'),
      (key: 'inappropriate', labelKey: 'post_report_reason_inappropriate'),
      (key: 'other', labelKey: 'post_report_reason_other'),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final sheetIg = SamanIgTokens.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('post_report_title'),
                  style: sheetIg.displayTitle(
                    fontSize: 17,
                    color: sheetIg.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (r) => ListTile(
                    key: ValueKey('report-reason-${r.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.tr(r.labelKey),
                      style: sheetIg.body(
                        fontSize: 14,
                        color: sheetIg.textPrimary,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: sheetIg.textSecondary,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await ref
                            .read(communitySettingsProvider.notifier)
                            .reportContent(
                              targetType: 'post',
                              targetId: post.id,
                              reason: r.key,
                            );
                        if (context.mounted) {
                          SamanFeedbackSnackBar.show(
                            context,
                            message: context.tr('post_report_success'),
                            type: FeedbackType.success,
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          SamanFeedbackSnackBar.show(
                            context,
                            message: context.tr('post_report_error'),
                            type: FeedbackType.error,
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showShareToDmSheet(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SharePostToDmSheet(post: post),
    );
  }
}

class _IgPostHeader extends StatelessWidget {
  final CommunityPost post;
  final SamanIgTokens ig;
  final bool hasActiveStory;
  final VoidCallback onAuthorTap;
  final VoidCallback onOptionsTap;

  const _IgPostHeader({
    required this.post,
    required this.ig,
    required this.hasActiveStory,
    required this.onAuthorTap,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    final subLabel = post.topic.isNotEmpty
        ? '${post.timeAgo} • ${post.topic}'
        : post.timeAgo;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAuthorTap,
              child: Row(
                children: [
                  _IgAuthorAvatar(
                    name: post.author.name,
                    avatarUrl: post.author.avatarUrl,
                    hasActiveStory: hasActiveStory,
                    ig: ig,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.author.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ig.username(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (post.author.isVerified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_rounded,
                                size: 15,
                                color: ig.primaryAction,
                              ),
                            ],
                            if (post.type == CommunityPostType.qa &&
                                post.qaInfo != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ig.surfaceElevated,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: ig.border,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    post.qaInfo!.categoryTag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ig.caption(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: ig.primaryAction,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ig.caption(
                            fontSize: 11.5,
                            color: ig.textSecondary,
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
            constraints: const BoxConstraints(
              minWidth: SamanIgTokens.minTouchTarget,
              minHeight: SamanIgTokens.minTouchTarget,
            ),
            icon: Icon(
              Icons.more_horiz_rounded,
              color: ig.textPrimary,
              size: 20,
            ),
            onPressed: onOptionsTap,
          ),
        ],
      ),
    );
  }
}

class _IgAuthorAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool hasActiveStory;
  final SamanIgTokens ig;

  const _IgAuthorAvatar({
    required this.name,
    required this.avatarUrl,
    required this.hasActiveStory,
    required this.ig,
  });

  Widget _buildInitial() {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    return ColoredBox(
      color: ig.surfaceElevated,
      child: Center(
        child: Text(
          initial,
          style: ig.username(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ig.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage(String url) {
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('/static/')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitial(),
      );
    }
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitial(),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _buildInitial();
  }

  @override
  Widget build(BuildContext context) {
    final innerAvatar = ClipOval(
      child: SizedBox(
        width: 32,
        height: 32,
        child: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? _buildAvatarImage(avatarUrl!)
            : _buildInitial(),
      ),
    );

    if (hasActiveStory) {
      return Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SamanIgTokens.storyGradient,
        ),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ig.canvas,
          ),
          child: innerAvatar,
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ig.border, width: 0.5),
      ),
      child: innerAvatar,
    );
  }
}

class _IgNonPhotoContent extends StatelessWidget {
  final CommunityPost post;
  final VoidCallback? onOpenDetail;

  const _IgNonPhotoContent({
    required this.post,
    this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                post.caption,
                style: ig.body(
                  fontSize: 14,
                  height: 1.45,
                  color: ig.textPrimary,
                ),
              ),
            ),
          if (post.activitySnapshot != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IgPostSnapshotSticker(
                snapshot: post.activitySnapshot!,
                onOpenDetail: onOpenDetail,
              ),
            ),
          if (post.type == CommunityPostType.workout &&
              post.workoutAttachment != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IgPostWorkoutSticker(
                attachment: post.workoutAttachment!,
                onViewWorkout: onOpenDetail,
              ),
            )
          else if (post.type == CommunityPostType.qa && post.qaInfo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CommunityQuestionCard(
                qaInfo: post.qaInfo!,
                onJoinDiscussion: onOpenDetail,
              ),
            )
          else if (post.nutritionInfo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IgPostNutritionSticker(
                nutritionInfo: post.nutritionInfo!,
                onViewMacros: onOpenDetail,
              ),
            ),
        ],
      ),
    );
  }
}

class _IgPostActionBar extends StatelessWidget {
  final CommunityPost post;
  final SamanIgTokens ig;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onOpenDetail;
  final VoidCallback onShare;
  final VoidCallback? onBookmarkToggle;

  const _IgPostActionBar({
    required this.post,
    required this.ig,
    this.onLikeToggle,
    this.onOpenDetail,
    required this.onShare,
    this.onBookmarkToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 4, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: SamanIgTokens.minTouchTarget,
                  minHeight: SamanIgTokens.minTouchTarget,
                ),
                onPressed: onLikeToggle,
                icon: Icon(
                  post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 24,
                  color: post.isLiked ? ig.likeHeart : ig.textPrimary,
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: SamanIgTokens.minTouchTarget,
                  minHeight: SamanIgTokens.minTouchTarget,
                ),
                onPressed: onOpenDetail,
                icon: Icon(
                  Icons.mode_comment_outlined,
                  size: 22,
                  color: ig.textPrimary,
                ),
              ),
              InkWell(
                key: ValueKey('post-share-button-${post.id}'),
                onTap: onShare,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: SamanIgTokens.minTouchTarget,
                    minHeight: SamanIgTokens.minTouchTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.send_outlined,
                          size: 21,
                          color: ig.textPrimary,
                        ),
                        if (post.shareCount > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '${post.shareCount}',
                            style: ig.username(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (post.type == CommunityPostType.qa)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ElevatedButton(
                onPressed: onOpenDetail,
                style: ig.primaryButtonStyle(
                  minHeight: SamanIgTokens.minTouchTarget,
                  borderRadius: 10,
                ).copyWith(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tham gia thảo luận',
                      style: ig.buttonLabel(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 14),
                  ],
                ),
              ),
            )
          else
            IconButton(
              constraints: const BoxConstraints(
                minWidth: SamanIgTokens.minTouchTarget,
                minHeight: SamanIgTokens.minTouchTarget,
              ),
              onPressed: onBookmarkToggle,
              icon: Icon(
                post.isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 24,
                color: ig.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}

class _IgPostFooter extends StatelessWidget {
  final CommunityPost post;
  final SamanIgTokens ig;
  final bool showInlineCaption;
  final bool showStickersInFooter;
  final VoidCallback? onOpenDetail;

  const _IgPostFooter({
    required this.post,
    required this.ig,
    required this.showInlineCaption,
    required this.showStickersInFooter,
    this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final hasStickerInFooter = showStickersInFooter &&
        (post.activitySnapshot != null ||
            post.workoutAttachment != null ||
            post.nutritionInfo != null);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isLikeCountHidden)
            Text(
              context.tr('post_likes_hidden'),
              style: ig.username(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: ig.textSecondary,
              ),
            )
          else if (post.type != CommunityPostType.qa || post.likeCount > 0)
            Text(
              '${post.likeCount} lượt thích',
              style: ig.username(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (showInlineCaption && post.caption.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${post.author.name} ',
                    style: ig.username(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: post.caption,
                    style: ig.body(
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasStickerInFooter) ...[
            const SizedBox(height: 10),
            if (post.activitySnapshot != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IgPostSnapshotSticker(
                  snapshot: post.activitySnapshot!,
                  onOpenDetail: onOpenDetail,
                ),
              ),
            if (post.workoutAttachment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IgPostWorkoutSticker(
                  attachment: post.workoutAttachment!,
                  onViewWorkout: onOpenDetail,
                ),
              ),
            if (post.nutritionInfo != null)
              IgPostNutritionSticker(
                nutritionInfo: post.nutritionInfo!,
                onViewMacros: onOpenDetail,
              ),
          ],
          if (post.type != CommunityPostType.qa) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onOpenDetail,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Xem tất cả ${post.commentCount} bình luận',
                  style: ig.caption(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ig.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SharePostToDmSheet extends ConsumerStatefulWidget {
  final CommunityPost post;

  const _SharePostToDmSheet({required this.post});

  @override
  ConsumerState<_SharePostToDmSheet> createState() =>
      _SharePostToDmSheetState();
}

class _SharePostToDmSheetState extends ConsumerState<_SharePostToDmSheet> {
  String? _sendingConversationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inboxState = ref.read(communityInboxProvider);
      if (inboxState.conversations.isEmpty && !inboxState.isLoading) {
        ref.read(communityInboxProvider.notifier).loadConversations();
      }
    });
  }

  Future<void> _sendToConversation(DmConversation conv) async {
    if (_sendingConversationId != null) return;
    setState(() => _sendingConversationId = conv.id);
    try {
      final msg = await ref
          .read(communityChatThreadProvider(conv.id).notifier)
          .sendMessage(
            type: DmMessageType.postShare,
            sharedPostId: widget.post.id,
          );
      if (msg != null) {
        unawaited(
          ref
              .read(communityRepositoryProvider)
              .sharePost(widget.post.id)
              .catchError((_) => widget.post.shareCount),
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      SamanFeedbackSnackBar.show(
        context,
        message: msg != null
            ? context.tr('share_post_sent_success')
            : context.tr('share_post_send_error'),
        type: msg != null ? FeedbackType.success : FeedbackType.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingConversationId = null);
      SamanFeedbackSnackBar.show(
        context,
        message: context.tr('share_post_send_error'),
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(text: 'https://saman.app/community/post/${widget.post.id}'),
    );
    unawaited(
      ref
          .read(communityRepositoryProvider)
          .sharePost(widget.post.id)
          .catchError((_) => widget.post.shareCount),
    );
    if (!mounted) return;
    Navigator.pop(context);
    SamanFeedbackSnackBar.show(
      context,
      message: context.tr('share_link_copied'),
      type: FeedbackType.info,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final inboxState = ref.watch(communityInboxProvider);
    final conversations = inboxState.conversations;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ig.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr('share_post_title'),
              style: ig.displayTitle(fontSize: 16, color: ig.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              context.tr('share_post_subtitle'),
              style: ig.caption(fontSize: 12, color: ig.textSecondary),
            ),
            const SizedBox(height: 12),
            if (inboxState.isLoading && conversations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CircularProgressIndicator(color: ig.primaryAction),
                ),
              )
            else if (conversations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    context.tr('share_post_empty_threads'),
                    style: ig.body(fontSize: 13, color: ig.textSecondary),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: ig.border),
                  itemBuilder: (ctx, index) {
                    final conv = conversations[index];
                    final isSending = _sendingConversationId == conv.id;
                    final initial = conv.peer.name.isNotEmpty
                        ? conv.peer.name[0].toUpperCase()
                        : 'S';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: ig.surfaceElevated,
                        child: Text(
                          initial,
                          style: ig.username(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ig.primaryAction,
                          ),
                        ),
                      ),
                      title: Text(
                        conv.peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ig.username(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ig.textPrimary,
                        ),
                      ),
                      trailing: ElevatedButton(
                        key: ValueKey('share-dm-send-${conv.id}'),
                        onPressed: _sendingConversationId == null
                            ? () => _sendToConversation(conv)
                            : null,
                        style: ig.primaryButtonStyle(
                          minHeight: SamanIgTokens.minTouchTarget,
                          borderRadius: 10,
                        ).copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 14),
                          ),
                        ),
                        child: isSending
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ig.onPrimaryAction,
                                ),
                              )
                            : Text(
                                context.tr('share_post_send_btn'),
                                style: ig.buttonLabel(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Divider(height: 1, color: ig.border),
            ListTile(
              key: const ValueKey('share-copy-link-tile'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.link_rounded, color: ig.textPrimary),
              title: Text(
                context.tr('share_copy_link'),
                style: ig.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ig.textPrimary,
                ),
              ),
              onTap: _copyLink,
            ),
          ],
        ),
      ),
    );
  }
}
