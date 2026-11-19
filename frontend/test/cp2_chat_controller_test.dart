import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/providers/coach_persona_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CP-2 Chat Controller & Coach Persona Upgrade Tests', () {
    test('ChatController.setAIMode updates state.selectedAIMode to swift3 and pro3', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);

      // Default initial mode should be core3
      expect(container.read(chatControllerProvider).selectedAIMode, AIMode.core3);

      // Transition to swift3
      controller.setAIMode(AIMode.swift3);
      expect(container.read(chatControllerProvider).selectedAIMode, AIMode.swift3);

      // Transition to pro3
      controller.setAIMode(AIMode.pro3);
      expect(container.read(chatControllerProvider).selectedAIMode, AIMode.pro3);

      // Transition back to core3
      controller.setAIMode(AIMode.core3);
      expect(container.read(chatControllerProvider).selectedAIMode, AIMode.core3);
    });

    test('CoachPersonaNotifier.syncFromPreferences synchronizes coach_persona and reply_style', () {
      final notifier = CoachPersonaNotifier();

      // Initial default persona
      expect(notifier.state.persona, CoachPersona.supportiveCoach);

      // Sync via coach_persona key
      notifier.syncFromPreferences({'coach_persona': 'strict_pt'});
      expect(notifier.state.persona, CoachPersona.strictPt);

      // Sync via reply_style key
      notifier.syncFromPreferences({'reply_style': 'nutrition_doctor'});
      expect(notifier.state.persona, CoachPersona.nutritionDoctor);

      // Sync with both keys prefers coach_persona
      notifier.syncFromPreferences({
        'coach_persona': 'supportive_coach',
        'reply_style': 'strict_pt',
      });
      expect(notifier.state.persona, CoachPersona.supportiveCoach);

      // Gracefully handles empty or null preferences
      notifier.syncFromPreferences(null);
      expect(notifier.state.persona, CoachPersona.supportiveCoach);

      notifier.syncFromPreferences({});
      expect(notifier.state.persona, CoachPersona.supportiveCoach);
    });
  });
}
