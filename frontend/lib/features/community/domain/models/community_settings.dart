class CommunitySettings {
  final bool isPrivateAccount;
  final String whoCanDm; // 'everyone' | 'followers' | 'nobody'
  final String whoCanComment; // 'everyone' | 'followers' | 'nobody'
  final String whoCanReplyStory; // 'everyone' | 'followers' | 'nobody'
  final String allowMentions; // 'everyone' | 'followers' | 'nobody'
  final bool hideLikeCounts;
  final bool showActivityStatus;
  final bool autoPromptShareWorkout;
  final bool autoPromptShareMeal;
  final List<String> mutedKeywords;

  const CommunitySettings({
    this.isPrivateAccount = false,
    this.whoCanDm = 'everyone',
    this.whoCanComment = 'everyone',
    this.whoCanReplyStory = 'everyone',
    this.allowMentions = 'everyone',
    this.hideLikeCounts = false,
    this.showActivityStatus = true,
    this.autoPromptShareWorkout = true,
    this.autoPromptShareMeal = true,
    this.mutedKeywords = const [],
  });

  factory CommunitySettings.fromJson(Map<String, dynamic> json) {
    return CommunitySettings(
      isPrivateAccount: json['is_private_account'] as bool? ?? false,
      whoCanDm: json['who_can_dm'] as String? ?? 'everyone',
      whoCanComment: json['who_can_comment'] as String? ?? 'everyone',
      whoCanReplyStory: json['who_can_reply_story'] as String? ?? 'everyone',
      allowMentions: json['allow_mentions'] as String? ?? 'everyone',
      hideLikeCounts: json['hide_like_counts'] as bool? ?? false,
      showActivityStatus: json['show_activity_status'] as bool? ?? true,
      autoPromptShareWorkout:
          json['auto_prompt_share_workout'] as bool? ?? true,
      autoPromptShareMeal: json['auto_prompt_share_meal'] as bool? ?? true,
      mutedKeywords: (json['muted_keywords'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_private_account': isPrivateAccount,
      'who_can_dm': whoCanDm,
      'who_can_comment': whoCanComment,
      'who_can_reply_story': whoCanReplyStory,
      'allow_mentions': allowMentions,
      'hide_like_counts': hideLikeCounts,
      'show_activity_status': showActivityStatus,
      'auto_prompt_share_workout': autoPromptShareWorkout,
      'auto_prompt_share_meal': autoPromptShareMeal,
      'muted_keywords': mutedKeywords,
    };
  }

  CommunitySettings copyWith({
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
  }) {
    return CommunitySettings(
      isPrivateAccount: isPrivateAccount ?? this.isPrivateAccount,
      whoCanDm: whoCanDm ?? this.whoCanDm,
      whoCanComment: whoCanComment ?? this.whoCanComment,
      whoCanReplyStory: whoCanReplyStory ?? this.whoCanReplyStory,
      allowMentions: allowMentions ?? this.allowMentions,
      hideLikeCounts: hideLikeCounts ?? this.hideLikeCounts,
      showActivityStatus: showActivityStatus ?? this.showActivityStatus,
      autoPromptShareWorkout:
          autoPromptShareWorkout ?? this.autoPromptShareWorkout,
      autoPromptShareMeal: autoPromptShareMeal ?? this.autoPromptShareMeal,
      mutedKeywords: mutedKeywords ?? this.mutedKeywords,
    );
  }
}

class CommunityReportReceipt {
  final String reportId;
  final String targetType;
  final String targetId;
  final String reason;
  final String status;
  final DateTime createdAt;
  final bool alreadyReported;

  const CommunityReportReceipt({
    required this.reportId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.status = 'received',
    required this.createdAt,
    this.alreadyReported = false,
  });

  factory CommunityReportReceipt.fromJson(Map<String, dynamic> json) {
    return CommunityReportReceipt(
      reportId: json['report_id'] as String? ?? '',
      targetType: json['target_type'] as String? ?? 'post',
      targetId: json['target_id'] as String? ?? '',
      reason: json['reason'] as String? ?? 'other',
      status: json['status'] as String? ?? 'received',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      alreadyReported: json['already_reported'] as bool? ?? false,
    );
  }
}
