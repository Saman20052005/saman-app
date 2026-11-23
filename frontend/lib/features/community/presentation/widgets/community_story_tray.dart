import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/community_story.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';
import '../screens/stories/community_story_viewer_screen.dart';
import '../tokens/saman_ig_tokens.dart';
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
    final ig = SamanIgTokens.of(context);
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
        ig: ig,
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
        const SizedBox(width: 12),
        _StoryGroupItem(
          ig: ig,
          group: entry.group,
          onTap: () => _openViewer(context, groups, entry.index),
        ),
      ],
    ];

    return Container(
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(color: ig.borderSubtle, width: 0.75),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _StoryAvatarRing extends StatelessWidget {
  const _StoryAvatarRing({
    required this.ig,
    required this.showGradientRing,
    required this.showViewedRing,
    required this.child,
  });

  final SamanIgTokens ig;
  final bool showGradientRing;
  final bool showViewedRing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BoxDecoration outerDecoration;
    if (showGradientRing) {
      outerDecoration = const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SamanIgTokens.storyGradient,
      );
    } else if (showViewedRing) {
      outerDecoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ig.border, width: 1.5),
      );
    } else {
      outerDecoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ig.border, width: 1.25),
      );
    }

    return Container(
      width: 68,
      height: 68,
      padding: EdgeInsets.all(showGradientRing ? 2.5 : 1.5),
      decoration: outerDecoration,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ig.canvas,
        ),
        child: ClipOval(child: child),
      ),
    );
  }
}

class _SelfStoryItem extends StatelessWidget {
  const _SelfStoryItem({
    required this.ig,
    required this.selfGroup,
    required this.onTapAvatar,
    required this.onTapAdd,
  });

  final SamanIgTokens ig;
  final CommunityStoryAuthorGroup? selfGroup;
  final VoidCallback onTapAvatar;
  final VoidCallback onTapAdd;

  @override
  Widget build(BuildContext context) {
    final hasStory = selfGroup != null;
    final avatarUrl = selfGroup?.author.avatarUrl;
    final hasUnviewed = selfGroup?.hasUnviewed ?? false;

    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onTapAvatar,
                child: _StoryAvatarRing(
                  ig: ig,
                  showGradientRing: hasStory && hasUnviewed,
                  showViewedRing: hasStory && !hasUnviewed,
                  child: Container(
                    color: ig.surfaceElevated,
                    alignment: Alignment.center,
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person_rounded,
                              color: ig.textSecondary,
                              size: 28,
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            color: ig.textSecondary,
                            size: 28,
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
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ig.primaryAction,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ig.canvas,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 15,
                      color: ig.onPrimaryAction,
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
              style: ig.caption(
                color: hasStory && hasUnviewed
                    ? ig.textPrimary
                    : ig.textSecondary,
                fontSize: 11.5,
                fontWeight:
                    hasStory && hasUnviewed ? FontWeight.w600 : FontWeight.w500,
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
    required this.ig,
    required this.group,
    required this.onTap,
  });

  final SamanIgTokens ig;
  final CommunityStoryAuthorGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = group.author.avatarUrl;
    final initial =
        group.author.name.isNotEmpty ? group.author.name[0].toUpperCase() : 'S';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StoryAvatarRing(
              ig: ig,
              showGradientRing: group.hasUnviewed,
              showViewedRing: !group.hasUnviewed,
              child: Container(
                color: ig.surfaceElevated,
                alignment: Alignment.center,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Text(
                          initial,
                          style: ig.username(
                            color: ig.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      )
                    : Text(
                        initial,
                        style: ig.username(
                          color: ig.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
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
              style: ig.caption(
                color: group.hasUnviewed ? ig.textPrimary : ig.textSecondary,
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
