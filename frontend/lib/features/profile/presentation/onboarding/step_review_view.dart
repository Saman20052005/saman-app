import 'package:flutter/material.dart';
import 'package:health_ai_app/features/profile/domain/entities/onboarding_activity_choice.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'biometric_input_parser.dart';
import 'onboarding_cta_button.dart';
import 'onboarding_header.dart';
import 'onboarding_tokens.dart';

/// Step 5: Review & Confirm
class StepReviewView extends StatelessWidget {
  final Goal? goal;
  final int? age;
  final Gender? gender;
  final double? height;
  final double? weight;
  final String? rawHeightText;
  final String? rawWeightText;
  final OnboardingActivityChoice? activityChoice;
  final VoidCallback onEditGoal;
  final VoidCallback onEditAbout;
  final VoidCallback onEditBody;
  final VoidCallback onEditActivity;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  final bool isSaving;
  final String? errorMessage;
  final bool isReadbackError;
  final bool isTimeoutUnknown;
  final bool isConflict;
  final bool isIdentityMismatch;
  final VoidCallback? onCheckAgain;
  final VoidCallback? onReconcile;
  final VoidCallback? onReload;
  final VoidCallback? onLogout;

  const StepReviewView({
    super.key,
    required this.goal,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    this.rawHeightText,
    this.rawWeightText,
    required this.activityChoice,
    required this.onEditGoal,
    required this.onEditAbout,
    required this.onEditBody,
    required this.onEditActivity,
    required this.onConfirm,
    required this.onBack,
    this.isSaving = false,
    this.errorMessage,
    this.isReadbackError = false,
    this.isTimeoutUnknown = false,
    this.isConflict = false,
    this.isIdentityMismatch = false,
    this.onCheckAgain,
    this.onReconcile,
    this.onReload,
    this.onLogout,
  });

  bool get _canEdit =>
      !isSaving &&
      !isReadbackError &&
      !isTimeoutUnknown &&
      !isIdentityMismatch;

  bool get _isAllValid {
    return goal != null &&
        age != null &&
        age! >= 13 &&
        age! <= 120 &&
        gender != null &&
        height != null &&
        height! > 0 &&
        height!.isFinite &&
        weight != null &&
        weight! > 0 &&
        weight!.isFinite &&
        activityChoice != null;
  }

  String _goalTitle(Goal? g) {
    switch (g) {
      case Goal.lose_weight:
        return 'Lose weight';
      case Goal.maintain_weight:
        return 'Maintain weight';
      case Goal.gain_muscle:
        return 'Build muscle';
      case null:
        return 'Not selected';
    }
  }

  String _goalSubtitle(Goal? g) {
    switch (g) {
      case Goal.lose_weight:
        return 'Work toward a lower body weight.';
      case Goal.maintain_weight:
        return 'Keep your weight steady.';
      case Goal.gain_muscle:
        return 'Focus on building muscle.';
      case null:
        return 'Please choose your goal.';
    }
  }

  String _goalImageAsset(Goal? g) {
    switch (g) {
      case Goal.lose_weight:
        return 'assets/onboarding/goal_lose_weight.jpg';
      case Goal.maintain_weight:
        return 'assets/onboarding/goal_maintain_weight.jpg';
      case Goal.gain_muscle:
      case null:
        return 'assets/onboarding/goal_build_muscle.jpg';
    }
  }

