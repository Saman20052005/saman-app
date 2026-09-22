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
}
