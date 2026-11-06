import 'dart:math';
import 'community_composer_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/api_client.dart';
import '../../domain/models/community_comment.dart';
import '../../domain/models/community_discover_item.dart';
import '../../domain/models/community_notification.dart';
import '../../domain/models/community_post.dart';
import '../../domain/models/draft_post.dart';
import '../../domain/models/question_answer.dart';
import '../../domain/repositories/community_repository.dart';
import '../../data/datasources/community_fake_datasource.dart';
import '../../data/datasources/community_remote_datasource.dart';
import '../../data/repositories/community_repository_impl.dart';

final useRemoteCommunityProvider = StateProvider<bool>((ref) {
  return const bool.fromEnvironment('USE_REMOTE_COMMUNITY', defaultValue: false);
});

final communityFakeDatasourceProvider = Provider<CommunityFakeDatasource>((ref) {
  return CommunityFakeDatasource();
});

final communityRemoteDatasourceProvider = Provider<CommunityRemoteDatasource>((ref) {
  return CommunityRemoteDatasourceImpl(dio: ApiClient.dio);
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final useRemote = ref.watch(useRemoteCommunityProvider);
  if (useRemote) {
    final remoteDs = ref.watch(communityRemoteDatasourceProvider);
    return CommunityRepositoryImpl(
      remoteDatasource: remoteDs,
      useRemote: true,
    );
  }
  final fakeDs = ref.watch(communityFakeDatasourceProvider);
  return CommunityRepositoryImpl(
    fakeDatasource: fakeDs,
    useRemote: false,
  );
});

// Active Feed Filter
final communityFeedFilterProvider =
    StateProvider<CommunityFeedFilter>((ref) => CommunityFeedFilter.forYou);

// State for Community Feed Stream
class CommunityFeedState {
  final bool isLoading;
  final List<CommunityPost> posts;
  final String? errorMessage;
  final CommunityFeedFilter activeFilter;

  const CommunityFeedState({
    this.isLoading = false,
    this.posts = const [],
    this.errorMessage,
    this.activeFilter = CommunityFeedFilter.forYou,
  });

  CommunityFeedState copyWith({
    bool? isLoading,
    List<CommunityPost>? posts,
    String? errorMessage,
    CommunityFeedFilter? activeFilter,
  }) {
    return CommunityFeedState(
      isLoading: isLoading ?? this.isLoading,
      posts: posts ?? this.posts,
      errorMessage: errorMessage,
      activeFilter: activeFilter ?? this.activeFilter,
    );
  }
}

class CommunityFeedNotifier extends StateNotifier<CommunityFeedState> {
  final CommunityRepository _repository;
  final Ref? _ref;
  final Set<String> _pendingActions = <String>{};
  int _publicationRevision = 0;
  int _generation = 0;

  CommunityFeedNotifier(this._repository, [this._ref]) : super(const CommunityFeedState()) {
    loadPosts(CommunityFeedFilter.forYou);
  }

  int get generation => _generation;

  void resetForUser(String? userId) {
    _generation++;
    _pendingActions.clear();
    state = const CommunityFeedState();
  }

  Future<void> loadPosts(CommunityFeedFilter filter) async {
    final currentGen = _generation;
    final publicationRevision = _publicationRevision;
    state = state.copyWith(isLoading: true, activeFilter: filter);
    try {
      final posts = await _repository.getFeedPosts(filter: filter);
      if (!mounted || currentGen != _generation) return;
      if (publicationRevision != _publicationRevision) {
        state = state.copyWith(isLoading: false); return;
      }
      state = state.copyWith(isLoading: false, posts: posts);
    } catch (e) {
      if (!mounted || currentGen != _generation) return;
      if (publicationRevision != _publicationRevision) {
        state = state.copyWith(isLoading: false); return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải bảng tin cộng đồng',
      );
    }
  }

  Future<void> setFilter(CommunityFeedFilter filter) async {
    if (state.activeFilter == filter && !state.isLoading) return;
    await loadPosts(filter);
  }

  void updatePostInteractions({
    required String postId,
    bool? isLiked,
    int? likeCount,
    int? commentCount,
    bool? isBookmarked,
    int? answerCount,
  }) {
    final index = state.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final p = state.posts[index];
    final updated = p.copyWith(
      qaInfo: answerCount == null ? p.qaInfo : p.qaInfo?.withAnswerCount(answerCount),
      isLiked: isLiked ?? p.isLiked,
      likeCount: likeCount ?? p.likeCount,
      commentCount: commentCount ?? p.commentCount,
      isBookmarked: isBookmarked ?? p.isBookmarked,
    );
    final next = List<CommunityPost>.from(state.posts);
    next[index] = updated;
    state = state.copyWith(posts: next);
  }

  void acceptPublished(CommunityPost post) {
    _publicationRevision++;
    final filter = post.type == CommunityPostType.qa ? CommunityFeedFilter.qa : CommunityFeedFilter.forYou;
    final existing = state.activeFilter == filter ? state.posts : <CommunityPost>[];
    state = CommunityFeedState(activeFilter: filter,
        posts: {post.id: post, for (final p in existing) if (p.id != post.id) p.id: p}.values.toList());
  }

  Future<bool> deletePost(String postId) async {
    final lockKey = 'delete_$postId';
    if (_pendingActions.contains(lockKey)) return false;
    _pendingActions.add(lockKey);
    try {
      final success = await _repository.deletePost(postId);
      if (success) {
        state = state.copyWith(
          posts: state.posts.where((p) => p.id != postId).toList(),
        );
        return true;
      }
      return false;
    } finally {
      _pendingActions.remove(lockKey);
    }
  }

