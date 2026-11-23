import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/community_dm_ws_service.dart';
import '../../domain/models/community_dm.dart';
import '../../domain/repositories/community_repository.dart';
import 'community_providers.dart';

final communityDmWsServiceProvider = Provider<CommunityDmWsService>((ref) {
  final service = CommunityDmWsService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class CommunityDmUnreadNotifier extends StateNotifier<int> {
  final CommunityRepository _repository;
  int _generation = 0;

  CommunityDmUnreadNotifier(this._repository) : super(0);

  void resetForUser(String? userId) {
    _generation++;
    state = 0;
  }

  void setUnreadCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> loadUnreadCount() async {
    final gen = _generation;
    try {
      final count = await _repository.getDmUnreadCount();
      if (!mounted || gen != _generation) return;
      state = count < 0 ? 0 : count;
    } catch (_) {}
  }
}

final communityDmUnreadProvider =
    StateNotifierProvider<CommunityDmUnreadNotifier, int>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  return CommunityDmUnreadNotifier(repo);
});

class CommunityInboxState {
  final bool isLoading;
  final bool isLoadingMore;
  final List<DmConversation> conversations;
  final String? nextCursor;
  final int totalUnreadCount;
  final String? errorMessage;

  const CommunityInboxState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.conversations = const [],
    this.nextCursor,
    this.totalUnreadCount = 0,
    this.errorMessage,
  });

  CommunityInboxState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    List<DmConversation>? conversations,
    String? nextCursor,
    bool clearCursor = false,
    int? totalUnreadCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CommunityInboxState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      conversations: conversations ?? this.conversations,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CommunityInboxNotifier extends StateNotifier<CommunityInboxState> {
  final CommunityRepository _repository;
  final CommunityDmWsService _wsService;
  final Ref _ref;
  StreamSubscription<DmWsEvent>? _wsSub;
  int _generation = 0;

  CommunityInboxNotifier(this._repository, this._wsService, this._ref)
      : super(const CommunityInboxState()) {
    _wsSub = _wsService.events.listen(_handleWsEvent);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunityInboxState();
  }

  void _handleWsEvent(DmWsEvent event) {
    if (!mounted) return;
    if (event.event == 'message.created' && event.message != null) {
      final msg = event.message!;
      final idx =
          state.conversations.indexWhere((c) => c.id == msg.conversationId);
      if (idx == -1) {
        loadConversations();
        return;
      }
      final existing = state.conversations[idx];
      final isFromPeer = msg.senderId != _repository.activeUserId;
      final preview = msg.type == DmMessageType.callLog
          ? formatDmCallLogPreview(msg)
          : (msg.content.isNotEmpty ? msg.content : msg.type.toApiValue());
      final shouldIncrementUnread = msg.type == DmMessageType.callLog
          ? (isFromPeer && (msg.callStatus ?? '').toLowerCase() == 'missed')
          : isFromPeer;
      final updated = existing.copyWith(
        lastMessagePreview: preview,
        lastMessageType: msg.type.toApiValue(),
        lastMessageAt: msg.createdAt,
        updatedAt: msg.createdAt,
        unreadCount: shouldIncrementUnread
            ? existing.unreadCount + 1
            : existing.unreadCount,
      );
      final next = List<DmConversation>.from(state.conversations)
        ..removeAt(idx)
        ..insert(0, updated);
      final totalUnread = next.fold<int>(0, (sum, c) => sum + c.unreadCount);
      state = state.copyWith(
        conversations: next,
        totalUnreadCount: totalUnread,
      );
      _ref.read(communityDmUnreadProvider.notifier).setUnreadCount(totalUnread);
    } else if (event.event == 'conversation.read' &&
        event.conversationId != null &&
        event.readerId == _repository.activeUserId) {
      _clearConversationUnread(event.conversationId!);
    }
  }

  void _clearConversationUnread(String conversationId) {
    final next = state.conversations.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(unreadCount: 0);
    }).toList();
    final totalUnread = next.fold<int>(0, (sum, c) => sum + c.unreadCount);
    state = state.copyWith(
      conversations: next,
      totalUnreadCount: totalUnread,
    );
    _ref.read(communityDmUnreadProvider.notifier).setUnreadCount(totalUnread);
  }

  Future<void> loadConversations() async {
    final gen = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _repository.getConversations();
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        conversations: page.items,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        totalUnreadCount: page.totalUnreadCount,
      );
      _ref
          .read(communityDmUnreadProvider.notifier)
          .setUnreadCount(page.totalUnreadCount);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải hộp thư',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.nextCursor == null) return;
    final gen = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repository.getConversations(cursor: state.nextCursor);
      if (!mounted || gen != _generation) return;
      final merged = <String, DmConversation>{
        for (final c in state.conversations) c.id: c,
        for (final c in page.items) c.id: c,
      }.values.toList();
      state = state.copyWith(
        isLoadingMore: false,
        conversations: merged,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        totalUnreadCount: page.totalUnreadCount,
      );
    } catch (_) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<DmConversation> createOrGetConversation(String targetUserId) async {
    final conv = await _repository.createOrGetConversation(targetUserId);
    final exists = state.conversations.any((c) => c.id == conv.id);
    if (!exists) {
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
      );
    }
    return conv;
  }

  Future<void> markConversationRead(String conversationId) async {
    await _repository.markConversationRead(conversationId);
    if (!mounted) return;
    _clearConversationUnread(conversationId);
  }
}

