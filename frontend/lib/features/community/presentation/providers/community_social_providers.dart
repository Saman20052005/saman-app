import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/community_author.dart';
import '../../domain/models/community_settings.dart';
import '../../domain/models/community_story.dart';
import '../../domain/repositories/community_repository.dart';
import 'community_providers.dart';

class CommunitySettingsState {
  final bool isLoading;
  final bool isSaving;
  final CommunitySettings settings;
  final List<CommunityAuthor> blockedUsers;
  final List<CommunityAuthor> mutedUsers;
  final String? errorMessage;

  const CommunitySettingsState({
    this.isLoading = false,
    this.isSaving = false,
    this.settings = const CommunitySettings(),
    this.blockedUsers = const [],
    this.mutedUsers = const [],
    this.errorMessage,
  });

  CommunitySettingsState copyWith({
    bool? isLoading,
    bool? isSaving,
    CommunitySettings? settings,
    List<CommunityAuthor>? blockedUsers,
    List<CommunityAuthor>? mutedUsers,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CommunitySettingsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      settings: settings ?? this.settings,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      mutedUsers: mutedUsers ?? this.mutedUsers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CommunitySettingsNotifier extends StateNotifier<CommunitySettingsState> {
  final CommunityRepository _repository;
  int _generation = 0;

  CommunitySettingsNotifier(this._repository)
      : super(const CommunitySettingsState());

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunitySettingsState();
  }

  Future<void> loadSettings() async {
    final gen = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final settings = await _repository.getSettings();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(isLoading: false, settings: settings);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải cài đặt cộng đồng',
      );
    }
  }

  Future<CommunitySettings?> updateSettings({
    bool? isPrivateAccount,
    String? whoCanDm,
    String? whoCanComment,
    String? whoCanReplyStory,
    String? allowMentions,
    bool? hideLikeCounts,
    bool? showActivityStatus,
    bool? autoPromptShareWorkout,
    bool? autoPromptShareMeal,
    List<String>? mutedKeywords,
  }) async {
    final gen = _generation;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.updateSettings(
        isPrivateAccount: isPrivateAccount,
        whoCanDm: whoCanDm,
        whoCanComment: whoCanComment,
        whoCanReplyStory: whoCanReplyStory,
        allowMentions: allowMentions,
        hideLikeCounts: hideLikeCounts,
        showActivityStatus: showActivityStatus,
        autoPromptShareWorkout: autoPromptShareWorkout,
        autoPromptShareMeal: autoPromptShareMeal,
        mutedKeywords: mutedKeywords,
      );
      if (!mounted || gen != _generation) return null;
      state = state.copyWith(isSaving: false, settings: updated);
      return updated;
    } catch (e) {
      if (!mounted || gen != _generation) return null;
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Không thể cập nhật cài đặt',
      );
      return null;
    }
  }

  Future<void> loadBlockedUsers() async {
    final gen = _generation;
    try {
      final items = await _repository.getBlockedUsers();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(blockedUsers: items);
    } catch (_) {}
  }

  Future<bool> blockUser(String targetUserId) async {
    final gen = _generation;
    final blocked = await _repository.blockUser(targetUserId);
    if (!mounted || gen != _generation) return blocked;
    if (blocked) {
      await loadBlockedUsers();
    }
    return blocked;
  }

  Future<bool> unblockUser(String targetUserId) async {
    final gen = _generation;
    final stillBlocked = await _repository.unblockUser(targetUserId);
    if (!mounted || gen != _generation) return stillBlocked;
    state = state.copyWith(
      blockedUsers:
          state.blockedUsers.where((u) => u.id != targetUserId).toList(),
    );
    return stillBlocked;
  }

  Future<void> loadMutedUsers() async {
    final gen = _generation;
    try {
      final items = await _repository.getMutedUsers();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(mutedUsers: items);
    } catch (_) {}
  }

  Future<bool> muteUser(String targetUserId) async {
    final gen = _generation;
    final muted = await _repository.muteUser(targetUserId);
    if (!mounted || gen != _generation) return muted;
    if (muted) {
      await loadMutedUsers();
    }
    return muted;
  }

  Future<bool> unmuteUser(String targetUserId) async {
    final gen = _generation;
    final stillMuted = await _repository.unmuteUser(targetUserId);
    if (!mounted || gen != _generation) return stillMuted;
    state = state.copyWith(
      mutedUsers: state.mutedUsers.where((u) => u.id != targetUserId).toList(),
    );
    return stillMuted;
  }

  Future<CommunityReportReceipt> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) {
    return _repository.reportContent(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    );
  }
}