  void removeInaccessibleQuestion(String id) {
    state = state.copyWith(posts: state.posts.where((p) => p.id != id).toList());
  }

  Future<void> toggleLike(String postId) async {
    final lockKey = 'like_$postId';
    if (_pendingActions.contains(lockKey)) return;
    _pendingActions.add(lockKey);

    final originalPosts = state.posts;
    final index = originalPosts.indexWhere((p) => p.id == postId);
    if (index == -1) {
      _pendingActions.remove(lockKey);
      return;
    }

    final currentPost = originalPosts[index];
    final optimisticIsLiked = !currentPost.isLiked;
    final optimisticCount = optimisticIsLiked
        ? currentPost.likeCount + 1
        : (currentPost.likeCount > 0 ? currentPost.likeCount - 1 : 0);

    // 1. Optimistic update
    final optimisticPosts = List<CommunityPost>.from(originalPosts);
    optimisticPosts[index] = currentPost.copyWith(
      isLiked: optimisticIsLiked,
      likeCount: optimisticCount,
    );
    state = state.copyWith(posts: optimisticPosts);

    // Sync to open detail if any
    _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
      isLiked: optimisticIsLiked,
      likeCount: optimisticCount,
    );

    final currentGen = _generation;
    try {
      final actualIsLiked = await _repository.toggleLike(postId);
      if (!mounted || currentGen != _generation) return;
      if (actualIsLiked != optimisticIsLiked) {
        final reconciledPosts = List<CommunityPost>.from(state.posts);
        final rIdx = reconciledPosts.indexWhere((p) => p.id == postId);
        if (rIdx != -1) {
          final p = reconciledPosts[rIdx];
          final rCount = actualIsLiked ? p.likeCount + 1 : (p.likeCount > 0 ? p.likeCount - 1 : 0);
          reconciledPosts[rIdx] = p.copyWith(isLiked: actualIsLiked, likeCount: rCount);
          state = state.copyWith(posts: reconciledPosts);
        }
      }
    } on IndeterminateMutationException {
      // Indeterminate error: Server may have committed; do not roll back.
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback on definitive failure
      if (mounted && currentGen == _generation) {
        state = state.copyWith(posts: originalPosts);
        _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
          isLiked: currentPost.isLiked,
          likeCount: currentPost.likeCount,
        );
      }
      rethrow;
    } finally {
      _pendingActions.remove(lockKey);
    }
  }

  Future<void> toggleBookmark(String postId) async {
    final lockKey = 'save_$postId';
    if (_pendingActions.contains(lockKey)) return;
    _pendingActions.add(lockKey);

    final originalPosts = state.posts;
    final index = originalPosts.indexWhere((p) => p.id == postId);
    if (index == -1) {
      _pendingActions.remove(lockKey);
      return;
    }

    final currentPost = originalPosts[index];
    final optimisticIsBookmarked = !currentPost.isBookmarked;

    // 1. Optimistic update
    final optimisticPosts = List<CommunityPost>.from(originalPosts);
    optimisticPosts[index] = currentPost.copyWith(isBookmarked: optimisticIsBookmarked);
    state = state.copyWith(posts: optimisticPosts);

    _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
      isBookmarked: optimisticIsBookmarked,
    );

    final currentGen = _generation;
    try {
      final actualIsBookmarked = await _repository.toggleBookmark(postId);
      if (!mounted || currentGen != _generation) return;
      if (actualIsBookmarked != optimisticIsBookmarked) {
        final reconciledPosts = List<CommunityPost>.from(state.posts);
        final rIdx = reconciledPosts.indexWhere((p) => p.id == postId);
        if (rIdx != -1) {
          reconciledPosts[rIdx] = reconciledPosts[rIdx].copyWith(isBookmarked: actualIsBookmarked);
          state = state.copyWith(posts: reconciledPosts);
        }
      }
      // Sync to saved screen
      _ref?.read(communitySavedProvider.notifier).syncBookmark(
        postId: postId,
        isBookmarked: actualIsBookmarked,
        post: optimisticPosts[index],
      );
    } on IndeterminateMutationException {
      // Indeterminate error: retain optimistic bookmark until confirmed
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback on definitive failure
      if (mounted && currentGen == _generation) {
        state = state.copyWith(posts: originalPosts);
        _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
          isBookmarked: currentPost.isBookmarked,
        );
      }
      rethrow;
    } finally {
      _pendingActions.remove(lockKey);
    }
  }

  Future<void> refresh() async {
    await loadPosts(state.activeFilter);
  }

  void updateAuthorFollow({
    required String authorId,
    required bool isFollowing,
    int? followerCount,
  }) {
    if (state.activeFilter == CommunityFeedFilter.following && !isFollowing) {
      final remaining = state.posts.where((p) => p.author.id != authorId).toList();
      state = state.copyWith(posts: remaining);
      return;
    }

    bool modified = false;
    final next = state.posts.map((p) {
      if (p.author.id == authorId) {
        modified = true;
        final newCount = followerCount ??
            (isFollowing
                ? p.author.followerCount + 1
                : (p.author.followerCount > 0 ? p.author.followerCount - 1 : 0));
        return p.copyWith(
          author: p.author.copyWith(
            isFollowing: isFollowing,
            followerCount: newCount,
          ),
        );
      }
      return p;
    }).toList();

    if (modified) {
      state = state.copyWith(posts: next);
    }
  }

  Future<void> toggleFollowAuthor(String authorId) async {
    final lockKey = 'follow_$authorId';
    if (_pendingActions.contains(lockKey)) return;
    _pendingActions.add(lockKey);

    final currentGen = _generation;
    final matchingPost = state.posts.cast<CommunityPost?>().firstWhere(
          (p) => p?.author.id == authorId,
          orElse: () => null,
        );
    final currentlyFollowing = matchingPost?.author.isFollowing ?? false;
    final optimisticFollowing = !currentlyFollowing;

    updateAuthorFollow(authorId: authorId, isFollowing: optimisticFollowing);

    try {
      final canonicalFollow = await _repository.toggleFollow(authorId);
      if (!mounted || currentGen != _generation) return;
      if (canonicalFollow != optimisticFollowing) {
        updateAuthorFollow(authorId: authorId, isFollowing: canonicalFollow);
      }
    } catch (e) {
      if (!mounted || currentGen != _generation) return;
      updateAuthorFollow(authorId: authorId, isFollowing: currentlyFollowing);
    } finally {
      _pendingActions.remove(lockKey);
    }
  }
}

