import 'package:flutter/material.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'onboarding_cta_button.dart';
import 'onboarding_header.dart';
import 'onboarding_tokens.dart';

/// Step 4: Activity Level (5 Distinct Choices)
class StepActivityView extends StatelessWidget {
  final OnboardingActivityChoice? selectedChoice;
  final ValueChanged<OnboardingActivityChoice> onChoiceSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final bool isReviewEdit;

  const StepActivityView({
    super.key,
    required this.selectedChoice,
    required this.onChoiceSelected,
    required this.onContinue,
    required this.onBack,
    this.isReviewEdit = false,
  });

  @override
  Widget build(BuildContext context) {
    final canContinue = selectedChoice != null;

    return Scaffold(
      backgroundColor: OnboardingTokens.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            // Atmospheric Gym Background (Upper-Right)
            Positioned(
              top: 0,
              right: 0,
              width: 260,
              height: 230,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/onboarding/bg_athlete.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            OnboardingTokens.canvas.withOpacity(0.3),
                            OnboardingTokens.canvas.withOpacity(0.7),
                            OnboardingTokens.canvas,
                          ],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Colors.transparent,
                            OnboardingTokens.canvas.withOpacity(0.6),
                            OnboardingTokens.canvas,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Main Content Stack
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingHeader(
                  step: 4,
                  onBack: onBack,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnboardingTokens.paddingHorizontal,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'How active is your usual week?',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: OnboardingTokens.textPrimary,
                            height: 1.15,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Think about your daily movement as well as exercise.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: OnboardingTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 5 Activity Choices
                        _ActivityCard(
                          choice: OnboardingActivityChoice.sedentary,
                          icon: Icons.chair_outlined,
                          isSelected:
                              selectedChoice == OnboardingActivityChoice.sedentary,
                          onTap: () =>
                              onChoiceSelected(OnboardingActivityChoice.sedentary),
                          cardKey: const Key('activity_option_sedentary'),
                        ),
                        const SizedBox(height: 10),

                        _ActivityCard(
                          choice: OnboardingActivityChoice.light,
                          icon: Icons.directions_walk,
                          isSelected:
                              selectedChoice == OnboardingActivityChoice.light,
                          onTap: () =>
                              onChoiceSelected(OnboardingActivityChoice.light),
                          cardKey: const Key('activity_option_light'),
                        ),
                        const SizedBox(height: 10),

                        _ActivityCard(
                          choice: OnboardingActivityChoice.moderate,
                          icon: Icons.fitness_center,
                          isSelected:
                              selectedChoice == OnboardingActivityChoice.moderate,
                          onTap: () =>
                              onChoiceSelected(OnboardingActivityChoice.moderate),
                          cardKey: const Key('activity_option_moderate'),
                        ),
                        const SizedBox(height: 10),

                        _ActivityCard(
                          choice: OnboardingActivityChoice.active,
                          icon: Icons.directions_run,
                          isSelected:
                              selectedChoice == OnboardingActivityChoice.active,
                          onTap: () =>
                              onChoiceSelected(OnboardingActivityChoice.active),
                          cardKey: const Key('activity_option_active'),
                        ),
                        const SizedBox(height: 10),

                        _ActivityCard(
                          choice: OnboardingActivityChoice.very_active,
                          icon: Icons.bolt,
                          isSelected: selectedChoice ==
                              OnboardingActivityChoice.very_active,
                          onTap: () => onChoiceSelected(
                              OnboardingActivityChoice.very_active),
                          cardKey: const Key('activity_option_very_active'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Bottom Action CTA
                Padding(
                  padding: const EdgeInsets.all(OnboardingTokens.paddingHorizontal),
                  child: OnboardingCtaButton(
                    label: isReviewEdit ? 'Back to review' : 'Continue',
                    isEnabled: canContinue,
                    onPressed: onContinue,
                    buttonKey: const Key('activity_continue_button'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final OnboardingActivityChoice choice;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Key cardKey;

  const _ActivityCard({
    required this.choice,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: cardKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(OnboardingTokens.radiusCard),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? OnboardingTokens.surfaceSelected
                : OnboardingTokens.surface,
            borderRadius: BorderRadius.circular(OnboardingTokens.radiusCard),
            border: Border.all(
              color: isSelected
                  ? OnboardingTokens.borderSelected
                  : OnboardingTokens.borderDefault,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF212328),
                  borderRadius: BorderRadius.circular(OnboardingTokens.radiusButton),
                  border: Border.all(color: OnboardingTokens.borderDefault),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : OnboardingTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      choice.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : OnboardingTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      choice.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: OnboardingTokens.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.white : const Color(0xFF131417),
                  border: Border.all(
                    color: isSelected ? Colors.white : const Color(0xFF525252),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: OnboardingTokens.canvas,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
