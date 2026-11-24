import 'package:flutter/material.dart';
import '../../../../presentation/tokens/saman_workout_tokens.dart';
import '../../domain/services/cv_exercise_guide_data.dart';

/// Displays the camera setup guide, supported angles, and honest 2D AI blind
/// spots for an exercise in a modal bottom sheet.
///
/// Returns `true` when the user confirms/closes via the primary action button.
Future<bool?> showCvExerciseGuideSheet(
  BuildContext context, {
  required String exerciseId,
  required String exerciseSlug,
  String? exerciseName,
  bool isVietnamese = true,
  bool isPreCameraEntry = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => CvExerciseGuideSheet(
      exerciseId: exerciseId,
      exerciseSlug: exerciseSlug,
      exerciseName: exerciseName,
      isVietnamese: isVietnamese,
      isPreCameraEntry: isPreCameraEntry,
    ),
  );
}

/// Bottom sheet presenting camera placement, supported angles (`0° / 30–45° / 90°`),
/// and honest 2D AI blind spots using [SamanWorkoutTokens.of(context)].
class CvExerciseGuideSheet extends StatelessWidget {
  const CvExerciseGuideSheet({
    super.key,
    required this.exerciseId,
    required this.exerciseSlug,
    this.exerciseName,
    this.isVietnamese = true,
    this.isPreCameraEntry = false,
  });

  final String exerciseId;
  final String exerciseSlug;
  final String? exerciseName;
  final bool isVietnamese;
  final bool isPreCameraEntry;

  static const String _fontFamily = 'Manrope';

