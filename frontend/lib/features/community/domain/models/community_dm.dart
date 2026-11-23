enum DmMessageType {
  text,
  voice,
  photo,
  video,
  postShare,
  storyReply,
  callLog;

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
      case DmMessageType.callLog:
        return 'call_log';
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
      case 'call_log':
        return DmMessageType.callLog;
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

  factory DmParticipant.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveMediaUrl,
  }) {
    final rawAvatar = json['avatar_url'] as String?;
    return DmParticipant(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Saman Athlete',
      avatarUrl:
          resolveMediaUrl != null ? resolveMediaUrl(rawAvatar) : rawAvatar,
      isVerified: json['is_verified'] as bool? ?? false,
      showActivityStatus: json['show_activity_status'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'is_verified': isVerified,
      'show_activity_status': showActivityStatus,
    };
  }

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'author_name': authorName,
      'caption': caption,
      'thumbnail_url': thumbnailUrl,
    };
  }
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
  final String? callId;
  final String? callType; // 'audio' | 'video'
  final String? callStatus; // 'completed' | 'missed' | 'rejected'
  final int? durationSec;

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
    this.callId,
    this.callType,
    this.callStatus,
    this.durationSec,
  });

  factory DmMessage.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveMediaUrl,
  }) {
    return dmMessageFromJson(json, resolveMediaUrl: resolveMediaUrl);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'type': type.toApiValue(),
      'content': content,
      'media_url': mediaUrl,
      'duration_seconds': durationSeconds,
      'shared_post_id': sharedPostId,
      'shared_post_preview': sharedPostPreview?.toJson(),
      'reply_to_message_id': replyToMessageId,
      'is_deleted': isDeleted,
      'created_at': createdAt.toUtc().toIso8601String(),
      'call_id': callId,
      'call_type': callType,
      'call_status': callStatus,
      'duration_sec': durationSec,
    };
  }

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
    String? callId,
    String? callType,
    String? callStatus,
    int? durationSec,
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
      callId: callId ?? this.callId,
      callType: callType ?? this.callType,
      callStatus: callStatus ?? this.callStatus,
      durationSec: durationSec ?? this.durationSec,
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

  // Call & WebRTC signaling fields (Phase 5A/5B)
  final String? callId;
  final String? callType; // 'audio' | 'video'
  final DmParticipant? caller;
  final String? byUserId;
  final String? fromUserId;
  final int? durationSec;
  final String? code;
  final String? sdp;
  final String? sdpType;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMlineIndex;

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
    this.callId,
    this.callType,
    this.caller,
    this.byUserId,
    this.fromUserId,
    this.durationSec,
    this.code,
    this.sdp,
    this.sdpType,
    this.candidate,
    this.sdpMid,
    this.sdpMlineIndex,
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

    final rawCaller = json['caller'];
    DmParticipant? parsedCaller;
    if (rawCaller is Map) {
      parsedCaller = DmParticipant.fromJson(
        Map<String, dynamic>.from(rawCaller),
        resolveMediaUrl: resolveMediaUrl,
      );
    }

    final rawCandidate = json['candidate'];
    final String? parsedCandidate = rawCandidate is String
        ? rawCandidate
        : rawCandidate?.toString();

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
      callId: json['call_id'] as String?,
      callType: json['call_type'] as String?,
      caller: parsedCaller,
      byUserId: json['by_user_id'] as String?,
      fromUserId: json['from_user_id'] as String?,
      durationSec: (json['duration_sec'] as num?)?.toInt(),
      code: json['code'] as String?,
      sdp: json['sdp'] as String?,
      sdpType: json['sdp_type'] as String?,
      candidate: parsedCandidate,
      sdpMid: json['sdp_mid'] as String?,
      sdpMlineIndex: (json['sdp_mline_index'] as num?)?.toInt(),
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
    callId: json['call_id'] as String?,
    callType: json['call_type'] as String?,
    callStatus: json['call_status'] as String?,
    durationSec: (json['duration_sec'] as num?)?.toInt(),
  );
}

String formatDmCallDuration(int? durationSec) {
  final sec = (durationSec ?? 0) < 0 ? 0 : (durationSec ?? 0);
  final hours = sec ~/ 3600;
  final rem = sec % 3600;
  final minutes = (rem ~/ 60).toString().padLeft(2, '0');
  final seconds = (rem % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    final hh = hours.toString().padLeft(2, '0');
    return '$hh:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String formatDmCallLogPreview(DmMessage msg) {
  if (msg.content.trim().isNotEmpty) {
    return msg.content.trim();
  }
  final isVideo = (msg.callType ?? '').toLowerCase() == 'video';
  final label = isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại';
  switch ((msg.callStatus ?? '').toLowerCase()) {
    case 'completed':
      return '$label • ${formatDmCallDuration(msg.durationSec)}';
    case 'missed':
      return '$label nhỡ';
    case 'rejected':
      return isVideo ? 'Đã từ chối cuộc gọi video' : 'Đã từ chối cuộc gọi';
    default:
      return label;
  }
}