  String _genderText(Gender? g) {
    switch (g) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
      case null:
        return 'Not selected';
    }
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
                  step: 5,
                  onBack: _canEdit ? onBack : () {},
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
                          'Take a final look',
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
                          'Check your details before you continue.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: OnboardingTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 1. YOUR GOAL CARD
                        _ReviewCardContainer(
                          child: Stack(
                            children: [
                              // Right side image crop
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: 0,
                                width: 140,
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
                                        opacity: 0.45,
                                        child: Image.asset(
                                          _goalImageAsset(goal),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox(),
                                        ),
                                      ),
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            OnboardingTokens.surface,
                                            OnboardingTokens.surface
                                                .withOpacity(0.6),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'YOUR GOAL',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: OnboardingTokens.textSecondary,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        _EditButton(
                                          buttonKey:
                                              const Key('review_edit_goal'),
                                          onPressed: onEditGoal,
                                          isEnabled: _canEdit,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _goalTitle(goal),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: OnboardingTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _goalSubtitle(goal),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: OnboardingTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. ABOUT YOU CARD
                        _ReviewCardContainer(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'ABOUT YOU',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: OnboardingTokens.textSecondary,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    _EditButton(
                                      buttonKey: const Key('review_edit_about'),
                                      onPressed: onEditAbout,
                                      isEnabled: _canEdit,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _DataRow(
                                  label: 'Age',
                                  value: age != null ? '$age years' : '—',
                                ),
                                const Divider(
                                  color: OnboardingTokens.divider,
                                  height: 16,
                                ),
                                _DataRow(
                                  label: 'Gender',
                                  value: _genderText(gender),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 3. BODY MEASUREMENTS CARD
                        _ReviewCardContainer(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'BODY MEASUREMENTS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: OnboardingTokens.textSecondary,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    _EditButton(
                                      buttonKey: const Key('review_edit_body'),
                                      onPressed: onEditBody,
                                      isEnabled: _canEdit,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _DataRow(
                                  label: 'Height',
                                  value: height != null
                                      ? '${BiometricInputParser.formatBiometric(height, rawText: rawHeightText)} cm'
                                      : '—',
                                ),
                                const Divider(
                                  color: OnboardingTokens.divider,
                                  height: 16,
                                ),
                                _DataRow(
                                  label: 'Weight',
                                  value: weight != null
                                      ? '${BiometricInputParser.formatBiometric(weight, rawText: rawWeightText)} kg'
                                      : '—',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 4. ACTIVITY LEVEL CARD
                        _ReviewCardContainer(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'ACTIVITY LEVEL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: OnboardingTokens.textSecondary,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    _EditButton(
                                      buttonKey:
                                          const Key('review_edit_activity'),
                                      onPressed: onEditActivity,
                                      isEnabled: _canEdit,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  activityChoice?.title ?? 'Not selected',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: OnboardingTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activityChoice?.subtitle ??
                                      'Please choose your activity level.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: OnboardingTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
                          Container(
                            key: const Key('onboarding_save_error_banner'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C1E21),
                              borderRadius: BorderRadius.circular(
                                  OnboardingTokens.radiusCard),
                              border: Border.all(color: const Color(0xFFE57373)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.error_outline,
                                          size: 16, color: Color(0xFFE57373)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        errorMessage!,
                                        style: const TextStyle(
                                          color: Color(0xFFFFCDD2),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isReadbackError && onCheckAgain != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      key: const Key(
                                          'onboarding_check_again_button'),
                                      onPressed: onCheckAgain,
                                      icon: const Icon(Icons.refresh,
                                          size: 16, color: Colors.white),
                                      label: const Text('Kiểm tra lại',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            OnboardingTokens.ctaBackground,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                      ),
                                    ),
                                  ),
                                ] else if (isTimeoutUnknown &&
                                    onReconcile != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      key: const Key(
                                          'onboarding_check_status_button'),
                                      onPressed: onReconcile,
                                      icon: const Icon(Icons.sync,
                                          size: 16, color: Colors.white),
                                      label: const Text('Kiểm tra trạng thái',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            OnboardingTokens.ctaBackground,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                      ),
                                    ),
                                  ),
                                ] else if (isConflict && onReload != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      key: const Key(
                                          'onboarding_reload_profile_button'),
                                      onPressed: onReload,
                                      icon: const Icon(Icons.refresh,
                                          size: 16, color: Colors.white),
                                      label: const Text('Tải lại hồ sơ',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            OnboardingTokens.ctaBackground,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                      ),
                                    ),
                                  ),
                                ] else if (isIdentityMismatch && onLogout != null) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      key: const Key(
                                          'onboarding_logout_button'),
                                      onPressed: onLogout,
                                      icon: const Icon(Icons.logout,
                                          size: 16, color: Colors.white),
                                      label: const Text('Đăng xuất',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            OnboardingTokens.ctaBackground,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // Bottom Action CTA: Confirm and start
                Padding(
                  padding: const EdgeInsets.all(
                      OnboardingTokens.paddingHorizontal),
                  child: isSaving
                      ? Container(
                          key: const Key('onboarding_confirm_loading'),
                          height: OnboardingTokens.ctaHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: OnboardingTokens.ctaDisabledBg
                                .withOpacity(0.6),
                            borderRadius: BorderRadius.circular(
                                OnboardingTokens.radiusButton),
                            border: Border.all(
                                color: OnboardingTokens.ctaDisabledBorder),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      OnboardingTokens.textPrimary),
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Đang lưu...',
                                style: TextStyle(
                                  color: OnboardingTokens.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : OnboardingCtaButton(
                          label: 'Confirm and start',
                          isEnabled: _isAllValid && !isSaving && !isReadbackError && !isTimeoutUnknown && !isIdentityMismatch,
                          onPressed: onConfirm,
                          buttonKey: const Key('onboarding_confirm_button'),
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

class _ReviewCardContainer extends StatelessWidget {
  final Widget child;

  const _ReviewCardContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OnboardingTokens.surface,
        borderRadius: BorderRadius.circular(OnboardingTokens.radiusCard),
        border: Border.all(color: OnboardingTokens.borderDefault),
      ),
      child: child,
    );
  }
}

class _EditButton extends StatelessWidget {
  final Key buttonKey;
  final VoidCallback onPressed;
  final bool isEnabled;

  const _EditButton({
    required this.buttonKey,
    required this.onPressed,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: buttonKey,
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(OnboardingTokens.radiusTag),
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF212328),
              borderRadius: BorderRadius.circular(OnboardingTokens.radiusTag),
              border: Border.all(color: OnboardingTokens.borderDefault),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: OnboardingTokens.textPrimary,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 12,
                  color: OnboardingTokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;

  const _DataRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: OnboardingTokens.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: OnboardingTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