final communitySettingsProvider =
    StateNotifierProvider<CommunitySettingsNotifier, CommunitySettingsState>(
  (ref) {
    final repo = ref.watch(communityRepositoryProvider);
    return CommunitySettingsNotifier(repo);
  },
);

class CommunityStoriesState {
  final bool isLoading;
  final List<CommunityStoryAuthorGroup> groups;
  final String? errorMessage;

  const CommunityStoriesState({
    this.isLoading = false,
    this.groups = const [],
    this.errorMessage,
  });

  CommunityStoriesState copyWith({
    bool? isLoading,
    List<CommunityStoryAuthorGroup>? groups,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CommunityStoriesState(
      isLoading: isLoading ?? this.isLoading,
      groups: groups ?? this.groups,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CommunityStoriesNotifier extends StateNotifier<CommunityStoriesState> {
  final CommunityRepository _repository;
  final Set<String> _knownSelfUserIds = <String>{};
  int _generation = 0;

  CommunityStoriesNotifier(this._repository)
      : super(const CommunityStoriesState());

  void resetForUser(String? userId) {
    _generation++;
    _knownSelfUserIds.clear();
    state = const CommunityStoriesState();
  }

  List<CommunityStoryAuthorGroup> _normalizeGroups(
    List<CommunityStoryAuthorGroup> groups,
  ) {
    if (_knownSelfUserIds.isEmpty) return groups;
    final selfGroups = <CommunityStoryAuthorGroup>[];
    final otherGroups = <CommunityStoryAuthorGroup>[];
    for (final group in groups) {
      final matchesSelf = group.isSelf ||
          _knownSelfUserIds.contains(group.author.id) ||
          group.stories.any((s) => _knownSelfUserIds.contains(s.userId));
      if (matchesSelf) {
        selfGroups.add(group.isSelf ? group : group.copyWith(isSelf: true));
      } else {
        otherGroups.add(group);
      }
    }
    return [...selfGroups, ...otherGroups];
  }

  Future<void> loadStories() async {
    final gen = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final groups = await _repository.getStories();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        groups: _normalizeGroups(groups),
      );
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải tin 24h',
      );
    }
  }

  Future<CommunityStory?> createStory({
    required String mediaType,
    String? mediaUrl,
    String caption = '',
    String? backgroundColor,
    String privacy = 'public',
  }) async {
    final gen = _generation;
    final story = await _repository.createStory(
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      caption: caption,
      backgroundColor: backgroundColor,
      privacy: privacy,
    );
    if (!mounted || gen != _generation) return null;
    if (story.userId.isNotEmpty) {
      _knownSelfUserIds.add(story.userId);
    }
    await loadStories();
    if (!mounted || gen != _generation) return story;

    final currentGroups = List<CommunityStoryAuthorGroup>.from(state.groups);
    final hasCreatedStory = currentGroups.any(
      (g) => g.stories.any((s) => s.id == story.id),
    );
    if (!hasCreatedStory) {
      final selfIdx = currentGroups.indexWhere(
        (g) =>
            g.isSelf ||
            (story.userId.isNotEmpty && g.author.id == story.userId),
      );
      if (selfIdx >= 0) {
        final existing = currentGroups[selfIdx];
        final updatedGroup = existing.copyWith(
          isSelf: true,
          hasUnviewed: true,
          latestCreatedAt: story.createdAt,
          stories: [...existing.stories, story],
        );
        currentGroups.removeAt(selfIdx);
        currentGroups.insert(0, updatedGroup);
      } else {
        currentGroups.insert(
          0,
          CommunityStoryAuthorGroup(
            author: CommunityAuthor(
              id: story.userId,
              name: 'Tin của bạn',
            ),
            isSelf: true,
            hasUnviewed: !story.isViewed,
            latestCreatedAt: story.createdAt,
            stories: [story],
          ),
        );
      }
      state = state.copyWith(groups: currentGroups);
    } else {
      state = state.copyWith(groups: _normalizeGroups(currentGroups));
    }
    return story;
  }

  Future<void> markStoryViewed(String storyId) async {
    final gen = _generation;
    final viewCount = await _repository.markStoryViewed(storyId);
    if (!mounted || gen != _generation) return;
    final updatedGroups = state.groups.map((group) {
      final hasStory = group.stories.any((s) => s.id == storyId);
      if (!hasStory) return group;
      final nextStories = group.stories.map((s) {
        if (s.id != storyId) return s;
        return s.copyWith(isViewed: true, viewCount: viewCount);
      }).toList();
      return group.copyWith(
        stories: nextStories,
        hasUnviewed: nextStories.any((s) => !s.isViewed),
      );
    }).toList();
    state = state.copyWith(groups: updatedGroups);
  }

  Future<bool> deleteStory(String storyId) async {
    final gen = _generation;
    final deleted = await _repository.deleteStory(storyId);
    if (!mounted || gen != _generation) return deleted;
    if (deleted) {
      final nextGroups = state.groups
          .map((g) => g.copyWith(
                stories: g.stories.where((s) => s.id != storyId).toList(),
              ))
          .where((g) => g.stories.isNotEmpty)
          .toList();
      state = state.copyWith(groups: nextGroups);
    }
    return deleted;
  }
}

final communityStoriesProvider =
    StateNotifierProvider<CommunityStoriesNotifier, CommunityStoriesState>(
  (ref) {
    final repo = ref.watch(communityRepositoryProvider);
    return CommunityStoriesNotifier(repo);
  },
);

class CommunityStoryArchiveState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool includeActive;
  final List<CommunityArchivedStory> items;
  final String? nextCursor;
  final int totalCount;
  final String? errorMessage;

