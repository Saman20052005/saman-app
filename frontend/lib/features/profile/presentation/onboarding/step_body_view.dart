import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'biometric_input_parser.dart';
import 'onboarding_cta_button.dart';
import 'onboarding_header.dart';
import 'onboarding_tokens.dart';

/// Step 3: Body Measurements (Height and Weight)
class StepBodyView extends StatefulWidget {
  final double? initialHeight;
  final double? initialWeight;
  final String? initialRawHeightText;
  final String? initialRawWeightText;
  final void Function(String rawText, double? parsedValue) onHeightChanged;
  final void Function(String rawText, double? parsedValue) onWeightChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final bool isReviewEdit;

  const StepBodyView({
    super.key,
    required this.initialHeight,
    required this.initialWeight,
    this.initialRawHeightText,
    this.initialRawWeightText,
    required this.onHeightChanged,
    required this.onWeightChanged,
    required this.onContinue,
    required this.onBack,
    this.isReviewEdit = false,
  });

  @override
  State<StepBodyView> createState() => _StepBodyViewState();
}

class _StepBodyViewState extends State<StepBodyView> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController(
      text: widget.initialRawHeightText ??
          BiometricInputParser.formatBiometric(widget.initialHeight),
    );
    _weightController = TextEditingController(
      text: widget.initialRawWeightText ??
          BiometricInputParser.formatBiometric(widget.initialWeight),
    );
  }

  @override
  void didUpdateWidget(StepBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRawHeightText != null &&
        widget.initialRawHeightText != oldWidget.initialRawHeightText &&
        _heightController.text != widget.initialRawHeightText) {
      _heightController.text = widget.initialRawHeightText!;
    } else if (widget.initialHeight != oldWidget.initialHeight &&
        _heightController.text.isEmpty &&
        widget.initialHeight != null) {
      _heightController.text =
          BiometricInputParser.formatBiometric(widget.initialHeight);
    }

    if (widget.initialRawWeightText != null &&
        widget.initialRawWeightText != oldWidget.initialRawWeightText &&
        _weightController.text != widget.initialRawWeightText) {
      _weightController.text = widget.initialRawWeightText!;
    } else if (widget.initialWeight != oldWidget.initialWeight &&
        _weightController.text.isEmpty &&
        widget.initialWeight != null) {
      _weightController.text =
          BiometricInputParser.formatBiometric(widget.initialWeight);
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  double? get _parsedHeight =>
      BiometricInputParser.parseValidBiometric(_heightController.text);
  double? get _parsedWeight =>
      BiometricInputParser.parseValidBiometric(_weightController.text);

  bool get _canContinue => _parsedHeight != null && _parsedWeight != null;

  void _onHeightChanged(String text) {
    setState(() {});
    widget.onHeightChanged(text, BiometricInputParser.parseValidBiometric(text));
  }

  void _onWeightChanged(String text) {
    setState(() {});
    widget.onWeightChanged(text, BiometricInputParser.parseValidBiometric(text));
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
                  step: 3,
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
                          'Your body measurements',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: OnboardingTokens.textPrimary,
                            height: 1.15,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your current height and weight.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: OnboardingTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Height Input
                        const Text(
                          'HEIGHT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: OnboardingTokens.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: OnboardingTokens.surface,
                            borderRadius:
                                BorderRadius.circular(OnboardingTokens.radiusCard),
                            border: Border.all(color: OnboardingTokens.borderDefault),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('height_input_field'),
                                  controller: _heightController,
                                  onChanged: _onHeightChanged,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  textAlignVertical: TextAlignVertical.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: OnboardingTokens.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                  cursorColor: OnboardingTokens.textPrimary,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    hintText: 'Enter height',
                                    hintStyle: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: OnboardingTokens.textDisabled,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              const Text(
                                'cm',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: OnboardingTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Weight Input
                        const Text(
                          'WEIGHT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: OnboardingTokens.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: OnboardingTokens.surface,
                            borderRadius:
                                BorderRadius.circular(OnboardingTokens.radiusCard),
                            border: Border.all(color: OnboardingTokens.borderDefault),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('weight_input_field'),
                                  controller: _weightController,
                                  onChanged: _onWeightChanged,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  textAlignVertical: TextAlignVertical.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: OnboardingTokens.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                  cursorColor: OnboardingTokens.textPrimary,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    hintText: 'Enter weight',
                                    hintStyle: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: OnboardingTokens.textDisabled,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              const Text(
                                'kg',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: OnboardingTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
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
                    buttonKey: const Key('body_continue_button'),
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