final communityFeedProvider =
    StateNotifierProvider<CommunityFeedNotifier, CommunityFeedState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityFeedNotifier(repo, ref);
});

// State for Community Discover Screen (R04)
class CommunityDiscoverState {
  final bool isLoading;
  final CommunityDiscoverData data;
  final String activeTopic;
  final String searchQuery;
  final String? errorMessage;

  const CommunityDiscoverState({
    this.isLoading = false,
    this.data = const CommunityDiscoverData(),
    this.activeTopic = 'all',
    this.searchQuery = '',
    this.errorMessage,
  });

  CommunityDiscoverState copyWith({
    bool? isLoading,
    CommunityDiscoverData? data,
    String? activeTopic,
    String? searchQuery,
    String? errorMessage,
  }) {
    return CommunityDiscoverState(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      activeTopic: activeTopic ?? this.activeTopic,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }
}

class CommunityDiscoverNotifier extends StateNotifier<CommunityDiscoverState> {
  final CommunityRepository _repository;
  final Ref? _ref;

  CommunityDiscoverNotifier(this._repository, [this._ref])
      : super(const CommunityDiscoverState()) {
    loadDiscover();
  }

  Future<void> loadDiscover({String topic = 'all'}) async {
    state = state.copyWith(isLoading: true, activeTopic: topic);
    try {
      final data = await _repository.getDiscoverData(topic: topic);
      if (!mounted) return;
      state = state.copyWith(isLoading: false, data: data);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải nội dung khám phá',
      );
    }
  }

  Future<void> setTopic(String topic) async {
    if (state.activeTopic == topic && !state.isLoading) return;
    await loadDiscover(topic: topic);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> toggleFollow(String authorId) async {
    final newFollow = await _repository.toggleFollow(authorId);
    if (!mounted) return;
    final updatedCreators = state.data.recommendedCreators.map((c) {
      if (c.id == authorId) {
        return c.copyWith(isFollowing: newFollow);
      }
      return c;
    }).toList();
    final updatedData = CommunityDiscoverData(
      activeTopic: state.data.activeTopic,
      topicChips: state.data.topicChips,
      gridItems: state.data.gridItems,
      trendingTopics: state.data.trendingTopics,
      recommendedCreators: updatedCreators,
    );
    state = state.copyWith(data: updatedData);
    _ref?.read(communityFeedProvider.notifier).updateAuthorFollow(
      authorId: authorId,
      isFollowing: newFollow,
    );
  }
}

final communityDiscoverProvider = StateNotifierProvider<
    CommunityDiscoverNotifier, CommunityDiscoverState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityDiscoverNotifier(repo, ref);
});

// State for Post Detail Screen (R05)
class CommunityPostDetailState {
  final String draft;
  final String? commentErrorKey;
  final String? commentsCursor;
  final bool isLoadingComments;
  final bool hasPendingSubmission;
  final bool isLoading;
  final bool isSubmitting;
  final CommunityPost? post;
  final String? errorMessage;
  final String? replyToAuthorName;
  final String? replyToCommentId;

  const CommunityPostDetailState({
    this.draft = '',
    this.commentErrorKey,
    this.commentsCursor,
    this.isLoadingComments = false,
    this.hasPendingSubmission = false,
    this.isLoading = false,
    this.isSubmitting = false,
    this.post,
    this.errorMessage,
    this.replyToAuthorName,
    this.replyToCommentId,
  });

  CommunityPostDetailState copyWith({
    String? draft,
    String? commentErrorKey,
    bool clearCommentError = false,
    String? commentsCursor,
    bool clearCommentsCursor = false,
    bool? isLoadingComments,
    bool? hasPendingSubmission,
    bool clearPost = false,
    bool? isLoading,
    bool? isSubmitting,
    CommunityPost? post,
    String? errorMessage,
    String? replyToAuthorName,
    String? replyToCommentId,
    bool clearReply = false,
  }) {
    return CommunityPostDetailState(
      draft: draft ?? this.draft,
      commentErrorKey: clearCommentError ? null : (commentErrorKey ?? this.commentErrorKey),
      commentsCursor: clearCommentsCursor ? null : (commentsCursor ?? this.commentsCursor),
      isLoadingComments: isLoadingComments ?? this.isLoadingComments,
      hasPendingSubmission: hasPendingSubmission ?? this.hasPendingSubmission,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      post: clearPost ? null : (post ?? this.post),
      errorMessage: errorMessage,
      replyToAuthorName:
          clearReply ? null : (replyToAuthorName ?? this.replyToAuthorName),
      replyToCommentId:
          clearReply ? null : (replyToCommentId ?? this.replyToCommentId),
    );
  }
}

