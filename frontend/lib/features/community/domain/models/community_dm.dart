enum DmMessageType {
  text,
  voice,
  photo,
  video,
  postShare,
  storyReply;

  String toApiValue() {
    switch (this) {
      case DmMessageType.text:
        return 'text';
      case DmMessageType.voice:
        return 'voice';
      case DmMessageType.photo:
        return 'photo';
      case DmMessageType.video:
        return 'video';
      case DmMessageType.postShare:
        return 'post_share';
      case DmMessageType.storyReply:
        return 'story_reply';
    }
  }

  static DmMessageType fromApiValue(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'voice':
        return DmMessageType.voice;
      case 'photo':
        return DmMessageType.photo;
      case 'video':
        return DmMessageType.video;
      case 'post_share':
        return DmMessageType.postShare;
      case 'story_reply':
        return DmMessageType.storyReply;
      case 'text':
      default:
        return DmMessageType.text;
    }
  }
}

class DmParticipant {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isVerified;
  final bool showActivityStatus;

  const DmParticipant({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isVerified = false,
    this.showActivityStatus = true,
  });

  DmParticipant copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    bool? isVerified,
    bool? showActivityStatus,
  }) {
    return DmParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      showActivityStatus: showActivityStatus ?? this.showActivityStatus,
    );
  }
}

class DmSharedPostPreview {
  final String id;
  final String type;
  final String authorName;
  final String caption;
  final String? thumbnailUrl;

  const DmSharedPostPreview({
    required this.id,
    required this.type,
    required this.authorName,
    this.caption = '',
    this.thumbnailUrl,
  });
}

class DmMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final DmMessageType type;
  final String content;
  final String? mediaUrl;
  final double? durationSeconds;
  final String? sharedPostId;
  final DmSharedPostPreview? sharedPostPreview;
  final String? replyToMessageId;
  final bool isDeleted;
  final DateTime createdAt;

  const DmMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.content = '',
    this.mediaUrl,
    this.durationSeconds,
    this.sharedPostId,
    this.sharedPostPreview,
    this.replyToMessageId,
    this.isDeleted = false,
    required this.createdAt,
  });

  DmMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    DmMessageType? type,
    String? content,
    String? mediaUrl,
    double? durationSeconds,
    String? sharedPostId,
    DmSharedPostPreview? sharedPostPreview,
    String? replyToMessageId,
    bool? isDeleted,
    DateTime? createdAt,
  }) {
    return DmMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      sharedPostId: sharedPostId ?? this.sharedPostId,
      sharedPostPreview: sharedPostPreview ?? this.sharedPostPreview,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class DmConversation {
  final String id;
  final DmParticipant peer;
  final String lastMessagePreview;
  final String? lastMessageType;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime updatedAt;

  const DmConversation({
    required this.id,
    required this.peer,
    this.lastMessagePreview = '',
    this.lastMessageType,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.updatedAt,
  });

  DmConversation copyWith({
    String? id,
    DmParticipant? peer,
    String? lastMessagePreview,
    String? lastMessageType,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return DmConversation(
      id: id ?? this.id,
      peer: peer ?? this.peer,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DmConversationsPage {
  final List<DmConversation> items;
  final int totalUnreadCount;
  final String? nextCursor;

  const DmConversationsPage({
    this.items = const [],
    this.totalUnreadCount = 0,
    this.nextCursor,
  });
}

class DmMessagesPage {
  final List<DmMessage> items;
  final String? nextCursor;

  const DmMessagesPage({
    this.items = const [],
    this.nextCursor,
  });
}

class DmMediaUploadResult {
  final String mediaUrl;
  final String mediaKind; // 'image' | 'audio' | 'video'
  final String contentType;
  final String? fileName;
  final int sizeBytes;

  const DmMediaUploadResult({
    required this.mediaUrl,
    required this.mediaKind,
    required this.contentType,
    this.fileName,
    required this.sizeBytes,
  });

  factory DmMediaUploadResult.fromJson(Map<String, dynamic> json) {
    return DmMediaUploadResult(
      mediaUrl: json['media_url'] as String? ?? '',
      mediaKind: json['media_kind'] as String? ?? 'image',
      contentType: json['content_type'] as String? ?? 'application/octet-stream',
      fileName: json['file_name'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class DmWsEvent {
  final String event;
  final String? conversationId;
  final DmMessage? message;
  final String? messageId;
  final String? deletedBy;
  final String? readerId;
  final DateTime? readAt;
  final String? userId;
  final bool? isTyping;
  final String? detail;

  const DmWsEvent({
    required this.event,
    this.conversationId,
    this.message,
    this.messageId,
    this.deletedBy,
    this.readerId,
    this.readAt,
    this.userId,
    this.isTyping,
    this.detail,
  });

  factory DmWsEvent.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveMediaUrl,
  }) {
    final rawMessage = json['message'];
    DmMessage? parsedMessage;
    if (rawMessage is Map) {
      parsedMessage = dmMessageFromJson(
        Map<String, dynamic>.from(rawMessage),
        resolveMediaUrl: resolveMediaUrl,
      );
    }

    return DmWsEvent(
      event: json['event'] as String? ?? '',
      conversationId: json['conversation_id'] as String?,
      message: parsedMessage,
      messageId: json['message_id'] as String?,
      deletedBy: json['deleted_by'] as String?,
      readerId: json['reader_id'] as String?,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'].toString())
          : null,
      userId: json['user_id'] as String?,
      isTyping: json['is_typing'] as bool?,
      detail: json['detail'] as String?,
    );
  }
}

DmMessage dmMessageFromJson(
  Map<String, dynamic> json, {
  String? Function(String?)? resolveMediaUrl,
}) {
  String? resolve(String? url) =>
      resolveMediaUrl != null ? resolveMediaUrl(url) : url;

  DmSharedPostPreview? preview;
  final rawPreview = json['shared_post_preview'];
  if (rawPreview is Map) {
    final p = Map<String, dynamic>.from(rawPreview);
    preview = DmSharedPostPreview(
      id: p['id'] as String? ?? '',
      type: p['type'] as String? ?? 'photo',
      authorName: p['author_name'] as String? ?? 'Saman Athlete',
      caption: p['caption'] as String? ?? '',
      thumbnailUrl: resolve(p['thumbnail_url'] as String?),
    );
  }

  return DmMessage(
    id: json['id'] as String? ?? '',
    conversationId: json['conversation_id'] as String? ?? '',
    senderId: json['sender_id'] as String? ?? '',
    type: DmMessageType.fromApiValue(json['type'] as String?),
    content: json['content'] as String? ?? '',
    mediaUrl: resolve(json['media_url'] as String?),
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    sharedPostId: json['shared_post_id'] as String?,
    sharedPostPreview: preview,
    replyToMessageId: json['reply_to_message_id'] as String?,
    isDeleted: json['is_deleted'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now().toUtc(),
  );
}
