enum CommunityNotificationType { like, comment, follow, system }

class CommunityNotification {
  final String id;
  final String actorName;
  final String? actorAvatarUrl;
  final String actionText;
  final String? targetSnippet;
  final String timeAgo;
  final bool isUnread;
  final CommunityNotificationType type;
  final String? targetPostId;

  const CommunityNotification({
    required this.id,
    required this.actorName,
    this.actorAvatarUrl,
    required this.actionText,
    this.targetSnippet,
    required this.timeAgo,
    this.isUnread = true,
    required this.type,
    this.targetPostId,
  });

  CommunityNotification copyWith({
    String? id,
    String? actorName,
    String? actorAvatarUrl,
    String? actionText,
    String? targetSnippet,
    String? timeAgo,
    bool? isUnread,
    CommunityNotificationType? type,
    String? targetPostId,
  }) {
    return CommunityNotification(
      id: id ?? this.id,
      actorName: actorName ?? this.actorName,
      actorAvatarUrl: actorAvatarUrl ?? this.actorAvatarUrl,
      actionText: actionText ?? this.actionText,
      targetSnippet: targetSnippet ?? this.targetSnippet,
      timeAgo: timeAgo ?? this.timeAgo,
      isUnread: isUnread ?? this.isUnread,
      type: type ?? this.type,
      targetPostId: targetPostId ?? this.targetPostId,
    );
  }
}
