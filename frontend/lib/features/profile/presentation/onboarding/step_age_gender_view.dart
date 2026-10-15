import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'biometric_input_parser.dart';
import 'onboarding_cta_button.dart';
import 'onboarding_header.dart';
import 'onboarding_tokens.dart';

/// Step 2: Age and Gender
class StepAgeGenderView extends StatefulWidget {
  final int? initialAge;
  final Gender? initialGender;
  final ValueChanged<int?> onAgeChanged;
  final ValueChanged<Gender> onGenderSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final bool isReviewEdit;

  const StepAgeGenderView({
    super.key,
    required this.initialAge,
    required this.initialGender,
    required this.onAgeChanged,
    required this.onGenderSelected,
    required this.onContinue,
    required this.onBack,
    this.isReviewEdit = false,
  });

  @override
  State<StepAgeGenderView> createState() => _StepAgeGenderViewState();
}

class _StepAgeGenderViewState extends State<StepAgeGenderView> {
  late final TextEditingController _ageController;
  late Gender? _gender;

  @override
  void initState() {
    super.initState();
    _ageController = TextEditingController(
      text: widget.initialAge != null ? widget.initialAge.toString() : '',
    );
    _gender = widget.initialGender;
  }

  @override
  void didUpdateWidget(StepAgeGenderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAge != oldWidget.initialAge &&
        _ageController.text.trim() != (widget.initialAge?.toString() ?? '')) {
      _ageController.text =
          widget.initialAge != null ? widget.initialAge.toString() : '';
    }
    if (widget.initialGender != oldWidget.initialGender) {
      _gender = widget.initialGender;
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  int? get _parsedAge => BiometricInputParser.parseValidAge(_ageController.text);

  bool get _canContinue => _parsedAge != null && _gender != null;

  void _onAgeTextChanged(String text) {
    setState(() {});
    widget.onAgeChanged(BiometricInputParser.parseValidAge(text));
  }

  void _onSelectGender(Gender gender) {
    setState(() {
      _gender = gender;
    });
    widget.onGenderSelected(gender);
  }

  @override
  Widget build(BuildContext context) {
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
                  step: 2,
                  onBack: widget.onBack,
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
                          'A little about you',
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
                          'Enter your age and select your gender.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: OnboardingTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Age Field Module
                        const Text(
                          'AGE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OnboardingTokens.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 72,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: OnboardingTokens.surface,
                            borderRadius:
                                BorderRadius.circular(OnboardingTokens.radiusCard),
                            border: Border.all(color: OnboardingTokens.borderDefault),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('age_input_field'),
                                  controller: _ageController,
                                  onChanged: _onAgeTextChanged,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                    color: OnboardingTokens.textPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                  cursorColor: OnboardingTokens.textPrimary,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Enter your age',
                                    hintStyle: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      color: OnboardingTokens.textDisabled,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              const Text(
                                'YEARS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: OnboardingTokens.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Gender Field Module
                        const Text(
                          'GENDER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OnboardingTokens.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _GenderCard(
                                title: 'Male',
                                icon: Icons.male,
                                isSelected: _gender == Gender.male,
                                onTap: () => _onSelectGender(Gender.male),
                                cardKey: const Key('gender_option_male'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GenderCard(
                                title: 'Female',
                                icon: Icons.female,
                                isSelected: _gender == Gender.female,
                                onTap: () => _onSelectGender(Gender.female),
                                cardKey: const Key('gender_option_female'),
                              ),
                            ),
                          ],
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
                    label: widget.isReviewEdit ? 'Back to review' : 'Continue',
                    isEnabled: _canContinue,
                    onPressed: widget.onContinue,
                    buttonKey: const Key('age_gender_continue_button'),
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

class _GenderCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Key cardKey;

  const _GenderCard({
    required this.title,
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
          height: 110,
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF212328),
                      borderRadius: BorderRadius.circular(OnboardingTokens.radiusTag),
                      border: Border.all(color: OnboardingTokens.borderDefault),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected ? Colors.white : OnboardingTokens.textSecondary,
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.white : const Color(0xFF131417),
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: OnboardingTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
