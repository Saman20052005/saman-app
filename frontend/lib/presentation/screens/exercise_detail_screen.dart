import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/exercise_thumbnail.dart';
import '../providers/exercise_providers.dart';
import '../../data/models/exercise.dart';
import '../tokens/saman_workout_tokens.dart';
import 'active_workout_screen.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
  });


  void _handleStartExercise(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveWorkoutScreen.fromExercises(
        exercises: [exercise],
        title: exercise.name,
      ),
    ));
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SamanWorkoutTokens.of(context);
    final isDumbbellBenchPress =
        exercise.id == 'db-bench-press' || exercise.slug == 'dumbbell-bench-press';

    // Taxonomy fields
    final primaryMuscle = exercise.muscleGroup.isNotEmpty
        ? exercise.muscleGroup
        : (exercise.targetMuscles.isNotEmpty
            ? exercise.targetMuscles.first
            : 'General');

    final secondaryMuscles = exercise.secondaryMuscles.isNotEmpty
        ? exercise.secondaryMuscles.join(', ')
        : 'None';

    final equipmentStr = exercise.equipment.isNotEmpty
        ? exercise.equipment.join(', ')
        : 'Bodyweight';

    return Scaffold(
      key: ValueKey('exercise_detail_${exercise.id}'),
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SamanWorkoutTokens.spacingLg,
                vertical: SamanWorkoutTokens.spacingSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    key: const ValueKey('exercise_detail_back_button'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.cardSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.border),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Exercise Library',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    exercise.muscleGroup.isNotEmpty
                        ? exercise.muscleGroup.toUpperCase()
                        : 'EXERCISE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: t.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Scrollable Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  SamanWorkoutTokens.spacingLg,
                  SamanWorkoutTokens.spacingSm,
                  SamanWorkoutTokens.spacingLg,
                  32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. Instructional Video Preview (16:9)
                    _buildVideoPreview(context, t),
                    const SizedBox(height: SamanWorkoutTokens.spacingLg),

                    // B. Title & Subtitle
                    Text(
                      exercise.name,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDumbbellBenchPress
                          ? 'A chest exercise using dumbbells and a flat bench.'
                          : (exercise.nameVi.isNotEmpty
                              ? exercise.nameVi
                              : 'Instructional movement guidance and cues.'),
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: SamanWorkoutTokens.spacingLg),

                    // C. Taxonomy Card
                    _buildTaxonomyCard(
                        primaryMuscle, secondaryMuscles, equipmentStr, t),
                    const SizedBox(height: SamanWorkoutTokens.spacingXl),

                    // D. How to Perform (3 Phases for Bench Press, readable cues for others)
                    _buildHowToPerform(isDumbbellBenchPress, t),

                    // E. Form Cues (only for benchmark Dumbbell Bench Press)
                    if (isDumbbellBenchPress) ...[
                      const SizedBox(height: SamanWorkoutTokens.spacingXl),
                      _buildFormCues(isDumbbellBenchPress, t),
                    ],

                    // F. Common Mistakes
                    _buildCommonMistakes(isDumbbellBenchPress, t),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // 3. Fixed Bottom Floating CTA Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: t.canvas,
          border: Border(
            top: BorderSide(color: t.border, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SamanWorkoutTokens.spacingLg,
              12,
              SamanWorkoutTokens.spacingLg,
              16,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                key: const ValueKey('exercise_detail_start_button'),
                onPressed: () => _handleStartExercise(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.buttonPrimary,
                  foregroundColor: t.buttonPrimaryText,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Start exercise',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview(BuildContext context, SamanWorkoutPalette t) {
    final previewContent = Container(
      width: double.infinity,
      height: exercisePosterSource(exercise.thumbnailUrl).isEmpty ? 180 : 200,
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExerciseThumbnail(
            source: exercisePosterSource(exercise.thumbnailUrl),
            fit: BoxFit.contain,
            showUnavailableLabel: true,
          ),
          // Gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xB30C0D0E),
                  Colors.transparent,
                  Color(0x4D0C0D0E),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ],
      ),
    );

    return InkWell(
      key: const ValueKey('exercise_detail_video_preview'),
      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video guide for "${exercise.name}" is currently in production and not yet available.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: previewContent,
    );
  }

  Widget _buildTaxonomyCard(String primary, String secondary, String equipment,
      SamanWorkoutPalette t) {
    return Container(
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          // Primary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PRIMARY',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: t.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: t.emeraldBadgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.emeraldBadgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.emeraldAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      primary,
                      style: TextStyle(
                        color: t.emeraldAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: t.borderSubtle),
          ),

          // Secondary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SECONDARY',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: t.textMuted,
                ),
              ),
              Text(
                secondary,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: t.borderSubtle),
          ),

          // Equipment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EQUIPMENT',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: t.textMuted,
                ),
              ),
              Text(
                equipment,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToPerform(bool isDumbbellBenchPress, SamanWorkoutPalette t) {
    if (isDumbbellBenchPress) {
      const steps = [
        (
          '1',
          'Setup',
          'Sit on the bench with a dumbbell in each hand. Lie back and place your feet firmly on the floor.'
        ),
        (
          '2',
          'Lower',
          'Lower the dumbbells slowly to either side of your chest.'
        ),
        (
          '3',
          'Press',
          'Push them up with control until your arms are extended.'
        ),
      ];
      return _renderPhases(steps, t);
    }

    if (exercise.cues.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'How to perform',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${exercise.cues.length} STEPS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: t.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: List.generate(exercise.cues.length, (index) {
              final stepNumber = '${index + 1}';
              final cue = exercise.cues[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
                  decoration: BoxDecoration(
                    color: t.cardSurface,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: t.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.border),
                        ),
                        child: Center(
                          child: Text(
                            stepNumber,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: t.emeraldAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cue,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to perform',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: t.border),
          ),
          child: Text(
            'Movement instructions are being prepared for this exercise.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _renderPhases(
      List<(String, String, String)> steps, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'How to perform',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${steps.length} PHASES',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: t.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Column(
          children: steps.map((s) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
                decoration: BoxDecoration(
                  color: t.cardSurface,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: t.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                        border:
                            Border.all(color: t.borderSubtle),
                      ),
                      child: Center(
                        child: Text(
                          s.$1,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: t.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.$2,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.$3,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFormCues(bool isDumbbellBenchPress, SamanWorkoutPalette t) {
    if (isDumbbellBenchPress) {
      const cues = [
        'Keep your feet planted',
        'Keep your wrists straight',
        'Move slowly and stay in control',
      ];
      return _renderCues(cues, t);
    }

    if (exercise.cues.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Form cues',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
            decoration: BoxDecoration(
              color: t.cardSurface,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              border: Border.all(color: t.border),
            ),
            child: Text(
              'Form cues are being documented for this exercise.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    return _renderCues(exercise.cues, t);
  }

  Widget _renderCues(List<String> cues, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Form cues',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: List.generate(cues.length, (index) {
              final cue = cues[index];
              final isLast = index == cues.length - 1;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: t.emeraldAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cue,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                          height: 1, color: t.borderSubtle),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCommonMistakes(
      bool isDumbbellBenchPress, SamanWorkoutPalette t) {
    if (isDumbbellBenchPress || exercise.commonMistakes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: SamanWorkoutTokens.spacingXl),
        Text(
          'Common mistakes',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: List.generate(exercise.commonMistakes.length, (index) {
              final mistake = exercise.commonMistakes[index];
              final isLast = index == exercise.commonMistakes.length - 1;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.close,
                        size: 16,
                        color: t.isDark ? Colors.redAccent : t.crimsonAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          mistake,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                          height: 1, color: t.borderSubtle),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}