class CommunityPostDetailNotifier
    extends StateNotifier<CommunityPostDetailState> {
  final CommunityRepository _repository;
  final String _postId;
  final Ref? _ref;
  final Set<String> _pendingActions = <String>{};
  int _generation = 0;
  int _commentRevision = 0;
  String? _requestKey;
  String? _pendingContent;
  String? _pendingParent;
  String? _pendingReplyName;
  final Map<String, CommunityComment> _comments = {};

  CommunityPostDetailNotifier(this._repository, this._postId, [this._ref])
      : super(const CommunityPostDetailState()) {
    loadPost();
  }

  int get generation => _generation;

  void resetForUser(String? userId) {
    _generation++;
    _pendingActions.clear();
    _requestKey = null;
    _pendingContent = null;
    _pendingParent = null;
    _pendingReplyName = null;
    _comments.clear();
    state = const CommunityPostDetailState();
  }

  Future<void> loadPost() async {
    final currentGen = _generation;
    state = state.copyWith(isLoading: true);
    try {
      final post = await _repository.getPostDetail(_postId);
      if (!mounted || currentGen != _generation) return;
      state = state.copyWith(isLoading: false, post: post);
      await loadComments();
    } catch (e) {
      if (!mounted || currentGen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải chi tiết bài viết',
      );
    }
  }

  void updateDraft(String value) {
    if (!state.hasPendingSubmission) state = state.copyWith(draft: value, clearCommentError: true);
  }

  List<CommunityComment> _orderedComments(Iterable<CommunityComment> values) {
    final items = values.toList();
    final positions = {for (var i = 0; i < items.length; i++) items[i].id: i};
    items.sort((a, b) {
      if (a.createdAt == null || b.createdAt == null) return positions[a.id]!.compareTo(positions[b.id]!);
      final time = a.createdAt!.compareTo(b.createdAt!);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return items;
  }

  List<CommunityComment> _threadedComments() {
    final roots = _orderedComments(_comments.values.where((c) => c.parentCommentId == null));
    return roots.map((root) => root.copyWith(replies: _orderedComments({
      for (final reply in root.replies) reply.id: reply,
      for (final reply in _comments.values.where((c) => c.parentCommentId == root.id)) reply.id: reply,
    }.values))).toList();
  }

  void _syncCommentCount(int count) {
    _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
        postId: _postId, commentCount: count);
  }

  Future<void> loadComments({bool more = false}) async {
    if (state.post == null || state.isLoadingComments || (more && state.commentsCursor == null)) return;
    final gen = _generation;
    final revision = _commentRevision;
    state = state.copyWith(isLoadingComments: true);
    try {
      final page = await _repository.getComments(_postId, cursor: more ? state.commentsCursor : null);
      if (!mounted || gen != _generation) return;
      if (revision != _commentRevision) {
        state = state.copyWith(isLoadingComments: false);
        return;
      }
      if (!more) _comments.clear();
      for (final c in page.items) { _comments[c.id] = c; }
      state = state.copyWith(isLoadingComments: false,
          clearCommentError: state.commentErrorKey == 'community_comments_load_error',
          commentsCursor: page.nextCursor, clearCommentsCursor: page.nextCursor == null,
          post: state.post!.copyWith(comments: _threadedComments(), commentCount: page.commentCount));
      _syncCommentCount(page.commentCount);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      final forbidden = e is DioException && [401,403,404].contains(e.response?.statusCode);
      state = state.copyWith(isLoadingComments: false, clearPost: forbidden,
          commentErrorKey: forbidden ? 'community_comment_access' : 'community_comments_load_error');
    }
  }

  void updateInteraction({bool? isLiked, int? likeCount, bool? isBookmarked}) {
    if (state.post == null) return;
    final p = state.post!;
    state = state.copyWith(
      post: p.copyWith(
        isLiked: isLiked ?? p.isLiked,
        likeCount: likeCount ?? p.likeCount,
        isBookmarked: isBookmarked ?? p.isBookmarked,
      ),
    );
  }

  void updateAuthorFollow({
    required String authorId,
    required bool isFollowing,
    int? followerCount,
  }) {
    if (state.post == null) return;
    final p = state.post!;
    if (p.author.id == authorId) {
      final newCount = followerCount ??
          (isFollowing
              ? p.author.followerCount + 1
              : (p.author.followerCount > 0 ? p.author.followerCount - 1 : 0));
      state = state.copyWith(
        post: p.copyWith(
          author: p.author.copyWith(
            isFollowing: isFollowing,
            followerCount: newCount,
          ),
        ),
      );
    }
  }

  Future<void> toggleLike() async {
    if (state.post == null) return;
    final lockKey = 'like_$_postId';
    if (_pendingActions.contains(lockKey)) return;
    _pendingActions.add(lockKey);

    final originalPost = state.post!;
    final optimisticIsLiked = !originalPost.isLiked;
    final optimisticCount = optimisticIsLiked
        ? originalPost.likeCount + 1
        : (originalPost.likeCount > 0 ? originalPost.likeCount - 1 : 0);

    // 1. Optimistic update
    state = state.copyWith(
      post: originalPost.copyWith(
        isLiked: optimisticIsLiked,
        likeCount: optimisticCount,
      ),
    );
    _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
      postId: _postId,
      isLiked: optimisticIsLiked,
      likeCount: optimisticCount,
    );

    final currentGen = _generation;
    try {
      final actualIsLiked = await _repository.toggleLike(_postId);
      if (!mounted || currentGen != _generation) return;
      if (actualIsLiked != optimisticIsLiked && state.post != null) {
        final p = state.post!;
        final rCount = actualIsLiked ? p.likeCount + 1 : (p.likeCount > 0 ? p.likeCount - 1 : 0);
        state = state.copyWith(post: p.copyWith(isLiked: actualIsLiked, likeCount: rCount));
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: _postId,
          isLiked: actualIsLiked,
          likeCount: rCount,
        );
      }
    } on IndeterminateMutationException {
      // Indeterminate: keep optimistic
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback on definitive failure
      if (mounted && currentGen == _generation) {
        state = state.copyWith(post: originalPost);
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: _postId,
          isLiked: originalPost.isLiked,
          likeCount: originalPost.likeCount,
        );
      }
      rethrow;
    } finally {
      _pendingActions.remove(lockKey);
    }
  }

  Future<void> toggleBookmark() async {
    if (state.post == null) return;
    final lockKey = 'save_$_postId';
    if (_pendingActions.contains(lockKey)) return;
    _pendingActions.add(lockKey);

    final originalPost = state.post!;
    final optimisticIsBookmarked = !originalPost.isBookmarked;

    // 1. Optimistic update
    state = state.copyWith(
      post: originalPost.copyWith(isBookmarked: optimisticIsBookmarked),
    );
    _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
      postId: _postId,
      isBookmarked: optimisticIsBookmarked,
    );

    final currentGen = _generation;
    try {
      final actualIsBookmarked = await _repository.toggleBookmark(_postId);
      if (!mounted || currentGen != _generation) return;
      if (actualIsBookmarked != optimisticIsBookmarked && state.post != null) {
        state = state.copyWith(post: state.post!.copyWith(isBookmarked: actualIsBookmarked));
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: _postId,
          isBookmarked: actualIsBookmarked,
        );
      }
      _ref?.read(communitySavedProvider.notifier).syncBookmark(
        postId: _postId,
        isBookmarked: actualIsBookmarked,
        post: state.post,
      );
    } on IndeterminateMutationException {
      // Indeterminate: keep optimistic
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback on definitive failure
      if (mounted && currentGen == _generation) {
        state = state.copyWith(post: originalPost);
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: _postId,
          isBookmarked: originalPost.isBookmarked,
        );
      }
      rethrow;
    } finally {
      _pendingActions.remove(lockKey);
    }
  }

  void setReplyTarget(String authorName, String commentId) {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(
      replyToAuthorName: _comments[commentId]?.author.name ?? authorName,
      replyToCommentId: commentId,
    );
  }

  void cancelReply() {
    if (state.hasPendingSubmission) return;
    state = state.copyWith(clearReply: true);
  }

  Future<void> retryComment() async {
    if (state.commentErrorKey == 'community_comments_load_error') {
      await loadComments(more: state.commentsCursor != null);
    } else {
      await submitComment(state.draft);
    }
  }

  Future<bool> submitComment(String text) async {
    if (state.post == null || state.isSubmitting) return false;
    final content = (_pendingContent ?? text).trim();
    if (content.isEmpty || content.length > 2000) {
      state = state.copyWith(commentErrorKey: 'community_comment_invalid');
      return false;
    }
    final gen = _generation;
    final recovering = _requestKey != null;
    if (_requestKey == null) {
      final random = Random.secure();
      _requestKey = List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    }
    _pendingContent ??= content;
    _pendingParent ??= state.replyToCommentId;
    _pendingReplyName ??= state.replyToAuthorName;
    final parent = _pendingParent;
    state = state.copyWith(isSubmitting: true, hasPendingSubmission: true, draft: content, clearCommentError: true);
    try {
      final canonical = await _repository.addComment(postId: _postId,
          content: _pendingContent!, parentCommentId: parent,
          replyToAuthorName: _pendingReplyName, requestKey: _requestKey);
      if (!mounted || gen != _generation) return false;
      _commentRevision++;
      // Fake data already contains nested replies; remote pages are a flat stream.
      if (_comments.isEmpty) {
        for (final c in state.post!.comments) { _comments[c.id] = c; }
      }
      _comments[canonical.id] = canonical;
      if (parent != null && canonical.parentCommentId == null && _comments.containsKey(parent)) {
        final root = _comments[parent]!;
        _comments.remove(canonical.id);
        _comments[parent] = root.copyWith(replies: {
          for (final c in root.replies) c.id: c, canonical.id: canonical,
        }.values.toList());
      }
      final repo = _repository;
      final count = repo is CommunityRepositoryImpl && repo.isRemote
          ? repo.commentCountFor(_postId)! : state.post!.commentCount + 1;
      state = state.copyWith(isSubmitting: false, hasPendingSubmission: false, clearCommentError: true,
          draft: '', clearReply: true,
          post: state.post!.copyWith(comments: _threadedComments(), commentCount: count));
      _syncCommentCount(count);
      _requestKey = null;
      _pendingContent = null;
      _pendingParent = null;
      _pendingReplyName = null;
      return true;
    } catch (e) {
      if (!mounted || gen != _generation) return false;
      final status = e is DioException ? e.response?.statusCode : null;
      // A later 4xx cannot disprove a previous unknown commit. A 404 can also
      // follow an insert when access is revoked during the server recheck.
      final definitive = !recovering && status != null && status >= 400 && status < 500 && status != 408 && status != 404;
      if (definitive) {
        _requestKey = null;
        _pendingContent = null;
        _pendingParent = null;
        _pendingReplyName = null;
      }
      state = state.copyWith(isSubmitting: false, hasPendingSubmission: !definitive,
          clearPost: [401,403,404].contains(status),
          commentErrorKey: [401,403,404].contains(status) ? 'community_comment_access'
              : definitive ? 'community_comment_rejected' : 'community_comment_unconfirmed');
      return false;
    }
  }
}

