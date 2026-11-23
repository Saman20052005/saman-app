import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';
import '../../domain/models/community_author.dart';
import '../providers/community_social_providers.dart';

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
    final tokens = SamanHomeTokens.of(context);
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
        color: tokens.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanHomeTokens.radiusLg),
        ),
        border: Border(
          top: BorderSide(color: tokens.border, width: 1),
          left: BorderSide(color: tokens.border, width: 1),
          right: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.borderHigh,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${users.length} tài khoản',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: tokens.textSecondary,
                    ),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.border),
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
    final tokens = SamanHomeTokens.of(context);
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
        color: tokens.secondarySurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        border: Border.all(color: tokens.border, width: 1),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (user.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: tokens.greenAccent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.textPrimary,
              backgroundColor: tokens.cardSurface,
              side: BorderSide(color: tokens.border, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
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
    final tokens = SamanHomeTokens.of(context);
    final hasUrl =
        author.avatarUrl != null && author.avatarUrl!.trim().isNotEmpty;
    final initial = author.name.trim().isNotEmpty
        ? author.name.trim().characters.first.toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 21,
      backgroundColor: tokens.cardSurfaceElevated,
      backgroundImage: hasUrl ? NetworkImage(author.avatarUrl!) : null,
      child: hasUrl
          ? null
          : Text(
              initial,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
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
    final tokens = SamanHomeTokens.of(context);
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
              color: tokens.secondarySurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(color: tokens.border, width: 1),
            ),
            child: Icon(
              isBlocked ? Icons.block_rounded : Icons.volume_off_rounded,
              size: 24,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isBlocked
                ? 'Chưa có tài khoản nào bị chặn'
                : 'Chưa có tài khoản nào bị ẩn tiếng',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isBlocked
                ? 'Những người bạn chặn sẽ không thể xem bài viết hoặc nhắn tin cho bạn.'
                : 'Bài viết và tin 24h từ những người bạn ẩn tiếng sẽ không xuất hiện trên bảng tin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: tokens.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
