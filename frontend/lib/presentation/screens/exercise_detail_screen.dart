import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/exercise.dart';
import '../tokens/saman_workout_tokens.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
  });

  void _handleVideoPlay(BuildContext context) {
    if (exercise.youtubeVideoId != null &&
        exercise.youtubeVideoId!.isNotEmpty) {
      // In future: play embedded YouTube video
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playing video guide for ${exercise.name}...'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Instructional video is currently being recorded by the coaching staff.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleStartExercise(BuildContext context) {
    // Product Decision Point:
    // Flow requires product confirmation whether "Start exercise" spawns a standalone single-movement
    // session or selects/appends the movement into an existing active workout plan.
    showModalBottomSheet(
      context: context,
      backgroundColor: SamanWorkoutTokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: const Icon(Icons.help_outline,
                      color: SamanWorkoutTokens.emeraldAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Start Exercise Flow Decision',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Starting "${exercise.name}": Awaiting product contract decision on whether this initializes a new session or appends to current active workout routine.',
              style: const TextStyle(
                color: SamanWorkoutTokens.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SamanWorkoutTokens.buttonPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Understood',
                  style: TextStyle(
                    color: SamanWorkoutTokens.buttonPrimaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDumbbellBenchPress =
        exercise.slug.contains('bench-press') || exercise.name.contains('Bench');

    // Taxonomy fields
    final primaryMuscle = exercise.muscleGroup.isNotEmpty
        ? exercise.muscleGroup
        : (exercise.targetMuscles.isNotEmpty
            ? exercise.targetMuscles.first
            : 'Chest');

    final secondaryMuscles = exercise.secondaryMuscles.isNotEmpty
        ? exercise.secondaryMuscles.join(', ')
        : 'Triceps, Shoulders';

    final equipmentStr = exercise.equipment.isNotEmpty
        ? exercise.equipment.join(', ')
        : 'Dumbbells, Flat bench';

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
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
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.cardSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: SamanWorkoutTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Exercise Library',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'CHEST / PUSH',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: SamanWorkoutTokens.textMuted,
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
                  100, // Space for fixed bottom CTA
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. Instructional Video Preview (16:9)
                    _buildVideoPreview(context),
                    const SizedBox(height: SamanWorkoutTokens.spacingLg),

                    // B. Title & Subtitle
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        color: SamanWorkoutTokens.textPrimary,
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
                      style: const TextStyle(
                        color: SamanWorkoutTokens.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: SamanWorkoutTokens.spacingLg),

                    // C. Taxonomy Card
                    _buildTaxonomyCard(
                        primaryMuscle, secondaryMuscles, equipmentStr),
                    const SizedBox(height: SamanWorkoutTokens.spacingXl),

                    // D. How to Perform (3 Phases)
                    _buildHowToPerform(isDumbbellBenchPress),
                    const SizedBox(height: SamanWorkoutTokens.spacingXl),

                    // E. Form Cues
                    _buildFormCues(isDumbbellBenchPress),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // 3. Fixed Bottom Floating CTA Bar
      bottomSheet: Container(
        color: SamanWorkoutTokens.canvas,
        padding: const EdgeInsets.fromLTRB(
          SamanWorkoutTokens.spacingLg,
          0,
          SamanWorkoutTokens.spacingLg,
          20,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => _handleStartExercise(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: SamanWorkoutTokens.buttonPrimary,
              foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
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
    );
  }

  Widget _buildVideoPreview(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo Poster
          CachedNetworkImage(
            imageUrl: exercise.thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(color: SamanWorkoutTokens.surfaceElevated),
            errorWidget: (_, __, ___) => Container(
              color: SamanWorkoutTokens.surfaceElevated,
              child: const Icon(Icons.fitness_center,
                  color: SamanWorkoutTokens.textMuted, size: 48),
            ),
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

          // Top Video Guide Badge
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xD90C0D0E),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: SamanWorkoutTokens.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'VIDEO GUIDE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Central Play Button
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _handleVideoPlay(context),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xD90C0D0E),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.play_arrow,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxonomyCard(
      String primary, String secondary, String equipment) {
    return Container(
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Column(
        children: [
          // Primary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PRIMARY',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.emeraldBadgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: SamanWorkoutTokens.emeraldBadgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: SamanWorkoutTokens.emeraldAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      primary,
                      style: const TextStyle(
                        color: SamanWorkoutTokens.emeraldAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: SamanWorkoutTokens.borderSubtle),
          ),

          // Secondary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SECONDARY',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
              Text(
                secondary,
                style: const TextStyle(
                  color: SamanWorkoutTokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: SamanWorkoutTokens.borderSubtle),
          ),

          // Equipment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EQUIPMENT',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: SamanWorkoutTokens.textMuted,
                ),
              ),
              Text(
                equipment,
                style: const TextStyle(
                  color: SamanWorkoutTokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToPerform(bool isDumbbellBenchPress) {
    final steps = isDumbbellBenchPress
        ? const [
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
          ]
        : (exercise.cues.isNotEmpty
            ? exercise.cues
                .asMap()
                .entries
                .map((e) => (
                      '${e.key + 1}',
                      'Step ${e.key + 1}',
                      e.value,
                    ))
                .toList()
            : const [
                ('1', 'Preparation', 'Position equipment and secure posture.'),
                ('2', 'Execution', 'Perform movement through full range.'),
                ('3', 'Recovery', 'Return to start position with control.'),
              ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'How to perform',
              style: TextStyle(
                color: SamanWorkoutTokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${steps.length} PHASES',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: SamanWorkoutTokens.textMuted,
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
                  color: SamanWorkoutTokens.cardSurface,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  border: Border.all(color: SamanWorkoutTokens.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                        border:
                            Border.all(color: SamanWorkoutTokens.borderSubtle),
                      ),
                      child: Center(
                        child: Text(
                          s.$1,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: SamanWorkoutTokens.textPrimary,
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
                            style: const TextStyle(
                              color: SamanWorkoutTokens.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.$3,
                            style: const TextStyle(
                              color: SamanWorkoutTokens.textSecondary,
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

  Widget _buildFormCues(bool isDumbbellBenchPress) {
    final cues = isDumbbellBenchPress
        ? const [
            'Keep your feet planted',
            'Keep your wrists straight',
            'Move slowly and stay in control',
          ]
        : (exercise.cues.isNotEmpty
            ? exercise.cues.take(3).toList()
            : const [
                'Maintain neutral spinal alignment',
                'Engage core throughout movement',
                'Breathe rhythmically during exertion',
              ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Form cues',
          style: TextStyle(
            color: SamanWorkoutTokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
          decoration: BoxDecoration(
            color: SamanWorkoutTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: SamanWorkoutTokens.border),
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
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: SamanWorkoutTokens.emeraldAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cue,
                          style: const TextStyle(
                            color: SamanWorkoutTokens.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isLast)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                          height: 1, color: SamanWorkoutTokens.borderSubtle),
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
