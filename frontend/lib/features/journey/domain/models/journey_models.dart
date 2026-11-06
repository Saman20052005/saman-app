import 'package:flutter/foundation.dart';

enum JourneyFocus {
  workout,
  nutrition,
  hybrid;

  String get label {
    switch (this) {
      case JourneyFocus.workout:
        return 'Tập luyện';
      case JourneyFocus.nutrition:
        return 'Dinh dưỡng';
      case JourneyFocus.hybrid:
        return 'Kết hợp cả hai';
    }
  }

  String get description {
    switch (this) {
      case JourneyFocus.workout:
        return 'Rèn luyện thể lực bền bỉ và theo sát các buổi tập.';
      case JourneyFocus.nutrition:
        return 'Ghi nhận bữa ăn chuẩn dinh dưỡng, cân đối calo mỗi ngày.';
      case JourneyFocus.hybrid:
        return 'Duy trì lối sống năng động, kết hợp dinh dưỡng và vận động.';
    }
  }

  static JourneyFocus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'workout':
        return JourneyFocus.workout;
      case 'nutrition':
        return JourneyFocus.nutrition;
      case 'both':
      case 'hybrid':
      default:
        return JourneyFocus.hybrid;
    }
  }
}

enum JourneyStatus {
  active,
  completed,
  abandoned;

  static JourneyStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'completed':
        return JourneyStatus.completed;
      case 'abandoned':
        return JourneyStatus.abandoned;
      case 'active':
      default:
        return JourneyStatus.active;
    }
  }
}

enum JourneyTaskType {
  nutrition,
  workout,
  water;

  static JourneyTaskType fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'workout':
        return JourneyTaskType.workout;
      case 'water':
        return JourneyTaskType.water;
      case 'nutrition':
      default:
        return JourneyTaskType.nutrition;
    }
  }
}

@immutable
class JourneyTask {
  final String id;
  final JourneyTaskType type;
  final String title;
  final String subtitle;
  final bool isCompleted;
  final int points;
  final String? activityId;

  const JourneyTask({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.isCompleted = false,
    this.points = 0,
    this.activityId,
  });

  JourneyTask copyWith({
    String? id,
    JourneyTaskType? type,
    String? title,
    String? subtitle,
    bool? isCompleted,
    int? points,
    String? activityId,
  }) {
    return JourneyTask(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isCompleted: isCompleted ?? this.isCompleted,
      points: points ?? this.points,
      activityId: activityId ?? this.activityId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'is_completed': isCompleted,
        'points': points,
        'activity_id': activityId,
      };

  factory JourneyTask.fromJson(Map<String, dynamic> json) => JourneyTask(
        id: json['id'] as String? ?? '',
        type: JourneyTaskType.fromString(json['type'] as String?),
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        isCompleted: json['is_completed'] as bool? ?? false,
        points: (json['points'] as num?)?.toInt() ?? 0,
        activityId: json['activity_id'] as String?,
      );
}

@immutable
class JourneyDayRecord {
  final String date;
  final int dayIndex;
  final bool isCompleted;
  final bool isRestDay;
  final bool isDailyRewardClaimed;
  final int dailyRewardPoints;
  final List<JourneyTask> tasks;
  final int pointsEarned;

  const JourneyDayRecord({
    required this.date,
    required this.dayIndex,
    this.isCompleted = false,
    this.isRestDay = false,
    this.isDailyRewardClaimed = false,
    this.dailyRewardPoints = 20,
    this.tasks = const [],
    this.pointsEarned = 0,
  });

  bool get isReadyToClaim => isCompleted && !isDailyRewardClaimed;

