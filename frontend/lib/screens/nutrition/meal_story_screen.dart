import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'widgets/story_timeline.dart';

/// Dedicated screen for Meal Story flow matching Calm Athleticism spec:
/// Wraps StoryTimeline with date context, clean AppBar and back navigation
class MealStoryScreen extends StatelessWidget {
  final DateTime date;

  const MealStoryScreen({
    super.key,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMM d').format(date);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0D0E),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Color(0xFFF3F4F6),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Meal Story',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF9FAFB),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: StoryTimeline(date: date),
        ),
      ),
    );
  }
}
