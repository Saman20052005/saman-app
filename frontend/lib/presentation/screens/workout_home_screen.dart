import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/workout_home_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import 'exercise_library_screen.dart';
import 'my_plans_screen.dart';
import 'workout_history_screen.dart';

class WorkoutHomeScreen extends ConsumerStatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  ConsumerState<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends ConsumerState<WorkoutHomeScreen> {
  void _navigateToLibrary([String category = 'All']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseLibraryScreen(initialCategory: category),
      ),
    );
  }

  void _navigateToMyPlans() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyPlansScreen()),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()),
    );
  }

  void _handleStartWorkout(ScheduledSessionInfo scheduled) {
    // Show confirmation / status notification regarding active workout contract
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting scheduled session: ${scheduled.title}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleQuickStart() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quick start: session initialized without a plan.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = ref.watch(scheduledWorkoutProvider);
    final upcomingPlans = ref.watch(upcomingPlansProvider);
    final recentWorkout = ref.watch(recentWorkoutSummaryProvider);

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingSm,
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingXxl * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // 2. Today's Scheduled Session Hero Card
              _buildScheduledSessionHero(scheduled),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // 3. Quick Action Row
              _buildQuickActionRow(),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 4. Train by Focus
              _buildTrainByFocus(),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 5. Your Plan
              _buildYourPlan(upcomingPlans),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 6. Last Workout
              if (recentWorkout != null) _buildLastWorkout(recentWorkout),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Workout',
              style: TextStyle(
                color: SamanWorkoutTokens.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Train, log & explore movements',
              style: TextStyle(
                color: SamanWorkoutTokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        InkWell(
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
          onTap: _navigateToMyPlans,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: SamanWorkoutTokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              border: Border.all(color: SamanWorkoutTokens.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_border,
                  size: 16,
                  color: SamanWorkoutTokens.emeraldAccent,
                ),
                SizedBox(width: 6),
                Text(
                  'My Plans',
                  style: TextStyle(
                    color: SamanWorkoutTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduledSessionHero(ScheduledSessionInfo session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category eyebrow + Planned pill
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TODAY’S SCHEDULED SESSION',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: SamanWorkoutTokens.textMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.emeraldBadgeBg,
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                border: Border.all(color: SamanWorkoutTokens.emeraldBadgeBorder),
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
                  const SizedBox(width: 5),
                  Text(
                    session.status,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: SamanWorkoutTokens.emeraldAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Hero Card Box
        Container(
          height: 290,
          decoration: BoxDecoration(
            color: SamanWorkoutTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: SamanWorkoutTokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo asset
              CachedNetworkImage(
                imageUrl: session.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: SamanWorkoutTokens.surfaceElevated,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: SamanWorkoutTokens.surfaceElevated,
                  child: const Center(
                    child: Icon(Icons.fitness_center,
                        color: SamanWorkoutTokens.textMuted, size: 48),
                  ),
                ),
              ),

              // Gradient Overlay (Calm obsidian fade)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF0C0D0E),
                      Color(0x990C0D0E),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
              ),

              // Content overlay
              Padding(
                padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Protocol badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.emeraldBadgeBg,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                        border: Border.all(
                            color: SamanWorkoutTokens.emeraldBadgeBorder),
                      ),
                      child: Text(
                        session.protocol.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: SamanWorkoutTokens.emeraldAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Session title
                    Text(
                      session.title,
                      style: const TextStyle(
                        color: SamanWorkoutTokens.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Metrics
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: SamanWorkoutTokens.textSub),
                        const SizedBox(width: 4),
                        Text(
                          '${session.durationMinutes} min',
                          style: const TextStyle(
                            color: SamanWorkoutTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('•',
                            style: TextStyle(
                                color: SamanWorkoutTokens.textSecondary)),
                        const SizedBox(width: 8),
                        const Icon(Icons.fitness_center,
                            size: 16, color: SamanWorkoutTokens.textSub),
                        const SizedBox(width: 4),
                        Text(
                          '${session.exerciseCount} exercises',
                          style: const TextStyle(
                            color: SamanWorkoutTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // CTAs: Start workout + View plan
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: () => _handleStartWorkout(session),
                              icon: const Icon(Icons.play_arrow,
                                  size: 18,
                                  color: SamanWorkoutTokens.buttonPrimaryText),
                              label: const Text(
                                'Start workout',
                                style: TextStyle(
                                  color: SamanWorkoutTokens.buttonPrimaryText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    SamanWorkoutTokens.buttonPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      SamanWorkoutTokens.radiusMd),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _navigateToMyPlans,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xCC212328),
                              side: const BorderSide(
                                  color: SamanWorkoutTokens.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    SamanWorkoutTokens.radiusMd),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Text(
                                  'View plan',
                                  style: TextStyle(
                                    color: SamanWorkoutTokens.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward,
                                    size: 14,
                                    color: SamanWorkoutTokens.textSecondary),
                              ],
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
        ),
      ],
    );
  }

  Widget _buildQuickActionRow() {
    return Row(
      children: [
        // Quick start
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: _handleQuickStart,
            child: Container(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.cardSurface,
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: SamanWorkoutTokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.surfaceElevated,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                          border: Border.all(color: SamanWorkoutTokens.border),
                        ),
                        child: const Icon(Icons.bolt,
                            size: 18, color: SamanWorkoutTokens.textPrimary),
                      ),
                      const Icon(Icons.arrow_forward,
                          size: 16, color: SamanWorkoutTokens.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Quick start',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Train without a plan',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Browse library
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: () => _navigateToLibrary('All'),
            child: Container(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.cardSurface,
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: SamanWorkoutTokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.surfaceElevated,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                          border: Border.all(color: SamanWorkoutTokens.border),
                        ),
                        child: const Icon(Icons.search,
                            size: 18, color: SamanWorkoutTokens.textPrimary),
                      ),
                      const Icon(Icons.arrow_forward,
                          size: 16, color: SamanWorkoutTokens.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Browse library',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Explore exercises',
                    style: TextStyle(
                      color: SamanWorkoutTokens.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrainByFocus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'TRAIN BY FOCUS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: SamanWorkoutTokens.textMuted,
              ),
            ),
            InkWell(
              onTap: () => _navigateToLibrary('All'),
              child: const Row(
                children: [
                  Text(
                    'All categories',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: SamanWorkoutTokens.emeraldAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_forward,
                      size: 14, color: SamanWorkoutTokens.emeraldAccent),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            // Upper Body Card
            Expanded(
              child: _FocusCategoryCard(
                title: 'Upper Body',
                subtitle: 'Chest, Back, Arms',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuCcanzIWbwr1wbgiYXZhgMavpn31gfEXKJTTVhG3mquc-uBH5EnvXNlZEn2tvJa2509Y8AAV8q2yKYpkns0qwUEZVDus2qc9VFylQ516_Hq1Mjl3KEiDeoevmknk51V83Mnpg6vtV74d533hkcOjlve55QtOPZXnvoFLwuQHbrJ-ZrJ1yV7bhiMrP4NA4ZRiUfuZaL7PA4zC5YPbomD8A-Ex10M9ou1Vzeei3-VoXwV4ZfCgbyY7Cd1',
                onTap: () => _navigateToLibrary('Upper Body'),
              ),
            ),
            const SizedBox(width: 10),

            // Lower Body Card
            Expanded(
              child: _FocusCategoryCard(
                title: 'Lower Body',
                subtitle: 'Quads, Glutes, Legs',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDrTlcWy4Im6QZihMwXHDm8qtDNHF9aIfXlkMfDMPbeSt3SEKpZcylKb8fHhO-FC5-uhmsT1lkJ5MspMUMssZKfj30ijhcVK7-Hg442bihGVzYUXiUotr-0XXGOUVx8VgQwldxSdTC3AminLzNQoU7ADaat_E3-9J15gY6qjXK6Pdui0DpighlW3JIihc7bFOOPWbs4T_LencKQ4KVQ_EBli7Xb9AEe0uh-ps9srVpebEFbeu-xJUFB',
                onTap: () => _navigateToLibrary('Lower Body'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildYourPlan(List<UpcomingPlanSession> upcoming) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'YOUR PLAN',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: SamanWorkoutTokens.textMuted,
              ),
            ),
            InkWell(
              onTap: _navigateToMyPlans,
              child: const Row(
                children: [
                  Text(
                    'View full plan',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 14, color: SamanWorkoutTokens.textSecondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: SamanWorkoutTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: SamanWorkoutTokens.border),
          ),
          child: Column(
            children: List.generate(upcoming.length, (index) {
              final item = upcoming[index];
              final isLast = index == upcoming.length - 1;

              return Container(
                padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: SamanWorkoutTokens.border),
                        ),
                ),
                child: Row(
                  children: [
                    // Calendar square
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.dayName.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: SamanWorkoutTokens.textSub,
                            ),
                          ),
                          Text(
                            item.dayNumber,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: SamanWorkoutTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Titles & metrics
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: SamanWorkoutTokens.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.isRest
                                      ? SamanWorkoutTokens.surfaceElevated
                                      : SamanWorkoutTokens.emeraldBadgeBg,
                                  borderRadius: BorderRadius.circular(
                                      SamanWorkoutTokens.radiusXs),
                                  border: Border.all(
                                    color: item.isRest
                                        ? SamanWorkoutTokens.borderSubtle
                                        : SamanWorkoutTokens.emeraldBadgeBorder,
                                  ),
                                ),
                                child: Text(
                                  item.badge,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: item.isRest
                                        ? SamanWorkoutTokens.textSub
                                        : SamanWorkoutTokens.emeraldAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.metrics,
                            style: const TextStyle(
                              color: SamanWorkoutTokens.textSub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildLastWorkout(RecentWorkoutSummary recent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LAST WORKOUT',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: SamanWorkoutTokens.textMuted,
              ),
            ),
            InkWell(
              onTap: _navigateToHistory,
              child: const Row(
                children: [
                  Text(
                    'View history',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 14, color: SamanWorkoutTokens.textSecondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        InkWell(
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
          onTap: _navigateToHistory,
          child: Container(
            padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
            decoration: BoxDecoration(
              color: SamanWorkoutTokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
              border: Border.all(color: SamanWorkoutTokens.border),
            ),
            child: Row(
              children: [
                // Completed check icon box
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.surfaceElevated,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: SamanWorkoutTokens.emeraldAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Session details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recent.title,
                        style: const TextStyle(
                          color: SamanWorkoutTokens.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${recent.relativeTime} • ${recent.metrics}',
                        style: const TextStyle(
                          color: SamanWorkoutTokens.textSub,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow button
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.surfaceElevated,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: const Icon(Icons.arrow_forward,
                      size: 16, color: SamanWorkoutTokens.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusCategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onTap;

  const _FocusCategoryCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: SamanWorkoutTokens.cardSurface,
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
          border: Border.all(color: SamanWorkoutTokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: SamanWorkoutTokens.surfaceElevated),
              errorWidget: (_, __, ___) => Container(
                color: SamanWorkoutTokens.surfaceElevated,
                child: const Icon(Icons.fitness_center,
                    color: SamanWorkoutTokens.textMuted),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xFF0C0D0E),
                    Color(0x800C0D0E),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: SamanWorkoutTokens.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 16, color: SamanWorkoutTokens.textSub),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SamanWorkoutTokens.textSub,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
