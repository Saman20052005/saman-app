import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_translations.dart';
import '../../data/models/exercise.dart';
import '../providers/muscle_recovery_provider.dart';
import '../screens/exercise_library_screen.dart';
import '../tokens/saman_workout_tokens.dart';

/// Displays 6-group muscle recovery readiness and a quick CTA for the freshest muscle group.
class MuscleRecoveryCard extends ConsumerWidget {
  const MuscleRecoveryCard({super.key});

  String _tr(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return AppTranslations.text(key, locale);
  }

  String _muscleLabel(BuildContext context, String rawGroup) {
    switch (rawGroup.toLowerCase().trim()) {
      case 'chest':
        return _tr(context, 'muscle_chest');
      case 'back':
        return _tr(context, 'muscle_back');
      case 'legs':
        return _tr(context, 'muscle_legs');
      case 'shoulders':
        return _tr(context, 'muscle_shoulders');
      case 'arms':
        return _tr(context, 'muscle_arms');
      case 'core':
        return _tr(context, 'muscle_core');
      default:
        if (rawGroup.isEmpty) return rawGroup;
        return rawGroup[0].toUpperCase() + rawGroup.substring(1);
    }
  }

  String _categoryForMuscle(String rawGroup) {
    switch (rawGroup.toLowerCase().trim()) {
      case 'legs':
        return 'Lower Body';
      case 'core':
        return 'Core';
      default:
        return 'Upper Body';
    }
  }

  Color _colorForPercent(num percent, SamanWorkoutPalette t) {
    if (percent >= 80) return t.emeraldAccent;
    if (percent >= 50) return t.amberAccent;
    return t.crimsonAccent;
  }

  String _statusLabel(BuildContext context, num percent) {
    if (percent >= 80) return _tr(context, 'recovery_ready');
    if (percent >= 50) return _tr(context, 'recovery_recovering');
    return _tr(context, 'recovery_fatigued');
  }

  void _openLibrary(BuildContext context, {String? muscleGroup}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => muscleGroup == null
            ? const ExerciseLibraryScreen()
            : ExerciseLibraryScreen(
                initialCategory: _categoryForMuscle(muscleGroup),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SamanWorkoutTokens.of(context);
    final recoveryAsync = ref.watch(muscleRecoveryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr(context, 'muscle_recovery_title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: t.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        recoveryAsync.when(
          loading: () => _RecoverySkeletonCard(palette: t),
          error: (_, __) => _RecoveryFallbackCard(
            key: const ValueKey('muscle_recovery_error'),
            palette: t,
            message: _tr(context, 'muscle_recovery_unavailable'),
            actionLabel: _tr(context, 'explore_exercises'),
            onTap: () => _openLibrary(context),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _RecoveryFallbackCard(
                key: const ValueKey('muscle_recovery_empty'),
                palette: t,
                message: _tr(context, 'muscle_recovery_empty'),
                actionLabel: _tr(context, 'explore_exercises'),
                onTap: () => _openLibrary(context),
              );
            }

            final best = items.reduce(
              (a, b) => a.recoveryPercent >= b.recoveryPercent ? a : b,
            );
            final bestPct = best.recoveryPercent.round().clamp(0, 100);
            final bestMuscleName = _muscleLabel(context, best.muscleGroup);

            return Container(
              key: const ValueKey('muscle_recovery_card'),
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              decoration: BoxDecoration(
                color: t.cardSurface,
                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MuscleGrid(
                    items: items,
                    palette: t,
                    labelBuilder: (group) => _muscleLabel(context, group),
                    statusBuilder: (pct) => _statusLabel(context, pct),
                    colorBuilder: (pct) => _colorForPercent(pct, t),
                  ),
                  const SizedBox(height: SamanWorkoutTokens.spacingMd),
                  ElevatedButton.icon(
                    key: const ValueKey('muscle_recovery_train_cta'),
                    onPressed: () => _openLibrary(
                      context,
                      muscleGroup: best.muscleGroup,
                    ),
                    icon: Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: t.buttonPrimaryText,
                    ),
                    label: Text(
                      '${_tr(context, 'train_muscle_cta')}: $bestMuscleName ($bestPct%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: t.buttonPrimaryText,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      backgroundColor: t.buttonPrimary,
                      foregroundColor: t.buttonPrimaryText,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MuscleGrid extends StatelessWidget {
  const _MuscleGrid({
    required this.items,
    required this.palette,
    required this.labelBuilder,
    required this.statusBuilder,
    required this.colorBuilder,
  });

  final List<MuscleRecoveryItem> items;
  final SamanWorkoutPalette palette;
  final String Function(String group) labelBuilder;
  final String Function(num percent) statusBuilder;
  final Color Function(num percent) colorBuilder;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final first = items[i];
      final second = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(
              child: _MuscleCell(
                key: ValueKey(
                  'muscle_recovery_item_${first.muscleGroup.toLowerCase()}',
                ),
                item: first,
                palette: palette,
                muscleLabel: labelBuilder(first.muscleGroup),
                statusLabel: statusBuilder(first.recoveryPercent),
                accentColor: colorBuilder(first.recoveryPercent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: second != null
                  ? _MuscleCell(
                      key: ValueKey(
                        'muscle_recovery_item_${second.muscleGroup.toLowerCase()}',
                      ),
                      item: second,
                      palette: palette,
                      muscleLabel: labelBuilder(second.muscleGroup),
                      statusLabel: statusBuilder(second.recoveryPercent),
                      accentColor: colorBuilder(second.recoveryPercent),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < items.length) {
        rows.add(const SizedBox(height: 8));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

class _MuscleCell extends StatelessWidget {
  const _MuscleCell({
    super.key,
    required this.item,
    required this.palette,
    required this.muscleLabel,
    required this.statusLabel,
    required this.accentColor,
  });

  final MuscleRecoveryItem item;
  final SamanWorkoutPalette palette;
  final String muscleLabel;
  final String statusLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final pct = item.recoveryPercent.round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  muscleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$pct%',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$statusLabel $pct%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: palette.isDark
                  ? const Color(0xFF262930)
                  : palette.border,
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (pct / 100.0).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoverySkeletonCard extends StatelessWidget {
  const _RecoverySkeletonCard({required this.palette});

  final SamanWorkoutPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('muscle_recovery_loading'),
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var row = 0; row < 3; row++) ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusMd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusMd,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (row < 2) const SizedBox(height: 8),
          ],
          const SizedBox(height: SamanWorkoutTokens.spacingMd),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryFallbackCard extends StatelessWidget {
  const _RecoveryFallbackCard({
    super.key,
    required this.palette,
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final SamanWorkoutPalette palette;
  final String message;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
              border: Border.all(color: palette.border),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              size: 18,
              color: palette.emeraldAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onTap,
            child: Text(
              actionLabel,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.emeraldAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
