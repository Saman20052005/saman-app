import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Data class representing a workout option in the recommendation carousel.
class RecommendedWorkout {
  const RecommendedWorkout({
    required this.id,
    required this.title,
    required this.categoryBadge,
    required this.durationMinutes,
    required this.subtitle,
    required this.imageAssetPath,
    this.weekIndicator,
    this.targetRpe,
    this.exerciseChips = const [],
    this.isPrimary = false,
  });

  final String id;
  final String title;
  final String categoryBadge;
  final int durationMinutes;
  final String subtitle;
  final String imageAssetPath;
  final String? weekIndicator;
  final double? targetRpe;
  final List<String> exerciseChips;
  final bool isPrimary;
}

/// Workout Recommendation Carousel:
/// Snap-swiping horizontal track displaying today's programmed workout
/// and alternative session choices.
///
/// Final visual truth: `design/saman-home/home-screen.png`
class WorkoutRecommendationCarousel extends StatefulWidget {
  const WorkoutRecommendationCarousel({
    super.key,
    this.workouts,
    this.onStartWorkout,
    this.onViewWorkout,
  });

  final List<RecommendedWorkout>? workouts;
  final void Function(RecommendedWorkout workout)? onStartWorkout;
  final void Function(RecommendedWorkout workout)? onViewWorkout;

  @override
  State<WorkoutRecommendationCarousel> createState() =>
      _WorkoutRecommendationCarouselState();
}

class _WorkoutRecommendationCarouselState
    extends State<WorkoutRecommendationCarousel> {
  late final PageController _pageController;

  static const List<RecommendedWorkout> _defaultWorkouts = [
    RecommendedWorkout(
      id: 'leg_day_posterior',
      title: 'Leg Day & Posterior Chain',
      categoryBadge: 'Recommended for today',
      durationMinutes: 45,
      subtitle: '5 compound exercises · Target RPE 8.5',
      weekIndicator: 'Week 2 of 4',
      targetRpe: 8.5,
      exerciseChips: ['Squat (4×8)', 'RDL (3×10)', 'Bulgarian Split'],
      imageAssetPath: 'assets/images/home_hero_leg_day.jpg',
      isPrimary: true,
    ),
    RecommendedWorkout(
      id: 'upper_strength',
      title: 'Upper Strength',
      categoryBadge: 'Program option',
      durationMinutes: 40,
      subtitle: 'Push & Pull',
      imageAssetPath: 'assets/images/home_workout_upper.jpg',
      isPrimary: false,
    ),
    RecommendedWorkout(
      id: 'full_body_express',
      title: 'Full Body Express',
      categoryBadge: 'Time saver',
      durationMinutes: 25,
      subtitle: 'Efficient compound work',
      imageAssetPath: 'assets/images/home_hero_leg_day.jpg',
      isPrimary: false,
    ),
    RecommendedWorkout(
      id: 'active_recovery',
      title: 'Active Recovery',
      categoryBadge: 'Low intensity',
      durationMinutes: 20,
      subtitle: 'Mobility & light conditioning',
      imageAssetPath: 'assets/images/home_workout_upper.jpg',
      isPrimary: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = (widget.workouts != null && widget.workouts!.isNotEmpty)
        ? widget.workouts!
        : _defaultWorkouts;

    return SizedBox(
      height: 290,
      child: PageView.builder(
        controller: _pageController,
        itemCount: list.length,
        itemBuilder: (context, index) {
          final workout = list[index];
          return Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 12,
              bottom: 4,
            ),
            child: _WorkoutHeroCard(
              workout: workout,
              onStartWorkout: () => widget.onStartWorkout?.call(workout),
              onViewWorkout: () => widget.onViewWorkout?.call(workout),
            ),
          );
        },
      ),
    );
  }
}

class _WorkoutHeroCard extends StatelessWidget {
  const _WorkoutHeroCard({
    required this.workout,
    this.onStartWorkout,
    this.onViewWorkout,
  });

  final RecommendedWorkout workout;
  final VoidCallback? onStartWorkout;
  final VoidCallback? onViewWorkout;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXl),
        border: Border.all(
          color: tokens.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Photographic layer with fallback
          Image.asset(
            workout.imageAssetPath,
            fit: BoxFit.cover,
            alignment: const Alignment(0.6, 0.0),
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: SamanHomeTokens.cardSurface,
            ),
          ),

          // 2. Moody local scrim overlays: heavy on left & bottom for contrast, open on right for barbell/lifter
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF0D1013),
                  Color(0xB30D1013), // 70%
                  Colors.transparent,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xF20D1013), // 95%
                  Color(0x990D1013), // 60%
                  Colors.transparent,
                ],
                stops: [0.0, 0.45, 0.85],
              ),
            ),
          ),

          // 3. Card Content
          Padding(
            padding: const EdgeInsets.all(SamanHomeTokens.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: _PillBadge(
                        label: workout.categoryBadge,
                        backgroundColor: const Color(0xE61B2127),
                        textColor: SamanHomeTokens.textPrimary,
                      ),
                    ),
                    if (workout.weekIndicator != null) ...[
                      const SizedBox(width: 8),
                      _PillBadge(
                        label: workout.weekIndicator!,
                        backgroundColor: const Color(0xE61B2127),
                        textColor: SamanHomeTokens.textSecondary,
                        borderRadius: SamanHomeTokens.radiusSm,
                      ),
                    ],
                  ],
                ),

                // Lower section: specs, chips, CTA
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (workout.isPrimary) ...[
                      const Text(
                        'BEST MATCH FOR YOUR RECOVERY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: SamanHomeTokens.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      workout.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: SamanHomeTokens.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${workout.durationMinutes} min · ${workout.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: SamanHomeTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SamanHomeTokens.spacingSm),

                    // Exercise chips (for primary card)
                    if (workout.isPrimary &&
                        workout.exerciseChips.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: workout.exerciseChips.map((chip) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xE61B2127),
                              borderRadius: BorderRadius.circular(
                                SamanHomeTokens.radiusXs,
                              ),
                              border: Border.all(
                                color: SamanHomeTokens.border,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              chip,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: SamanHomeTokens.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: SamanHomeTokens.spacingSm),
                    ],

                    // Primary Action Button: Mint #54DFAC background, dark graphite #092018 text and icon
                    if (workout.isPrimary)
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton(
                          onPressed: onStartWorkout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SamanHomeTokens.mintAccent,
                            foregroundColor: SamanHomeTokens.mintCtaText,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                SamanHomeTokens.radiusMd,
                              ),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                                color: SamanHomeTokens.mintCtaText,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Start Workout →',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  color: SamanHomeTokens.mintCtaText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onViewWorkout,
                          borderRadius: BorderRadius.circular(
                            SamanHomeTokens.radiusSm,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View workout',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: SamanHomeTokens.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: SamanHomeTokens.textPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderRadius,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          borderRadius ?? SamanHomeTokens.radiusPill,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
