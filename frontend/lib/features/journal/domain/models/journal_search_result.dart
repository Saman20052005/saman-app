import 'package:flutter/material.dart';

/// Categories of search results within Saman Journal.
/// Note: Social community posts are strictly isolated and not included here.
enum JournalSearchCategory {
  all('all', 'journal_filter_all'),
  articles('articles', 'journal_filter_articles'),
  exercises('exercises', 'journal_filter_exercises'),
  foods('foods', 'journal_filter_foods'),
  recipes('recipes', 'journal_filter_recipes');

  const JournalSearchCategory(this.id, this.translationKey);

  final String id;
  final String translationKey;

  static JournalSearchCategory fromId(String id) {
    return JournalSearchCategory.values.firstWhere(
      (cat) => cat.id == id,
      orElse: () => JournalSearchCategory.all,
    );
  }
}

/// A structured item returned by Saman Journal search.
class JournalSearchResultItem {
  const JournalSearchResultItem({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    this.badgeText,
    this.metricText,
    this.readTimeMinutes,
    this.imageAsset,
    this.icon,
    this.isVerified = false,
    this.detailDescription,
  });

  final String id;
  final JournalSearchCategory category;
  final String title;
  final String subtitle;
  final String? badgeText;
  final String? metricText;
  final int? readTimeMinutes;
  final String? imageAsset;
  final IconData? icon;
  final bool isVerified;
  final String? detailDescription;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalSearchResultItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Educational contextual tip displayed below search results.
class JournalAdviceTip {
  const JournalAdviceTip({
    required this.id,
    required this.title,
    required this.content,
    this.icon = Icons.tips_and_updates_outlined,
  });

  final String id;
  final String title;
  final String content;
  final IconData icon;
}
