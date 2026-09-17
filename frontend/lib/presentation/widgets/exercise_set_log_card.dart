import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../../core/constants/app_dimens.dart';

class ExerciseSetLogCard extends StatelessWidget {
  final ExerciseSetLog log;
  final int index; // set number (0-based)

  const ExerciseSetLogCard({super.key, required this.log, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(AppDimens.radiusM),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              'Set ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text('${log.repsCompleted} reps'),
          ),
          Expanded(
            child: Text('${log.weightKg.toStringAsFixed(0)} kg'),
          ),
          if (log.cvDetected)
            const Icon(Icons.visibility, size: 16, color: Colors.blue),
        ],
      ),
    );
  }
}