  @override
  Widget build(BuildContext context) {
    final tokens = SamanWorkoutTokens.of(context);
    final spec = CvExerciseGuideData.forExercise(
      id: exerciseId,
      slug: exerciseSlug,
    );

    final resolvedTitle =
        (exerciseName != null && exerciseName!.trim().isNotEmpty)
            ? exerciseName!.trim()
            : spec.title(isVietnamese);
    final subtitle = isVietnamese
        ? 'Hướng dẫn đặt máy & Lưu ý điểm mù AI 2D'
        : 'Camera Setup & Honest 2D AI Blind Spots';

    final angleWarning = spec.angleWarning(isVietnamese);
    final blindSpots = spec.blindSpots(isVietnamese);
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SamanWorkoutTokens.radiusXl),
            ),
            border: Border(
              top: BorderSide(color: tokens.border),
              left: BorderSide(color: tokens.border),
              right: BorderSide(color: tokens.border),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle + Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SamanWorkoutTokens.spacingXl,
                  SamanWorkoutTokens.spacingMd,
                  SamanWorkoutTokens.spacingXl,
                  SamanWorkoutTokens.spacingMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.borderHover,
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusPill,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: SamanWorkoutTokens.spacingLg),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(
                            SamanWorkoutTokens.spacingSm,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.emeraldBadgeBg,
                            borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusMd,
                            ),
                            border: Border.all(color: tokens.emeraldBadgeBorder),
                          ),
                          child: Icon(
                            Icons.videocam_outlined,
                            color: tokens.emeraldAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: SamanWorkoutTokens.spacingMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resolvedTitle,
                                style: TextStyle(
                                  fontFamily: _fontFamily,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontFamily: _fontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textSecondary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.divider),

              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SamanWorkoutTokens.spacingXl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Part 2: Supported Angles
                      _SectionTitle(
                        title: isVietnamese
                            ? 'Góc quay hỗ trợ'
                            : 'Supported Camera Angles',
                        tokens: tokens,
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingSm),
                      Wrap(
                        spacing: SamanWorkoutTokens.spacingSm,
                        runSpacing: SamanWorkoutTokens.spacingSm,
                        children: spec.supportedAngles
                            .map(
                              (option) => _AngleChip(
                                option: option,
                                isVietnamese: isVietnamese,
                                tokens: tokens,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingMd),
                      Text(
                        spec.bestAngleSummary(isVietnamese),
                        style: TextStyle(
                          fontFamily: _fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: tokens.textSub,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingMd),
                      ...spec.supportedAngles.map(
                        (option) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: SamanWorkoutTokens.spacingSm,
                          ),
                          child: _AngleNoteRow(
                            option: option,
                            isVietnamese: isVietnamese,
                            tokens: tokens,
                          ),
                        ),
                      ),

                      if (angleWarning != null &&
                          angleWarning.trim().isNotEmpty) ...[
                        const SizedBox(height: SamanWorkoutTokens.spacingSm),
                        _AngleWarningBanner(
                          message: angleWarning,
                          tokens: tokens,
                        ),
                      ],

                      const SizedBox(height: SamanWorkoutTokens.spacingLg),

                      // Part 3: Camera Placement & Lighting
                      _SectionTitle(
                        title: isVietnamese
                            ? 'Cách đặt máy & Ánh sáng'
                            : 'Camera Placement & Lighting',
                        tokens: tokens,
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingSm),
                      _InfoCard(
                        icon: Icons.straighten_rounded,
                        iconColor: tokens.tealAccent,
                        title: isVietnamese
                            ? 'Vị trí & Khung hình'
                            : 'Position & Framing',
                        body: spec.cameraPlacement(isVietnamese),
                        tokens: tokens,
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingSm),
                      _InfoCard(
                        icon: Icons.wb_sunny_outlined,
                        iconColor: tokens.amberAccent,
                        title: isVietnamese ? 'Ánh sáng' : 'Lighting',
                        body: spec.lightingTip(isVietnamese),
                        tokens: tokens,
                      ),

                      const SizedBox(height: SamanWorkoutTokens.spacingLg),

                      // Part 4: AI Blind Spots
                      _SectionTitle(
                        title: isVietnamese
                            ? 'Điểm mù AI (Lưu ý trung thực)'
                            : 'AI Blind Spots (Honest Limits)',
                        tokens: tokens,
                      ),
                      const SizedBox(height: SamanWorkoutTokens.spacingSm),
                      Container(
                        padding: const EdgeInsets.all(
                          SamanWorkoutTokens.spacingMd,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusMd,
                          ),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: blindSpots
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: SamanWorkoutTokens.spacingSm,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: tokens.amberAccent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: SamanWorkoutTokens.spacingSm,
                                      ),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: TextStyle(
                                            fontFamily: _fontFamily,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: tokens.textSub,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Part 5: Action Button
              Divider(height: 1, thickness: 1, color: tokens.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SamanWorkoutTokens.spacingXl,
                  SamanWorkoutTokens.spacingMd,
                  SamanWorkoutTokens.spacingXl,
                  SamanWorkoutTokens.spacingLg,
                ),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    key: const ValueKey('cv_exercise_guide_confirm_button'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.buttonPrimary,
                      foregroundColor: tokens.buttonPrimaryText,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                      ),
                    ),
                    child: Text(
                      _confirmButtonLabel,
                      style: const TextStyle(
                        fontFamily: _fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _confirmButtonLabel {
    if (isPreCameraEntry) {
      return isVietnamese ? 'Đã hiểu, tiếp tục' : 'Got it, continue';
    }
    return isVietnamese ? 'Đóng' : 'Close';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.tokens,
  });

  final String title;
  final SamanWorkoutPalette tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: CvExerciseGuideSheet._fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _AngleChip extends StatelessWidget {
  const _AngleChip({
    required this.option,
    required this.isVietnamese,
    required this.tokens,
  });

  final CvAngleOption option;
  final bool isVietnamese;
  final SamanWorkoutPalette tokens;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(option.supportLevel, tokens);
    final isNotRecommended =
        option.supportLevel == CvAngleSupportLevel.notRecommended;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanWorkoutTokens.spacingMd,
        vertical: SamanWorkoutTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusPill),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNotRecommended) ...[
            Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 4),
          ] else if (option.supportLevel == CvAngleSupportLevel.best) ...[
            Icon(
              Icons.check_circle_rounded,
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              option.label(isVietnamese),
              style: TextStyle(
                fontFamily: CvExerciseGuideSheet._fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AngleNoteRow extends StatelessWidget {
  const _AngleNoteRow({
    required this.option,
    required this.isVietnamese,
    required this.tokens,
  });

  final CvAngleOption option;
  final bool isVietnamese;
  final SamanWorkoutPalette tokens;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(option.supportLevel, tokens);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: SamanWorkoutTokens.spacingSm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
          ),
          child: Text(
            option.angleCode,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CvExerciseGuideSheet._fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: SamanWorkoutTokens.spacingSm),
        Expanded(
          child: Text(
            option.note(isVietnamese),
            style: TextStyle(
              fontFamily: CvExerciseGuideSheet._fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: tokens.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _AngleWarningBanner extends StatelessWidget {
  const _AngleWarningBanner({
    required this.message,
    required this.tokens,
  });

  final String message;
  final SamanWorkoutPalette tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: tokens.crimsonAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: tokens.crimsonAccent.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: tokens.crimsonAccent,
            size: 20,
          ),
          const SizedBox(width: SamanWorkoutTokens.spacingSm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: CvExerciseGuideSheet._fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.tokens,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final SamanWorkoutPalette tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: SamanWorkoutTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: CvExerciseGuideSheet._fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontFamily: CvExerciseGuideSheet._fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _accentColor(
  CvAngleSupportLevel level,
  SamanWorkoutPalette tokens,
) {
  switch (level) {
    case CvAngleSupportLevel.best:
      return tokens.emeraldAccent;
    case CvAngleSupportLevel.supported:
      return tokens.tealAccent;
    case CvAngleSupportLevel.notRecommended:
      return tokens.crimsonAccent;
  }
}
