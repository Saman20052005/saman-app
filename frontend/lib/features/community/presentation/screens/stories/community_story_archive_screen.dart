import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../config/app_translations.dart';
import '../../../../../config/routes.dart';
import '../../../domain/models/community_author.dart';
import '../../../domain/models/community_story.dart';
import '../../providers/community_social_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

class CommunityStoryArchiveScreen extends ConsumerStatefulWidget {
  const CommunityStoryArchiveScreen({super.key});

  @override
  ConsumerState<CommunityStoryArchiveScreen> createState() =>
      _CommunityStoryArchiveScreenState();
}

class _CommunityStoryArchiveScreenState
    extends ConsumerState<CommunityStoryArchiveScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(communityStoryArchiveProvider.notifier).loadArchive();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      ref.read(communityStoryArchiveProvider.notifier).loadMore();
    }
  }

  Future<void> _openArchivedStory(
    List<CommunityArchivedStory> items,
    int index,
  ) async {
    final slice = items.sublist(index);
    final first = slice.first;
    final group = CommunityStoryAuthorGroup(
      author: CommunityAuthor(
        id: first.userId.isNotEmpty ? first.userId : 'me',
        name: context.tr('community_stories_your_story'),
      ),
      isSelf: true,
      hasUnviewed: false,
      latestCreatedAt: first.createdAt,
      stories: slice,
    );
    await Navigator.of(context).pushNamed(
      AppRoutes.communityStoryViewer,
      arguments: <String, dynamic>{
        'groups': <CommunityStoryAuthorGroup>[group],
        'initialGroupIndex': 0,
      },
    );
    if (!mounted) return;
    await ref.read(communityStoryArchiveProvider.notifier).loadArchive();
  }

  Color _parseHexColor(String? hex, Color fallback) {
    final cleaned = (hex ?? '').replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  String _formatDateBadge(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final state = ref.watch(communityStoryArchiveProvider);
    final notifier = ref.read(communityStoryArchiveProvider.notifier);

    return Scaffold(
      backgroundColor: ig.canvas,
      appBar: AppBar(
        backgroundColor: ig.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          constraints: const BoxConstraints(
            minWidth: SamanIgTokens.minTouchTarget,
            minHeight: SamanIgTokens.minTouchTarget,
          ),
          icon: Icon(Icons.arrow_back_rounded, color: ig.textPrimary),
          tooltip: context.tr('community_settings_back'),
        ),
        titleSpacing: 4,
        title: Row(
          children: [
            Flexible(
              child: Text(
                context.tr('community_story_archive_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ig.displayTitle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (state.totalCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ig.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ig.border, width: 0.5),
                ),
                child: Text(
                  '${state.totalCount}',
                  style: ig.caption(
                    color: ig.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: ig.border),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ArchiveFilterBar(
              ig: ig,
              includeActive: state.includeActive,
              isLoading: state.isLoading,
              onToggleIncludeActive: (val) => notifier.toggleIncludeActive(val),
            ),
            Expanded(
              child: _buildBody(context, ig, state, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SamanIgTokens ig,
    CommunityStoryArchiveState state,
    CommunityStoryArchiveNotifier notifier,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: ig.primaryAction),
      );
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return RefreshIndicator(
        color: ig.primaryAction,
        backgroundColor: ig.surface,
        onRefresh: () => notifier.loadArchive(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 72),
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: ig.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(state.errorMessage!),
              textAlign: TextAlign.center,
              style: ig.username(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: () => notifier.loadArchive(),
                style: ig.primaryButtonStyle(),
                child: Text(context.tr('community_story_archive_retry')),
              ),
            ),
          ],
        ),
      );
    }

    if (state.items.isEmpty) {
      return RefreshIndicator(
        color: ig.primaryAction,
        backgroundColor: ig.surface,
        onRefresh: () => notifier.loadArchive(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 72),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ig.surface,
                  border: Border.all(color: ig.border, width: 0.5),
                ),
                child: Icon(
                  Icons.history_toggle_off_rounded,
                  size: 32,
                  color: ig.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('community_story_archive_empty_title'),
              textAlign: TextAlign.center,
              style: ig.displayTitle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('community_story_archive_empty_desc'),
              textAlign: TextAlign.center,
              style: ig.body(
                color: ig.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: ig.primaryAction,
      backgroundColor: ig.surface,
      onRefresh: () => notifier.loadArchive(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1.5,
              mainAxisSpacing: 1.5,
              childAspectRatio: 9 / 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final story = state.items[index];
                return _ArchivedStoryGridTile(
                  ig: ig,
                  story: story,
                  dateBadge: _formatDateBadge(story.createdAt),
                  backgroundColor: _parseHexColor(
                    story.backgroundColor,
                    ig.surfaceElevated,
                  ),
                  onTap: () => _openArchivedStory(state.items, index),
                );
              },
              childCount: state.items.length,
            ),
          ),
          if (state.isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ig.primaryAction,
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}

class _ArchiveFilterBar extends StatelessWidget {
  const _ArchiveFilterBar({
    required this.ig,
    required this.includeActive,
    required this.isLoading,
    required this.onToggleIncludeActive,
  });

  final SamanIgTokens ig;
  final bool includeActive;
  final bool isLoading;
  final ValueChanged<bool> onToggleIncludeActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ig.surface,
        border: Border(
          bottom: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 17,
            color: ig.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('community_story_archive_include_active'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ig.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ig.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: includeActive,
            onChanged: isLoading ? null : onToggleIncludeActive,
            activeColor: ig.primaryAction,
            activeTrackColor: ig.primaryAction.withOpacity(0.42),
            inactiveThumbColor: ig.textMuted,
            inactiveTrackColor: ig.surfaceElevated,
          ),
        ],
      ),
    );
  }
}

class _ArchivedStoryGridTile extends StatelessWidget {
  const _ArchivedStoryGridTile({
    required this.ig,
    required this.story,
    required this.dateBadge,
    required this.backgroundColor,
    required this.onTap,
  });

  final SamanIgTokens ig;
  final CommunityArchivedStory story;
  final String dateBadge;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = story.mediaType == 'photo' &&
        story.mediaUrl != null &&
        story.mediaUrl!.trim().isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: ig.surfaceElevated,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                story.mediaUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _TextFallbackTile(
                  ig: ig,
                  caption: story.caption,
                  backgroundColor: backgroundColor,
                  icon: Icons.broken_image_outlined,
                ),
              )
            else if (story.mediaType == 'video')
              _TextFallbackTile(
                ig: ig,
                caption: story.caption,
                backgroundColor: backgroundColor,
                icon: Icons.play_circle_outline_rounded,
              )
            else
              _TextFallbackTile(
                ig: ig,
                caption: story.caption,
                backgroundColor: backgroundColor,
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.32),
                        Colors.transparent,
                        Colors.black.withOpacity(0.45),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.62),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dateBadge,
                  style: ig.caption(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (!story.isExpired)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ig.primaryAction,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.tr('community_story_archive_active_badge'),
                    style: ig.caption(
                      color: ig.onPrimaryAction,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (story.mediaType == 'video')
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${story.viewCount}',
                      style: ig.caption(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
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
}

class _TextFallbackTile extends StatelessWidget {
  const _TextFallbackTile({
    required this.ig,
    required this.caption,
    required this.backgroundColor,
    this.icon,
  });

  final SamanIgTokens ig;
  final String caption;
  final Color backgroundColor;
  final IconData? icon;

  String _cleanCaption(String raw) {
    return raw
        .replaceAll('[SAMAN_WORKOUT]', '')
        .replaceAll('[SAMAN_MEAL]', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _cleanCaption(caption);
    final isLightBg = backgroundColor.computeLuminance() > 0.5;
    final fgColor = isLightBg ? ig.textPrimary : Colors.white;

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fgColor.withOpacity(0.85), size: 22),
            if (displayText.isNotEmpty) const SizedBox(height: 6),
          ],
          if (displayText.isNotEmpty)
            Text(
              displayText,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ig.caption(
                color: fgColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ).copyWith(height: 1.3),
            ),
        ],
      ),
    );
  }
}