  const CommunityStoryArchiveState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.includeActive = false,
    this.items = const [],
    this.nextCursor,
    this.totalCount = 0,
    this.errorMessage,
  });

  CommunityStoryArchiveState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? includeActive,
    List<CommunityArchivedStory>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    int? totalCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CommunityStoryArchiveState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      includeActive: includeActive ?? this.includeActive,
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      totalCount: totalCount ?? this.totalCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CommunityStoryArchiveNotifier
    extends StateNotifier<CommunityStoryArchiveState> {
  final CommunityRepository _repository;
  int _generation = 0;

  CommunityStoryArchiveNotifier(this._repository)
      : super(const CommunityStoryArchiveState());

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunityStoryArchiveState();
  }

  Future<void> loadArchive({bool? includeActive}) async {
    final gen = _generation;
    final effectiveIncludeActive = includeActive ?? state.includeActive;
    state = state.copyWith(
      isLoading: true,
      includeActive: effectiveIncludeActive,
      clearError: true,
    );
    try {
      final page = await _repository.getArchivedStories(
        includeActive: effectiveIncludeActive,
        limit: 30,
      );
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        items: page.items,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        totalCount: page.totalCount,
      );
    } catch (_) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'community_story_archive_load_error',
      );
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || cursor.isEmpty || state.isLoading || state.isLoadingMore) {
      return;
    }
    final gen = _generation;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repository.getArchivedStories(
        includeActive: state.includeActive,
        limit: 30,
        cursor: cursor,
      );
      if (!mounted || gen != _generation) return;
      final existingIds = state.items.map((e) => e.id).toSet();
      final merged = [
        ...state.items,
        ...page.items.where((item) => !existingIds.contains(item.id)),
      ];
      state = state.copyWith(
        isLoadingMore: false,
        items: merged,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        totalCount: page.totalCount,
      );
    } catch (_) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> toggleIncludeActive(bool value) async {
    if (value == state.includeActive && !state.isLoading) return;
    await loadArchive(includeActive: value);
  }
}

final communityStoryArchiveProvider = StateNotifierProvider<
    CommunityStoryArchiveNotifier, CommunityStoryArchiveState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityStoryArchiveNotifier(repo);
});
