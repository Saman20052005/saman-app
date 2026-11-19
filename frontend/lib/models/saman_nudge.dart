import 'package:flutter/foundation.dart';

/// Lightweight explicit model for a proactive coaching nudge or reminder in Saman Chat (State 04).
///
/// Designed to be presentation-only and transient. Never persisted or inserted into
/// persistent ChatMessage history, and never sent to /api/chat.
@immutable
class SamanNudge {
  final String id;
  final String message;
  final String? supportingLine;
  final DateTime? timestamp;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final String? promptToSend;

  const SamanNudge({
    this.id = 'default_nudge',
    required this.message,
    this.supportingLine,
    this.timestamp,
    this.primaryLabel = 'Plan dinner',
    this.onPrimary,
    this.secondaryLabel = 'Later',
    this.onSecondary,
    this.promptToSend,
  });

  factory SamanNudge.fromJson(Map<String, dynamic> json) {
    return SamanNudge(
      id: json['id']?.toString() ?? 'ai_nudge',
      message: json['message']?.toString() ?? '',
      supportingLine: json['supporting_line']?.toString(),
      primaryLabel: json['primary_label']?.toString() ?? 'Ask Saman',
      secondaryLabel: json['secondary_label']?.toString() ?? 'Later',
      promptToSend: json['prompt_to_send']?.toString(),
      timestamp: DateTime.now(),
    );
  }

  SamanNudge copyWith({
    String? id,
    String? message,
    String? supportingLine,
    DateTime? timestamp,
    String? primaryLabel,
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    String? promptToSend,
  }) {
    return SamanNudge(
      id: id ?? this.id,
      message: message ?? this.message,
      supportingLine: supportingLine ?? this.supportingLine,
      timestamp: timestamp ?? this.timestamp,
      primaryLabel: primaryLabel ?? this.primaryLabel,
      onPrimary: onPrimary ?? this.onPrimary,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      onSecondary: onSecondary ?? this.onSecondary,
      promptToSend: promptToSend ?? this.promptToSend,
    );
  }
}

/// Helper to build a safe, grounded Saman proactive nudge from real nutrition & workout targets.
///
/// Note: Must not be auto-triggered in production without explicit intent/configuration.
class SamanNudgeHelper {
  const SamanNudgeHelper._();

  static SamanNudge? createNutritionNudge({
    required int consumedCalories,
    required int targetCalories,
    required int consumedProtein,
    required int targetProtein,
    String? tomorrowSession,
    DateTime? timestamp,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) {
    final remainingCalories = (targetCalories - consumedCalories).clamp(0, 9999);
    final remainingProtein = (targetProtein - consumedProtein).clamp(0, 9999);
    if (remainingCalories <= 0 && remainingProtein <= 0) return null;

    final sessionSuffix = tomorrowSession != null
        ? " before tomorrow’s $tomorrowSession session."
        : ".";

    return SamanNudge(
      id: 'nutrition_gap_nudge',
      message:
          'You still have $remainingCalories kcal and ${remainingProtein}g protein left today. A high-protein dinner would close most of the gap$sessionSuffix',
      supportingLine:
          '• $consumedCalories / $targetCalories kcal · ${remainingProtein}g protein remaining',
      timestamp: timestamp ?? DateTime.now(),
      primaryLabel: 'Plan dinner',
      secondaryLabel: 'Later',
      promptToSend:
          'Plan a high-protein dinner based on my remaining nutrition targets ($remainingCalories kcal, ${remainingProtein}g protein).',
      onPrimary: onPrimary,
      onSecondary: onSecondary,
    );
  }

  static SamanNudge? fromDailyBrief(Map<String, dynamic> payload) {
    final rawNudge = payload['nudge'];
    if (rawNudge is Map) {
      final parsed = SamanNudge.fromJson(Map<String, dynamic>.from(rawNudge));
      if (parsed.message.trim().isNotEmpty) {
        return parsed;
      }
    }

    final brief = (payload['daily_brief'] ?? payload['brief'])?.toString();
    if (brief != null && brief.trim().isNotEmpty) {
      return SamanNudge(
        id: 'daily_brief_nudge',
        message: brief,
        primaryLabel: 'Hỏi Saman',
        secondaryLabel: 'Để sau',
        promptToSend: 'Dựa trên tình hình hôm nay, tôi nên làm gì tiếp theo?',
      );
    }

    return null;
  }

  static SamanNudge? buildGroundedHomeNudge({
    required int consumedCalories,
    required int targetCalories,
    required double consumedProtein,
    required double targetProtein,
    required int waterMl,
    required int waterTargetMl,
    String? pendingJourneyTaskTitle,
    bool hasRealNutritionData = false,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) {
    if (!hasRealNutritionData && pendingJourneyTaskTitle == null) {
      return null;
    }

    if (pendingJourneyTaskTitle != null &&
        pendingJourneyTaskTitle.trim().isNotEmpty) {
      final title = pendingJourneyTaskTitle.trim();
      return SamanNudge(
        id: 'journey_task_nudge',
        message: 'Bạn có nhiệm vụ hành trình đang chờ: "$title". Hoàn thành sớm nhé!',
        supportingLine: 'Hành trình hôm nay',
        primaryLabel: 'Xem nhiệm vụ',
        secondaryLabel: 'Để sau',
        promptToSend: 'Hướng dẫn tôi hoàn thành nhiệm vụ "$title"',
        onPrimary: onPrimary,
        onSecondary: onSecondary,
      );
    }

    if (targetProtein > 0 && consumedProtein < targetProtein * 0.7) {
      final remainingProtein = (targetProtein - consumedProtein).clamp(0, 9999).round();
      final remainingCalories = (targetCalories - consumedCalories).clamp(0, 9999);
      return SamanNudge(
        id: 'nutrition_deficit_nudge',
        message:
            'Bạn đang thiếu khoảng ${remainingProtein}g đạm và $remainingCalories kcal so với mục tiêu hôm nay. Hãy bổ sung thêm trong bữa ăn tiếp theo nhé!',
        supportingLine:
            '• ${consumedProtein.round()} / ${targetProtein.round()}g đạm · $consumedCalories / $targetCalories kcal',
        primaryLabel: 'Gợi ý món ăn',
        secondaryLabel: 'Để sau',
        promptToSend:
            'Gợi ý cho tôi món ăn bổ sung khoảng ${remainingProtein}g đạm và $remainingCalories kcal.',
        onPrimary: onPrimary,
        onSecondary: onSecondary,
      );
    }

    if (waterTargetMl > 0 && waterMl < waterTargetMl * 0.5) {
      final missingWater = waterTargetMl - waterMl;
      return SamanNudge(
        id: 'water_hydration_nudge',
        message:
            'Bạn mới uống $waterMl ml nước, còn thiếu $missingWater ml nữa để đạt mục tiêu. Nhớ uống thêm nước nhé!',
        supportingLine: '• $waterMl / $waterTargetMl ml nước',
        primaryLabel: 'Ghi nhận nước',
        secondaryLabel: 'Để sau',
        promptToSend: 'Tôi vừa uống thêm nước, hãy cập nhật nhật ký nước giúp tôi.',
        onPrimary: onPrimary,
        onSecondary: onSecondary,
      );
    }

    return null;
  }
}