final communityPostDetailProvider = StateNotifierProvider.family<
    CommunityPostDetailNotifier, CommunityPostDetailState, String>(
  (ref, postId) {
    final repo = ref.watch(communityRepositoryProvider);
    return CommunityPostDetailNotifier(repo, postId, ref);
  },
);

// JCOM-04: Saved Posts
class CommunitySavedState {
  final bool isLoading;
  final List<CommunityPost> posts;
  const CommunitySavedState({this.isLoading = false, this.posts = const []});
  CommunitySavedState copyWith({bool? isLoading, List<CommunityPost>? posts}) {
    return CommunitySavedState(
      isLoading: isLoading ?? this.isLoading,
      posts: posts ?? this.posts,
    );
  }
}

class CommunitySavedNotifier extends StateNotifier<CommunitySavedState> {
  final CommunityRepository _repository;
  final Ref? _ref;
  int _generation = 0;

  CommunitySavedNotifier(this._repository, [this._ref])
      : super(const CommunitySavedState()) {
    loadSavedPosts();
  }

  int get generation => _generation;

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunitySavedState();
  }

  Future<void> loadSavedPosts() async {
    final currentGen = _generation;
    state = state.copyWith(isLoading: true);
    try {
      final posts = await _repository.getSavedPosts();
      if (!mounted || currentGen != _generation) return;
      state = state.copyWith(isLoading: false, posts: posts);
    } catch (e) {
      if (!mounted || currentGen != _generation) return;
      state = state.copyWith(isLoading: false, posts: []);
    }
  }

  void syncBookmark({
    required String postId,
    required bool isBookmarked,
    CommunityPost? post,
  }) {
    if (isBookmarked) {
      if (post != null && !state.posts.any((p) => p.id == postId)) {
        state = state.copyWith(posts: [post.copyWith(isBookmarked: true), ...state.posts]);
      }
    } else {
      state = state.copyWith(posts: state.posts.where((p) => p.id != postId).toList());
    }
  }

  Future<void> unbookmark(String postId) async {
    final originalPosts = state.posts;
    // 1. Optimistic removal
    state = state.copyWith(
      posts: state.posts.where((p) => p.id != postId).toList(),
    );
    // Sync to feed & detail
    _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
      postId: postId,
      isBookmarked: false,
    );
    _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
      isBookmarked: false,
    );

    final currentGen = _generation;
    try {
      await _repository.toggleBookmark(postId);
    } on IndeterminateMutationException {
      // Indeterminate: keep optimistic removal
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback on definitive failure
      if (mounted && currentGen == _generation) {
        state = state.copyWith(posts: originalPosts);
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: postId,
          isBookmarked: true,
        );
        _ref?.read(communityPostDetailProvider(postId).notifier).updateInteraction(
          isBookmarked: true,
        );
      }
      rethrow;
    }
  }

  Future<void> restore(CommunityPost post) async {
    final originalPosts = state.posts;
    // 1. Optimistic restore
    state = state.copyWith(posts: [post.copyWith(isBookmarked: true), ...state.posts]);
    _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
      postId: post.id,
      isBookmarked: true,
    );
    _ref?.read(communityPostDetailProvider(post.id).notifier).updateInteraction(
      isBookmarked: true,
    );

    final currentGen = _generation;
    try {
      await _repository.toggleBookmark(post.id);
    } on IndeterminateMutationException {
      // Indeterminate: keep optimistic restore
      if (!mounted || currentGen != _generation) return;
    } catch (e) {
      // 2. Rollback
      if (mounted && currentGen == _generation) {
        state = state.copyWith(posts: originalPosts);
        _ref?.read(communityFeedProvider.notifier).updatePostInteractions(
          postId: post.id,
          isBookmarked: false,
        );
        _ref?.read(communityPostDetailProvider(post.id).notifier).updateInteraction(
          isBookmarked: false,
        );
      }
      rethrow;
    }
  }
}

