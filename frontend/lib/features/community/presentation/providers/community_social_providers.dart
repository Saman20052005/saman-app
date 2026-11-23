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
    bool? hideLikeCounts,
    bool? showActivityStatus,
    List<String>? mutedKeywords,
  }) async {
    final gen = _generation;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.updateSettings(
        isPrivateAccount: isPrivateAccount,
        whoCanDm: whoCanDm,
        whoCanComment: whoCanComment,
        hideLikeCounts: hideLikeCounts,
        showActivityStatus: showActivityStatus,
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
  int _generation = 0;

  CommunityStoriesNotifier(this._repository)
      : super(const CommunityStoriesState());

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunityStoriesState();
  }

  Future<void> loadStories() async {
    final gen = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final groups = await _repository.getStories();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(isLoading: false, groups: groups);
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
    await loadStories();
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
