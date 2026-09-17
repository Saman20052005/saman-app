import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';

class ExerciseCuesSection extends StatelessWidget {
  final Exercise exercise;

  const ExerciseCuesSection({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hướng dẫn kỹ thuật',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...exercise.cues.map(
          (cue) => _BulletPoint(
            icon: Icons.check_circle,
            iconColor: Colors.green,
            text: cue,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Lỗi thường gặp',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...exercise.commonMistakes.map(
          (mistake) => _BulletPoint(
            icon: Icons.error_outline,
            iconColor: Colors.red,
            text: mistake,
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

  const _BulletPoint({
    required this.icon,
    required this.iconColor,
    required this.text,
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
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
