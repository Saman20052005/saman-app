import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_story.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';
import '../screens/stories/community_story_viewer_screen.dart';
import 'community_create_story_sheet.dart';

class CommunityStoryTray extends ConsumerWidget {
  const CommunityStoryTray({
    super.key,
    this.onOpenCreateStory,
  });

  final VoidCallback? onOpenCreateStory;

  void _openCreate(BuildContext context) {
    if (onOpenCreateStory != null) {
      onOpenCreateStory!();
      return;
    }
    CommunityCreateStorySheet.show(context);
  }

  void _openViewer(
    BuildContext context,
    List<CommunityStoryAuthorGroup> groups,
    int index,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityStoryViewerScreen(
          groups: groups,
          initialGroupIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final storiesState = ref.watch(communityStoriesProvider);
    final activeUserId = ref.watch(communityRepositoryProvider).activeUserId;
    final groups = storiesState.groups;

    final selfIndex = groups.indexWhere(
      (g) =>
          (g.isSelf ||
              (activeUserId != null &&
                  activeUserId.isNotEmpty &&
                  g.author.id == activeUserId)) &&
          g.stories.isNotEmpty,
    );
    final CommunityStoryAuthorGroup? selfGroup =
        selfIndex >= 0 ? groups[selfIndex] : null;

    final otherEntries = <({int index, CommunityStoryAuthorGroup group})>[
      for (var i = 0; i < groups.length; i++)
        if (i != selfIndex && !groups[i].isSelf && groups[i].stories.isNotEmpty)
          (index: i, group: groups[i]),
    ];

    final children = <Widget>[
      _SelfStoryItem(
        tokens: tokens,
        selfGroup: selfGroup,
        onTapAvatar: () {
          if (selfGroup != null) {
            _openViewer(context, groups, selfIndex);
          } else {
            _openCreate(context);
          }
        },
        onTapAdd: () => _openCreate(context),
      ),
      for (final entry in otherEntries) ...[
        const SizedBox(width: 14),
        _StoryGroupItem(
          tokens: tokens,
          group: entry.group,
          onTap: () => _openViewer(context, groups, entry.index),
        ),
      ],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SelfStoryItem extends StatelessWidget {
  const _SelfStoryItem({
    required this.tokens,
    required this.selfGroup,
    required this.onTapAvatar,
    required this.onTapAdd,
  });

  final SamanHomePalette tokens;
  final CommunityStoryAuthorGroup? selfGroup;
  final VoidCallback onTapAvatar;
  final VoidCallback onTapAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasStory = selfGroup != null;
    final avatarUrl = selfGroup?.author.avatarUrl;
    final hasUnviewed = selfGroup?.hasUnviewed ?? false;

    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onTapAvatar,
                child: Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasStory
                          ? (hasUnviewed ? tokens.greenAccent : tokens.border)
                          : tokens.borderHigh,
                      width: hasStory && hasUnviewed ? 2.2 : 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: Container(
                      color: tokens.secondarySurface,
                      alignment: Alignment.center,
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.person_rounded,
                                color: tokens.textSecondary,
                                size: 26,
                              ),
                            )
                          : Icon(
                              hasStory
                                  ? Icons.person_rounded
                                  : Icons.auto_awesome_outlined,
                              color: hasStory
                                  ? tokens.textSecondary
                                  : tokens.greenAccent,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: GestureDetector(
                  onTap: onTapAdd,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: tokens.greenAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tokens.canvas,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapAvatar,
            child: Text(
              'Tin của bạn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryGroupItem extends StatelessWidget {
  const _StoryGroupItem({
    required this.tokens,
    required this.group,
    required this.onTap,
  });

  final SamanHomePalette tokens;
  final CommunityStoryAuthorGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final avatarUrl = group.author.avatarUrl;
    final initial =
        group.author.name.isNotEmpty ? group.author.name[0].toUpperCase() : 'S';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: group.hasUnviewed ? tokens.greenAccent : tokens.border,
                  width: group.hasUnviewed ? 2.2 : 1.5,
                ),
              ),
              child: ClipOval(
                child: Container(
                  color: tokens.secondarySurface,
                  alignment: Alignment.center,
                  child: avatarUrl != null && avatarUrl.isNotEmpty
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Text(
                            initial,
                            style: textTheme.titleMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        )
                      : Text(
                          initial,
                          style: textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.author.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: group.hasUnviewed
                    ? tokens.textPrimary
                    : tokens.textSecondary,
                fontSize: 11.5,
                fontWeight:
                    group.hasUnviewed ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