final communityIdentityRevisionProvider = StateProvider<int>((ref) => 0);

void resetCommunityStateForUser(WidgetRef ref, [String? userId]) {
  final repo = ref.read(communityRepositoryProvider);
  if (repo is CommunityRepositoryImpl) {
    repo.resetForUser(userId);
  }
  ref.read(communityIdentityRevisionProvider.notifier).state++;
  ref.read(communityFeedProvider.notifier).resetForUser(userId);
  ref.read(communitySavedProvider.notifier).resetForUser(userId);
  ref.invalidate(communityPostDetailProvider);
  ref.invalidate(communityQuestionDetailProvider);
  ref.invalidate(communityComposerProvider);
  ref.invalidate(communityQuestionComposerProvider);
}

void resetCommunityStateInContainer(ProviderContainer container, [String? userId]) {
  final repo = container.read(communityRepositoryProvider);
  if (repo is CommunityRepositoryImpl) {
    repo.resetForUser(userId);
  }
  container.read(communityIdentityRevisionProvider.notifier).state++;
  container.read(communityFeedProvider.notifier).resetForUser(userId);
  container.read(communitySavedProvider.notifier).resetForUser(userId);
  container.invalidate(communityPostDetailProvider);
  container.invalidate(communityQuestionDetailProvider);
  container.invalidate(communityComposerProvider);
  container.invalidate(communityQuestionComposerProvider);
}

final communitySavedProvider =
    StateNotifierProvider<CommunitySavedNotifier, CommunitySavedState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunitySavedNotifier(repo, ref);
});

