import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../tokens/saman_workout_tokens.dart';

class ExerciseSetLogCard extends StatelessWidget {
  final ExerciseSetLog log;
  final int index; // set number (0-based)

  const ExerciseSetLogCard({super.key, required this.log, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Set ${index + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: SamanWorkoutTokens.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              log.effectiveUnit == SetUnit.seconds
                  ? '${log.secondsCompleted} s'
                  : '${log.repsCompleted} reps',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SamanWorkoutTokens.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          if (log.effectiveUnit == SetUnit.reps) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                '${log.weightKg.toStringAsFixed(0)} kg',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: SamanWorkoutTokens.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          if (log.cvDetected)
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 4),
              child: Icon(Icons.visibility, size: 16, color: Colors.blue),
            ),
          if (log.isCompleted)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.check_circle,
                size: 16,
                color: SamanWorkoutTokens.emeraldAccent,
              ),
            ),
        ],
      ),
    );
  }
}
