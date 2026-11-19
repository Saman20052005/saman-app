import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';

/// Available coaching personas for Saman Coach.
enum CoachPersona {
  strictPt(
    id: 'strict_pt',
    displayName: 'Strict PT',
    vietnameseTitle: 'Strict PT (Kỷ luật)',
    emoji: '🏋️‍♂️',
    icon: Icons.fitness_center_rounded,
    shortDescription: 'Disciplined, performance-focused, no excuses.',
    vietnameseDesc: 'Kỷ luật cao, tập trung hiệu suất, không thỏa hiệp.',
    prompt: '''From now on, act as a STRICT Personal Trainer.
Be disciplined, direct, and performance-oriented.
Use firm and commanding language.
Do not accept excuses, laziness, or shortcuts.
Focus only on actions, consistency, and measurable results.
Avoid emotional encouragement; enforce accountability.''',
  ),
  nutritionDoctor(
    id: 'nutrition_doctor',
    displayName: 'Nutrition Doctor',
    vietnameseTitle: 'Nutrition Doctor (Bác sĩ dinh dưỡng)',
    emoji: '👩‍⚕️',
    icon: Icons.health_and_safety_rounded,
    shortDescription: 'Scientific, calm, and explanatory.',
    vietnameseDesc: 'Khoa học, điềm tĩnh và giải thích chuyên sâu.',
    prompt: '''From now on, act as a Nutrition Specialist.
Base all advice strictly on scientific and evidence-based principles.
Use a calm, gentle, and professional tone.
Explain concepts clearly and logically when needed.
Prioritize health, safety, and long-term sustainability.
Avoid harsh or pressuring language.''',
  ),
  supportiveCoach(
    id: 'supportive_coach',
    displayName: 'Supportive Coach',
    vietnameseTitle: 'Supportive Coach (Đồng hành)',
    emoji: '🤝',
    icon: Icons.sentiment_satisfied_alt_rounded,
    shortDescription: 'Friendly, supportive, and motivating.',
    vietnameseDesc: 'Thân thiện, đồng cảm và truyền cảm hứng.',
    prompt: '''From now on, act as a supportive personal coach.
Use a friendly, casual, and positive tone.
Be empathetic and encouraging.
Keep the conversation light and engaging.
Motivate through emotional support rather than strict discipline.''',
  );

  const CoachPersona({
    required this.id,
    required this.displayName,
    required this.vietnameseTitle,
    required this.emoji,
    required this.icon,
    required this.shortDescription,
    required this.vietnameseDesc,
    required this.prompt,
  });

  final String id;
  final String displayName;
  final String vietnameseTitle;
  final String emoji;
  final IconData icon;
  final String shortDescription;
  final String vietnameseDesc;
  final String prompt;

  static CoachPersona fromId(String? id) {
    if (id == null) return CoachPersona.supportiveCoach;
    return CoachPersona.values.firstWhere(
      (p) => p.id == id,
      orElse: () => CoachPersona.supportiveCoach,
    );
  }
}

class CoachPersonaState {
  final CoachPersona persona;
  final bool isSaving;
  final String? errorMessage;

  const CoachPersonaState({
    required this.persona,
    this.isSaving = false,
    this.errorMessage,
  });

  CoachPersonaState copyWith({
    CoachPersona? persona,
    bool? isSaving,
    String? errorMessage,
  }) {
    return CoachPersonaState(
      persona: persona ?? this.persona,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
    );
  }
}

class CoachPersonaNotifier extends StateNotifier<CoachPersonaState> {
  CoachPersonaNotifier([CoachPersona initial = CoachPersona.supportiveCoach])
      : super(CoachPersonaState(persona: initial));

  Future<bool> selectPersona(
    CoachPersona persona, {
    Future<void> Function(String prompt)? onSendPrompt,
  }) async {
    if (state.isSaving) return false;

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      if (onSendPrompt != null) {
        await onSendPrompt(persona.prompt);
      }

      state = CoachPersonaState(persona: persona, isSaving: false);

      // Persist to user preferences via ApiClient in background
      Future.microtask(() async {
        try {
          await ApiClient.dio.put(
            '/api/user/update-profile',
            data: {
              'preferences': {
                'coach_persona': persona.id,
                'reply_style': persona.id,
              }
            },
          );
        } catch (_) {
          // Non-blocking for local offline mock
        }
      });

      return true;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Không thể cập nhật phong cách. Vui lòng thử lại sau.',
      );
      return false;
    }
  }

  void setPersona(CoachPersona persona) {
    state = state.copyWith(persona: persona, isSaving: false);
  }

  void syncFromPreferences(Map<String, dynamic>? prefs) {
    final raw = prefs?['coach_persona'] ?? prefs?['reply_style'];
    if (raw == null) return;
    final id = raw.toString().trim();
    if (id.isEmpty) return;
    final matched = CoachPersona.fromId(id);
    if (matched != state.persona) {
      state = state.copyWith(persona: matched, isSaving: false);
    }
  }
}

final coachPersonaProvider =
    StateNotifierProvider<CoachPersonaNotifier, CoachPersonaState>((ref) {
  return CoachPersonaNotifier();
});
