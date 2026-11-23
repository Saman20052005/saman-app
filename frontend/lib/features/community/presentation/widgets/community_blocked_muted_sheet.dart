import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../widgets/saman_feedback_snackbar.dart';
import '../../domain/models/community_author.dart';
import '../providers/community_social_providers.dart';
import '../tokens/saman_ig_tokens.dart';

enum BlockedMutedMode { blocked, muted }

class CommunityBlockedMutedSheet extends ConsumerWidget {
  final BlockedMutedMode mode;

  const CommunityBlockedMutedSheet({
    super.key,
    required this.mode,
  });

  static Future<void> show(
    BuildContext context, {
    required BlockedMutedMode mode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityBlockedMutedSheet(mode: mode),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(communitySettingsProvider);
    final users =
        mode == BlockedMutedMode.blocked ? state.blockedUsers : state.mutedUsers;
    final title = mode == BlockedMutedMode.blocked
        ? 'Tài khoản đã chặn'
        : 'Tài khoản đã ẩn tiếng';
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
        border: Border(
          top: BorderSide(color: ig.border, width: 1),
          left: BorderSide(color: ig.border, width: 1),
          right: BorderSide(color: ig.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ig.textMuted.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: ig.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${users.length} tài khoản',
                          style: textTheme.bodySmall?.copyWith(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 12,
                            color: ig.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      color: ig.textSecondary,
                    ),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: ig.border),
            if (users.isEmpty)
              Flexible(
                child: _EmptyBlockedMutedState(mode: mode),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _BlockedMutedUserTile(
                      user: user,
                      mode: mode,
                      onAction: () => _handleAction(context, ref, user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    CommunityAuthor user,
  ) async {
    final notifier = ref.read(communitySettingsProvider.notifier);
    final isBlockedMode = mode == BlockedMutedMode.blocked;

    try {
      final stillActive = isBlockedMode
          ? await notifier.unblockUser(user.id)
          : await notifier.unmuteUser(user.id);
      if (!context.mounted) return;

      if (!stillActive) {
        SamanFeedbackSnackBar.show(
          context,
          message: isBlockedMode
              ? 'Đã bỏ chặn ${user.name}'
              : 'Đã bỏ ẩn tiếng ${user.name}',
          type: FeedbackType.success,
        );
      } else {
        SamanFeedbackSnackBar.show(
          context,
          message: isBlockedMode
              ? 'Không thể bỏ chặn ${user.name}'
              : 'Không thể bỏ ẩn tiếng ${user.name}',
          type: FeedbackType.error,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      SamanFeedbackSnackBar.show(
        context,
        message: isBlockedMode
            ? 'Đã xảy ra lỗi khi bỏ chặn ${user.name}'
            : 'Đã xảy ra lỗi khi bỏ ẩn tiếng ${user.name}',
        type: FeedbackType.error,
      );
    }
  }
}

class _BlockedMutedUserTile extends StatelessWidget {
  final CommunityAuthor user;
  final BlockedMutedMode mode;
  final VoidCallback onAction;

  const _BlockedMutedUserTile({
    required this.user,
    required this.mode,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final actionLabel =
        mode == BlockedMutedMode.blocked ? 'Bỏ chặn' : 'Bỏ ẩn tiếng';
    final subtitleText = (user.title != null && user.title!.trim().isNotEmpty)
        ? user.title!
        : (user.handle != null && user.handle!.trim().isNotEmpty
            ? '@${user.handle}'
            : 'Thành viên Saman');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ig.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ig.border, width: 1),
      ),
      child: Row(
        children: [
          _AuthorAvatar(author: user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ig.textPrimary,
                        ),
                      ),
                    ),
                    if (user.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: ig.primaryAction,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: SamanIgTokens.fontFamily,
                    fontSize: 12,
                    color: ig.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: ig.textPrimary,
              backgroundColor: ig.surface,
              side: BorderSide(color: ig.border, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 44),
            ),
            child: Text(
              actionLabel,
              style: textTheme.labelMedium?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ig.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  final CommunityAuthor author;

  const _AuthorAvatar({required this.author});

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final hasUrl =
        author.avatarUrl != null && author.avatarUrl!.trim().isNotEmpty;
    final initial = author.name.trim().isNotEmpty
        ? author.name.trim().characters.first.toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 21,
      backgroundColor: ig.surfaceElevated,
      backgroundImage: hasUrl ? NetworkImage(author.avatarUrl!) : null,
      child: hasUrl
          ? null
          : Text(
              initial,
              style: textTheme.titleMedium?.copyWith(
                fontFamily: SamanIgTokens.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ig.textPrimary,
              ),
            ),
    );
  }
}

class _EmptyBlockedMutedState extends StatelessWidget {
  final BlockedMutedMode mode;

  const _EmptyBlockedMutedState({required this.mode});

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isBlocked = mode == BlockedMutedMode.blocked;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ig.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ig.border, width: 1),
            ),
            child: Icon(
              isBlocked ? Icons.block_rounded : Icons.volume_off_rounded,
              size: 24,
              color: ig.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isBlocked
                ? 'Chưa có tài khoản nào bị chặn'
                : 'Chưa có tài khoản nào bị ẩn tiếng',
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ig.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isBlocked
                ? 'Những người bạn chặn sẽ không thể xem bài viết hoặc nhắn tin cho bạn.'
                : 'Bài viết và tin 24h từ những người bạn ẩn tiếng sẽ không xuất hiện trên bảng tin.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 13,
              color: ig.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
