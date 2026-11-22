enum CommunityNotificationType { like, comment, follow, answer, system }

class CommunityNotification {
  final String id;
  final String? actorId;
  final String actorName;
  final String? actorAvatarUrl;
  final String actionText;
  final String? targetSnippet;
  final String timeAgo;
  final bool isUnread;
  final CommunityNotificationType type;
  final String? targetPostId;
  final String? targetPostType;

  const CommunityNotification({
    required this.id,
    this.actorId,
    required this.actorName,
    this.actorAvatarUrl,
    required this.actionText,
    this.targetSnippet,
    required this.timeAgo,
    this.isUnread = true,
    required this.type,
    this.targetPostId,
    this.targetPostType,
  });

  CommunityNotification copyWith({
    String? id,
    String? actorId,
    String? actorName,
    String? actorAvatarUrl,
    String? actionText,
    String? targetSnippet,
    String? timeAgo,
    bool? isUnread,
    CommunityNotificationType? type,
    String? targetPostId,
    String? targetPostType,
  }) {
    return CommunityNotification(
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      actorAvatarUrl: actorAvatarUrl ?? this.actorAvatarUrl,
      actionText: actionText ?? this.actionText,
      targetSnippet: targetSnippet ?? this.targetSnippet,
      timeAgo: timeAgo ?? this.timeAgo,
      isUnread: isUnread ?? this.isUnread,
      type: type ?? this.type,
      targetPostId: targetPostId ?? this.targetPostId,
      targetPostType: targetPostType ?? this.targetPostType,
    );
  }
}