final communityInboxProvider =
    StateNotifierProvider<CommunityInboxNotifier, CommunityInboxState>((ref) {
  final repo = ref.watch(communityRepositoryProvider);
  final ws = ref.watch(communityDmWsServiceProvider);
  return CommunityInboxNotifier(repo, ws, ref);
});

class CommunityChatThreadState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSending;
  final List<DmMessage> messages;
  final String? nextCursor;
  final bool peerIsTyping;
  final DateTime? peerReadAt;
  final String? errorMessage;

  const CommunityChatThreadState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.messages = const [],
    this.nextCursor,
    this.peerIsTyping = false,
    this.peerReadAt,
    this.errorMessage,
  });

  CommunityChatThreadState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSending,
    List<DmMessage>? messages,
    String? nextCursor,
    bool clearCursor = false,
    bool? peerIsTyping,
    DateTime? peerReadAt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CommunityChatThreadState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      messages: messages ?? this.messages,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      peerIsTyping: peerIsTyping ?? this.peerIsTyping,
      peerReadAt: peerReadAt ?? this.peerReadAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CommunityChatThreadNotifier
    extends StateNotifier<CommunityChatThreadState> {
  final CommunityRepository _repository;
  final CommunityDmWsService _wsService;
  final String conversationId;
  StreamSubscription<DmWsEvent>? _wsSub;
  int _generation = 0;

  CommunityChatThreadNotifier(
    this._repository,
    this._wsService,
    this.conversationId,
  ) : super(const CommunityChatThreadState()) {
    _wsSub = _wsService.events.listen(_handleWsEvent);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void resetForUser(String? userId) {
    _generation++;
    state = const CommunityChatThreadState();
  }

  String _generateIdempotencyKey() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _handleWsEvent(DmWsEvent event) {
    if (!mounted) return;
    if (event.conversationId != conversationId) return;

    switch (event.event) {
      case 'message.created':
        final incoming = event.message;
        if (incoming == null) return;
        _upsertMessage(incoming);
        state = state.copyWith(peerIsTyping: false);
        break;
      case 'message.deleted':
        final msgId = event.messageId;
        if (msgId == null || msgId.isEmpty) return;
        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id != msgId) return m;
            return m.copyWith(
              isDeleted: true,
              content: '',
              mediaUrl: null,
              durationSeconds: null,
              sharedPostId: null,
              sharedPostPreview: null,
            );
          }).toList(),
        );
        break;
      case 'conversation.read':
        if (event.readerId != _repository.activeUserId && event.readAt != null) {
          state = state.copyWith(peerReadAt: event.readAt);
        }
        break;
      case 'typing':
        if (event.userId != _repository.activeUserId) {
          state = state.copyWith(peerIsTyping: event.isTyping ?? false);
        }
        break;
    }
  }

  void _upsertMessage(DmMessage message, {String? replaceTempId}) {
    final next = List<DmMessage>.from(state.messages);
    if (replaceTempId != null) {
      next.removeWhere((m) => m.id == replaceTempId);
    }
    final existingIdx = next.indexWhere((m) => m.id == message.id);
    if (existingIdx != -1) {
      next[existingIdx] = message;
    } else {
      next.insert(0, message);
    }
    state = state.copyWith(messages: next);
  }

  Future<void> loadMessages({bool loadMore = false}) async {
    if (loadMore && (state.isLoadingMore || state.nextCursor == null)) return;
    final gen = _generation;
    state = state.copyWith(
      isLoading: !loadMore,
      isLoadingMore: loadMore,
      clearError: true,
    );
    try {
      final page = await _repository.getMessages(
        conversationId,
        cursor: loadMore ? state.nextCursor : null,
      );
      if (!mounted || gen != _generation) return;
      final merged = loadMore
          ? <String, DmMessage>{
              for (final m in state.messages) m.id: m,
              for (final m in page.items) m.id: m,
            }.values.toList()
          : page.items;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        messages: merged,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
      );
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: 'Không thể tải tin nhắn',
      );
    }
  }

  Future<DmMessage?> sendMessage({
    required DmMessageType type,
    String content = '',
    String? mediaUrl,
    double? durationSeconds,
    String? sharedPostId,
    String? replyToMessageId,
    String? idempotencyKey,
  }) async {
    final gen = _generation;
    final key = idempotencyKey ?? _generateIdempotencyKey();
    final tempId = 'temp_$key';
    final optimistic = DmMessage(
      id: tempId,
      conversationId: conversationId,
      senderId: _repository.activeUserId ?? 'me',
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      durationSeconds: durationSeconds,
      sharedPostId: sharedPostId,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now().toUtc(),
    );

    _upsertMessage(optimistic);
    state = state.copyWith(isSending: true, clearError: true);

    try {
      final canonical = await _repository.sendMessage(
        conversationId: conversationId,
        type: type,
        content: content,
        mediaUrl: mediaUrl,
        durationSeconds: durationSeconds,
        sharedPostId: sharedPostId,
        replyToMessageId: replyToMessageId,
        idempotencyKey: key,
      );
      if (!mounted || gen != _generation) return null;
      _upsertMessage(canonical, replaceTempId: tempId);
      state = state.copyWith(isSending: false);
      return canonical;
    } catch (e) {
      if (!mounted || gen != _generation) return null;
      state = state.copyWith(
        isSending: false,
        messages: state.messages.where((m) => m.id != tempId).toList(),
        errorMessage: 'Không thể gửi tin nhắn',
      );
      return null;
    }
  }

  Future<void> markRead() async {
    await _repository.markConversationRead(conversationId);
  }

  Future<bool> deleteMessage(String messageId) async {
    final deleted = await _repository.deleteMessage(messageId);
    if (!mounted) return deleted;
    if (deleted) {
      state = state.copyWith(
        messages: state.messages.map((m) {
          if (m.id != messageId) return m;
          return m.copyWith(
            isDeleted: true,
            content: '',
            mediaUrl: null,
            durationSeconds: null,
            sharedPostId: null,
            sharedPostPreview: null,
          );
        }).toList(),
      );
    }
    return deleted;
  }

  void sendTyping(bool isTyping) {
    _wsService.sendTyping(conversationId, isTyping);
  }
}

final communityChatThreadProvider = StateNotifierProvider.family<
    CommunityChatThreadNotifier, CommunityChatThreadState, String>(
  (ref, conversationId) {
    final repo = ref.watch(communityRepositoryProvider);
    final ws = ref.watch(communityDmWsServiceProvider);
    return CommunityChatThreadNotifier(repo, ws, conversationId);
  },
);
