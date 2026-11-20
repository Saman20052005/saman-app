import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
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
    final theme = Theme.of(context);
    final palette = SamanPalette.of(context);
    final isDark = palette.isDark;
    final bg = isDark ? const Color(0xFF0C0D0E) : theme.scaffoldBackgroundColor;
    final backIconCol =
        isDark ? const Color(0xFFF3F4F6) : theme.colorScheme.onSurface;
    final titleCol =
        isDark ? const Color(0xFFF9FAFB) : theme.colorScheme.onSurface;
    final subtitleCol = isDark ? const Color(0xFF9CA3AF) : palette.textSecondary;
    final dateStr = DateFormat('EEEE, MMM d').format(date);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: backIconCol,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meal Story',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: titleCol,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: subtitleCol,
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
