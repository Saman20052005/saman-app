import 'package:flutter/material.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'onboarding_cta_button.dart';
import 'onboarding_header.dart';
import 'onboarding_tokens.dart';

/// Step 1: Choose Your Goal
class StepGoalView extends StatelessWidget {
  final Goal? selectedGoal;
  final ValueChanged<Goal> onGoalSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final bool isReviewEdit;

  const StepGoalView({
    super.key,
    required this.selectedGoal,
    required this.onGoalSelected,
    required this.onContinue,
    required this.onBack,
    this.isReviewEdit = false,
  });

  @override
  Widget build(BuildContext context) {
    final canContinue = selectedGoal != null;

    return Scaffold(
      backgroundColor: OnboardingTokens.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            // Atmospheric Header Background
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 240,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/onboarding/step1_top_bg.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.topRight,
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
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            OnboardingTokens.canvas.withOpacity(0.9),
                            OnboardingTokens.canvas.withOpacity(0.6),
                            Colors.transparent,
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
                  step: 1,
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
                          'What’s your\nmain goal?',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: OnboardingTokens.textPrimary,
                            height: 1.15,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose what you’d like to focus on.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: OnboardingTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Goal Cards
                        _GoalCard(
                          goal: Goal.lose_weight,
                          title: 'Lose weight',
                          subtitle: 'Work toward a lower body weight.',
                          imageAsset: 'assets/onboarding/goal_lose_weight.jpg',
                          isSelected: selectedGoal == Goal.lose_weight,
                          onTap: () => onGoalSelected(Goal.lose_weight),
                          cardKey: const Key('goal_option_lose_weight'),
                        ),
                        const SizedBox(height: 12),

                        _GoalCard(
                          goal: Goal.maintain_weight,
                          title: 'Maintain weight',
                          subtitle: 'Keep your weight steady.',
                          imageAsset: 'assets/onboarding/goal_maintain_weight.jpg',
                          isSelected: selectedGoal == Goal.maintain_weight,
                          onTap: () => onGoalSelected(Goal.maintain_weight),
                          cardKey: const Key('goal_option_maintain_weight'),
                        ),
                        const SizedBox(height: 12),

                        _GoalCard(
                          goal: Goal.gain_muscle,
                          title: 'Build muscle',
                          subtitle: 'Focus on building muscle.',
                          imageAsset: 'assets/onboarding/goal_build_muscle.jpg',
                          isSelected: selectedGoal == Goal.gain_muscle,
                          onTap: () => onGoalSelected(Goal.gain_muscle),
                          cardKey: const Key('goal_option_gain_muscle'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Bottom CTA
                Padding(
                  padding: const EdgeInsets.all(OnboardingTokens.paddingHorizontal),
                  child: OnboardingCtaButton(
                    label: isReviewEdit ? 'Back to review' : 'Continue',
                    isEnabled: canContinue,
                    onPressed: onContinue,
                    buttonKey: const Key('goal_continue_button'),
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

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final String title;
  final String subtitle;
  final String imageAsset;
  final bool isSelected;
  final VoidCallback onTap;
  final Key cardKey;

  const _GoalCard({
    required this.goal,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
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
          height: 120,
          clipBehavior: Clip.antiAlias,
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
          child: Stack(
            children: [
              // Right side athlete image
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: Opacity(
                        opacity: isSelected ? 0.75 : 0.45,
                        child: Image.asset(
                          imageAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            isSelected
                                ? OnboardingTokens.surfaceSelected
                                : OnboardingTokens.surface,
                            (isSelected
                                    ? OnboardingTokens.surfaceSelected
                                    : OnboardingTokens.surface)
                                .withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Left side text and radio indicator
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : OnboardingTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
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
                    // Custom Radio Circle
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white
                            : OnboardingTokens.surface.withOpacity(0.9),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF525252),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isSelected
                          ? Container(
                              width: 10,
                              height: 10,
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
            ],
          ),
        ),
      ),
    );
  }
}
