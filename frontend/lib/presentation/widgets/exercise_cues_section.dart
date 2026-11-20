import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../tokens/saman_workout_tokens.dart';

class ExerciseCuesSection extends StatelessWidget {
  final Exercise exercise;

  const ExerciseCuesSection({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hướng dẫn kỹ thuật',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...exercise.cues.map(
          (cue) => _BulletPoint(
            icon: Icons.check_circle,
            iconColor: t.emeraldAccent,
            text: cue,
            textColor: t.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Lỗi thường gặp',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...exercise.commonMistakes.map(
          (mistake) => _BulletPoint(
            icon: Icons.error_outline,
            iconColor: t.crimsonAccent,
            text: mistake,
            textColor: t.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  const _BulletPoint({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