// JCOM-04: Notifications
class CommunityNotificationsState {
  final bool isLoading;
  final List<CommunityNotification> allNotifications;
  final String activeFilter; // 'all', 'interactions', 'system'

  const CommunityNotificationsState({
    this.isLoading = false,
    this.allNotifications = const [],
    this.activeFilter = 'all',
  });

  int get unreadCount => allNotifications.where((n) => n.isUnread).length;

  List<CommunityNotification> get filteredNotifications {
    if (activeFilter == 'interactions') {
      return allNotifications
          .where((n) =>
              n.type == CommunityNotificationType.like ||
              n.type == CommunityNotificationType.comment ||
              n.type == CommunityNotificationType.follow)
          .toList();
    } else if (activeFilter == 'system') {
      return allNotifications
          .where((n) => n.type == CommunityNotificationType.system)
          .toList();
    }
    return allNotifications;
  }

  CommunityNotificationsState copyWith({
    bool? isLoading,
    List<CommunityNotification>? allNotifications,
    String? activeFilter,
  }) {
    return CommunityNotificationsState(
      isLoading: isLoading ?? this.isLoading,
      allNotifications: allNotifications ?? this.allNotifications,
      activeFilter: activeFilter ?? this.activeFilter,
    );
  }
}

class CommunityNotificationsNotifier
    extends StateNotifier<CommunityNotificationsState> {
  final CommunityRepository _repository;
  CommunityNotificationsNotifier(this._repository)
      : super(const CommunityNotificationsState()) {
    loadNotifications();
  }
  Future<void> loadNotifications() async {
    state = state.copyWith(isLoading: true);
    final notifs = await _repository.getNotifications();
    if (!mounted) return;
    state = state.copyWith(isLoading: false, allNotifications: notifs);
  }
  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }
  Future<void> markAsRead(String id) async {
    await _repository.markNotificationRead(id);
    if (!mounted) return;
    final updated = state.allNotifications.map((n) {
      if (n.id == id) return n.copyWith(isUnread: false);
      return n;
    }).toList();
    state = state.copyWith(allNotifications: updated);
  }
  Future<void> markAllAsRead() async {
    for (final n in state.allNotifications) {
      if (n.isUnread) {
        await _repository.markNotificationRead(n.id);
      }
    }
    if (!mounted) return;
    final updated = state.allNotifications
        .map((n) => n.copyWith(isUnread: false))
        .toList();
    state = state.copyWith(allNotifications: updated);
  }
}

final communityNotificationsProvider = StateNotifierProvider<
    CommunityNotificationsNotifier, CommunityNotificationsState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityNotificationsNotifier(repo);
});

// JCOM-04: Drafts
class CommunityDraftsState {
  final bool isLoading;
  final List<DraftPost> drafts;
  const CommunityDraftsState({this.isLoading = false, this.drafts = const []});
  CommunityDraftsState copyWith({bool? isLoading, List<DraftPost>? drafts}) {
    return CommunityDraftsState(
      isLoading: isLoading ?? this.isLoading,
      drafts: drafts ?? this.drafts,
    );
  }
}

class CommunityDraftsNotifier extends StateNotifier<CommunityDraftsState> {
  final CommunityRepository _repository;
  CommunityDraftsNotifier(this._repository)
      : super(const CommunityDraftsState()) {
    loadDrafts();
  }
  Future<void> loadDrafts() async {
    state = state.copyWith(isLoading: true);
    final drafts = await _repository.getDrafts();
    if (!mounted) return;
    state = state.copyWith(isLoading: false, drafts: drafts);
  }
  Future<void> deleteDraft(String draftId) async {
    await _repository.deleteDraft(draftId);
    if (!mounted) return;
    state = state.copyWith(
      drafts: state.drafts.where((d) => d.id != draftId).toList(),
    );
  }
}

final communityDraftsProvider =
    StateNotifierProvider<CommunityDraftsNotifier, CommunityDraftsState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityDraftsNotifier(repo);
});

// JCOM-05-07: canonical answers, session recovery and desired helpful votes.
class CommunityQuestionDetailState {
  final bool isLoading;
  final bool isSubmitting;
  final bool hasPendingAnswer;
  final bool accessible;
  final CommunityPost? question;
  final List<QuestionAnswer> answers;
  final int answerCount;
  final String draft;
  final String? cursor;
  final String? errorMessage;
  final Set<String> voting;
  const CommunityQuestionDetailState({this.isLoading = false, this.isSubmitting = false,
    this.hasPendingAnswer = false, this.accessible = true, this.question,
    this.answers = const [], this.answerCount = 0, this.draft = '', this.cursor,
    this.errorMessage, this.voting = const {}});
  CommunityQuestionDetailState copyWith({bool? isLoading, bool? isSubmitting,
      bool? hasPendingAnswer, bool? accessible, CommunityPost? question,
      List<QuestionAnswer>? answers, int? answerCount, String? draft,
      String? cursor, bool clearCursor = false, String? errorMessage, Set<String>? voting}) =>
    CommunityQuestionDetailState(isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting, hasPendingAnswer: hasPendingAnswer ?? this.hasPendingAnswer,
      accessible: accessible ?? this.accessible, question: (accessible ?? this.accessible) ? question ?? this.question : null,
      answers: answers ?? this.answers, answerCount: answerCount ?? this.answerCount,
      draft: draft ?? this.draft, cursor: clearCursor ? null : cursor ?? this.cursor,
      errorMessage: errorMessage, voting: voting ?? this.voting);
}