  JourneyDayRecord copyWith({
    String? date,
    int? dayIndex,
    bool? isCompleted,
    bool? isRestDay,
    bool? isDailyRewardClaimed,
    int? dailyRewardPoints,
    List<JourneyTask>? tasks,
    int? pointsEarned,
  }) {
    return JourneyDayRecord(
      date: date ?? this.date,
      dayIndex: dayIndex ?? this.dayIndex,
      isCompleted: isCompleted ?? this.isCompleted,
      isRestDay: isRestDay ?? this.isRestDay,
      isDailyRewardClaimed: isDailyRewardClaimed ?? this.isDailyRewardClaimed,
      dailyRewardPoints: dailyRewardPoints ?? this.dailyRewardPoints,
      tasks: tasks ?? this.tasks,
      pointsEarned: pointsEarned ?? this.pointsEarned,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'day_index': dayIndex,
        'is_completed': isCompleted,
        'is_rest_day': isRestDay,
        'is_daily_reward_claimed': isDailyRewardClaimed,
        'daily_reward_points': dailyRewardPoints,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'points_earned': pointsEarned,
      };

  factory JourneyDayRecord.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'] as List<dynamic>? ?? [];
    return JourneyDayRecord(
      date: json['date'] as String? ?? '',
      dayIndex: (json['day_index'] as num?)?.toInt() ?? 1,
      isCompleted: json['is_completed'] as bool? ?? false,
      isRestDay: json['is_rest_day'] as bool? ?? false,
      isDailyRewardClaimed: json['is_daily_reward_claimed'] as bool? ?? false,
      dailyRewardPoints: (json['daily_reward_points'] as num?)?.toInt() ?? 20,
      tasks: rawTasks.map((t) => JourneyTask.fromJson(t as Map<String, dynamic>)).toList(),
      pointsEarned: (json['points_earned'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class SamanJourney {
  final String id;
  final String userId;
  final JourneyFocus focus;
  final int totalDays;
  final String startDate;
  final String endDate;
  final String? reminderTime;
  final JourneyStatus status;
  final int currentStreak;
  final int completedDaysCount;
  final int bestStreak;
  final int pointsEarned;
  final JourneyDayRecord? todayRecord;
  final List<JourneyDayRecord> days;

  const SamanJourney({
    required this.id,
    required this.userId,
    required this.focus,
    required this.totalDays,
    required this.startDate,
    required this.endDate,
    this.reminderTime,
    this.status = JourneyStatus.active,
    this.currentStreak = 0,
    this.completedDaysCount = 0,
    this.bestStreak = 0,
    this.pointsEarned = 0,
    this.todayRecord,
    this.days = const [],
  });

  bool get isActive => status == JourneyStatus.active;
  double get progress => totalDays > 0 ? (completedDaysCount / totalDays).clamp(0.0, 1.0) : 0.0;

  SamanJourney copyWith({
    String? id,
    String? userId,
    JourneyFocus? focus,
    int? totalDays,
    String? startDate,
    String? endDate,
    String? reminderTime,
    JourneyStatus? status,
    int? currentStreak,
    int? completedDaysCount,
    int? bestStreak,
    int? pointsEarned,
    JourneyDayRecord? todayRecord,
    List<JourneyDayRecord>? days,
  }) {
    return SamanJourney(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      focus: focus ?? this.focus,
      totalDays: totalDays ?? this.totalDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      reminderTime: reminderTime ?? this.reminderTime,
      status: status ?? this.status,
      currentStreak: currentStreak ?? this.currentStreak,
      completedDaysCount: completedDaysCount ?? this.completedDaysCount,
      bestStreak: bestStreak ?? this.bestStreak,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      todayRecord: todayRecord ?? this.todayRecord,
      days: days ?? this.days,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'focus': focus.name,
        'total_days': totalDays,
        'start_date': startDate,
        'end_date': endDate,
        'reminder_time': reminderTime,
        'status': status.name,
        'current_streak': currentStreak,
        'completed_days_count': completedDaysCount,
        'best_streak': bestStreak,
        'points_earned': pointsEarned,
        'today_record': todayRecord?.toJson(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory SamanJourney.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? [];
    return SamanJourney(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      focus: JourneyFocus.fromString(json['focus'] as String?),
      totalDays: (json['total_days'] as num?)?.toInt() ?? 21,
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      reminderTime: json['reminder_time'] as String?,
      status: JourneyStatus.fromString(json['status'] as String?),
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      completedDaysCount: (json['completed_days_count'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      pointsEarned: (json['points_earned'] as num?)?.toInt() ?? 0,
      todayRecord: json['today_record'] != null
          ? JourneyDayRecord.fromJson(json['today_record'] as Map<String, dynamic>)
          : null,
      days: rawDays.map((d) => JourneyDayRecord.fromJson(d as Map<String, dynamic>)).toList(),
    );
  }
}

@immutable
class PointTransaction {
  final String id;
  final String userId;
  final int amount;
  final String type;
  final String description;
  final String createdAt;
  final String? referenceId;

  const PointTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.description,
    required this.createdAt,
    this.referenceId,
  });

  bool get isEarned => amount > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'amount': amount,
        'type': type,
        'description': description,
        'created_at': createdAt,
        'reference_id': referenceId,
      };

  factory PointTransaction.fromJson(Map<String, dynamic> json) => PointTransaction(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'general',
        description: json['description'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        referenceId: json['reference_id'] as String?,
      );
}

@immutable
class RewardItem {
  final String id;
  final String title;
  final String description;
  final int pointsCost;
  final int aiCredits;
  final String category;
  final String iconName;
  final bool isAvailable;
  final String statusNote;

  const RewardItem({
    required this.id,
    required this.title,
    required this.description,
    required this.pointsCost,
    this.aiCredits = 0,
    required this.category,
    this.iconName = 'stars',
    this.isAvailable = true,
    this.statusNote = 'Khả dụng',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'points_cost': pointsCost,
        'ai_credits': aiCredits,
        'category': category,
        'icon_name': iconName,
        'is_available': isAvailable,
        'status_note': statusNote,
      };

  factory RewardItem.fromJson(Map<String, dynamic> json) => RewardItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        pointsCost: (json['points_cost'] as num?)?.toInt() ?? 100,
        aiCredits: (json['ai_credits'] as num?)?.toInt() ?? 0,
        category: json['category'] as String? ?? 'perk',
        iconName: json['icon_name'] as String? ?? 'stars',
        isAvailable: json['is_available'] as bool? ?? true,
        statusNote: json['status_note'] as String? ?? 'Khả dụng',
      );
}
