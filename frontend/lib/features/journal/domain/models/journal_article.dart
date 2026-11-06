import 'package:flutter/material.dart';

/// Topic categorization for Saman Journal articles and guides.
enum JournalTopic {
  all('all', 'journal_topic_all'),
  workout('workout', 'journal_topic_workout'),
  nutrition('nutrition', 'journal_topic_nutrition'),
  recovery('recovery', 'journal_topic_recovery'),
  habits('habits', 'journal_topic_habits');

  const JournalTopic(this.id, this.translationKey);

  final String id;
  final String translationKey;

  static JournalTopic fromId(String id) {
    return JournalTopic.values.firstWhere(
      (topic) => topic.id == id,
      orElse: () => JournalTopic.all,
    );
  }
}

/// A scientific, evidence-based article model in Saman Journal.
class JournalArticle {
  const JournalArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.topic,
    required this.readTimeMinutes,
    required this.coverImageAsset,
    this.badgeLabel,
    this.isFeatured = false,
    this.contentBody,
  });

  final String id;
  final String title;
  final String summary;
  final JournalTopic topic;
  final int readTimeMinutes;
  final String coverImageAsset;
  final String? badgeLabel;
  final bool isFeatured;
  final String? contentBody;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalArticle &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Reading progress tracker for an active reader.
class JournalReadingProgress {
  const JournalReadingProgress({
    required this.articleId,
    required this.title,
    required this.progressPercent,
    required this.remainingMinutes,
    required this.coverImageAsset,
    this.summary,
  });

  final String articleId;
  final String title;
  final double progressPercent;
  final int remainingMinutes;
  final String coverImageAsset;
  final String? summary;

  int get percentDisplay => (progressPercent * 100).clamp(0, 100).round();
}

/// Knowledge library section entry (Exercises, Foods, etc.).
class JournalLibraryEntry {
  const JournalLibraryEntry({
    required this.id,
    required this.title,
    required this.itemCountLabel,
    required this.icon,
    required this.coverImageAsset,
    this.routeDescription,
  });

  final String id;
  final String title;
  final String itemCountLabel;
  final IconData icon;
  final String coverImageAsset;
  final String? routeDescription;
}

/// Guided onboarding or foundation series.
class JournalGuidedSeries {
  const JournalGuidedSeries({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.totalLessons,
    required this.coverImageAsset,
  });

  final String id;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final int totalLessons;
  final String coverImageAsset;
}