class CommunityQuestionDetailNotifier extends StateNotifier<CommunityQuestionDetailState> {
  final CommunityRepository _repository;
  final String _questionId;
  final Ref? _ref;
  int _revision = 0;
  String? _requestKey;
  String? _pendingContent;
  final Map<String, bool> _desiredVotes = {};
  CommunityQuestionDetailNotifier(this._repository, this._questionId, [this._ref])
      : super(const CommunityQuestionDetailState()) { loadAnswers(); }

  bool _denied(Object e) => e is DioException && [401,403,404].contains(e.response?.statusCode);
  void _fail(Object e, String key) {
    if (!mounted) return;
    final denied = _denied(e);
    state = state.copyWith(isLoading: false, isSubmitting: false,
      accessible: denied ? false : state.accessible,
      answers: denied ? [] : state.answers, answerCount: denied ? 0 : state.answerCount,
      clearCursor: denied, errorMessage: denied ? 'community_answer_access' : key);
    if (denied) _ref?.read(communityFeedProvider.notifier).removeInaccessibleQuestion(_questionId);
  }
  void updateDraft(String value) {
    if (!state.hasPendingAnswer) state = state.copyWith(draft: value);
  }
  void _syncCount(int count) => _ref?.read(communityFeedProvider.notifier)
      .updatePostInteractions(postId: _questionId, answerCount: count);

  Future<void> loadAnswers({bool more = false}) async {
    if (state.isLoading || (more && state.cursor == null)) return;
    final revision = _revision;
    state = state.copyWith(isLoading: true);
    try {
      final question = await _repository.getPostDetail(_questionId);
      if (!mounted) return;
      final page = await _repository.getAnswerPage(_questionId, cursor: more ? state.cursor : null);
      if (!mounted || revision != _revision) return;
      final answers = {if (more) for (final a in state.answers) a.id: a,
        for (final a in page.items) a.id: a}.values.toList();
      final count = _repository is CommunityRepositoryImpl
          ? _repository.answerCountFor(_questionId) ?? page.answerCount : page.answerCount;
      state = state.copyWith(isLoading: false, accessible: true, question: question,
          answers: answers, answerCount: count, cursor: page.nextCursor, clearCursor: page.nextCursor == null);
      _syncCount(count);
    } catch (e) {
      if (mounted && revision == _revision) _fail(e, 'community_answer_load_error');
    } finally {
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false, errorMessage: state.errorMessage);
    }
  }
  Future<void> refresh() => loadAnswers();
  Future<bool> submitAnswer(String text) async {
    if (!state.accessible || state.isSubmitting) return false;
    final content = (_pendingContent ?? text).trim();
    if (content.isEmpty || content.length > 2000) {
      state = state.copyWith(errorMessage: 'community_answer_invalid'); return false;
    }
    final recovering = _requestKey != null;
    _requestKey ??= List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    _pendingContent ??= content;
    state = state.copyWith(isSubmitting: true, hasPendingAnswer: true, draft: content);
    try {
      final answer = await _repository.addQuestionAnswer(questionId: _questionId,
          content: _pendingContent!, requestKey: _requestKey);
      if (!mounted) return false;
      _revision++;
      final answers = {for (final a in state.answers) a.id: a, answer.id: answer}.values.toList();
      final count = _repository is CommunityRepositoryImpl
          ? _repository.answerCountFor(_questionId) ?? answers.length : answers.length;
      state = state.copyWith(isSubmitting: false, hasPendingAnswer: false, answers: answers, answerCount: count, draft: '');
      _requestKey = null; _pendingContent = null; _syncCount(count);
      return true;
    } catch (e) {
      if (!mounted) return false;
      final status = e is DioException ? e.response?.statusCode : null;
      final definitive = !recovering && status != null && status >= 400 && status < 500 && status != 404 && status != 408;
      if (definitive) { _requestKey = null; _pendingContent = null; }
      state = state.copyWith(hasPendingAnswer: !definitive);
      _fail(e, definitive ? 'community_answer_rejected' : 'community_answer_unconfirmed');
      return false;
    }
  }
  bool canVote(QuestionAnswer answer) => !(_repository is CommunityRepositoryImpl &&
      _repository.activeUserId == answer.author.id);
  Future<void> toggleUpvote(String answerId) async {
    if (!canVote(state.answers.firstWhere((a) => a.id == answerId))) return;
    if (!state.accessible || state.voting.contains(answerId)) return;
    final old = state.answers.firstWhere((a) => a.id == answerId);
    final desired = _desiredVotes.putIfAbsent(answerId, () => !old.isUpvoted);
    state = state.copyWith(voting: {...state.voting, answerId});
    try {
      QuestionAnswer canonical;
      try {
        canonical = await _repository.setAnswerHelpful(_questionId, answerId, desired);
      } catch (e) {
        if (_denied(e)) rethrow;
        // Resolve a possibly committed PUT/DELETE using current server state.
        canonical = await _repository.getAnswer(_questionId, answerId);
      }
      if (!mounted) return;
      _revision++;
      _desiredVotes.remove(answerId);
      state = state.copyWith(answers: state.answers.map((a) => a.id == answerId ? canonical : a).toList());
    } catch (e) {
      if (mounted) _fail(e, 'community_vote_unconfirmed');
    } finally {
      if (mounted) state = state.copyWith(voting: {...state.voting}..remove(answerId), errorMessage: state.errorMessage);
    }
  }
}

final communityQuestionDetailProvider = StateNotifierProvider.family<
    CommunityQuestionDetailNotifier, CommunityQuestionDetailState, String>((ref, questionId) =>
      CommunityQuestionDetailNotifier(ref.watch(communityRepositoryProvider), questionId, ref));
