import 'package:flutter/material.dart';
import 'onboarding_tokens.dart';

/// Top header for all onboarding steps: Back button, step counter, 5-segment progress bar.
class OnboardingHeader extends StatelessWidget {
  final int step;
  final VoidCallback onBack;

  const OnboardingHeader({
    super.key,
    required this.step,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = OnboardingTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Navigation row
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OnboardingTokens.paddingHorizontal,
            vertical: 8.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('onboarding_back_button'),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(OnboardingTokens.radiusButton),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius:
                          BorderRadius.circular(OnboardingTokens.radiusButton),
                      border: Border.all(color: p.borderDefault),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ),
              // Step counter
              Text(
                'Step $step of 5',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: p.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        // 5-segment progress bar
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OnboardingTokens.paddingHorizontal,
            vertical: 4.0,
          ),
          child: Row(
            children: List.generate(5, (index) {
              final segmentStep = index + 1;
              Color segmentColor;
              if (segmentStep < step) {
                segmentColor = p.progressCompleted;
              } else if (segmentStep == step) {
                segmentColor = p.progressActive;
              } else {
                segmentColor = p.progressUpcoming;
              }

              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 3,
                    right: index == 4 ? 0 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: segmentColor,
                    borderRadius: BorderRadius.circular(OnboardingTokens.radiusProgress),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
