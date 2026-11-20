import 'package:flutter/material.dart';
import 'onboarding_tokens.dart';

/// Primary full-width CTA button for onboarding screens.
class OnboardingCtaButton extends StatelessWidget {
  final String label;
  final bool isEnabled;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  const OnboardingCtaButton({
    super.key,
    required this.label,
    required this.isEnabled,
    this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final p = OnboardingTokens.of(context);
    return Container(
      width: double.infinity,
      height: OnboardingTokens.ctaHeight,
      decoration: BoxDecoration(
        color: isEnabled
            ? p.ctaBackground
            : p.ctaDisabledBg.withOpacity(0.6),
        borderRadius: BorderRadius.circular(OnboardingTokens.radiusButton),
        border: Border.all(
          color: isEnabled
              ? p.ctaBorder
              : p.ctaDisabledBorder,
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey ?? const Key('onboarding_continue_button'),
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(OnboardingTokens.radiusButton),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isEnabled
                        ? p.ctaText
                        : p.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: isEnabled
                      ? p.ctaText
                      : p.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
