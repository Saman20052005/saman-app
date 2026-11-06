import '../models/journal_article.dart';
import '../models/journal_search_result.dart';

/// Abstract contract for Saman Journal data retrieval.
abstract class JournalRepository {
  /// Fetches articles optionally filtered by topic.
  Future<List<JournalArticle>> getArticles({JournalTopic? topic});

  /// Fetches the primary featured editorial story.
  Future<JournalArticle?> getFeaturedArticle();

  /// Fetches current active reading progress, if any.
  Future<JournalReadingProgress?> getReadingProgress();

  /// Fetches curated knowledge library entries (Exercises, Foods).
  Future<List<JournalLibraryEntry>> getLibraryEntries();

  /// Fetches the current guided foundational series.
  Future<JournalGuidedSeries?> getGuidedSeries();

  /// Searches journal content across articles, exercises, foods, and recipes.
  Future<List<JournalSearchResultItem>> search({
    required String query,
    JournalSearchCategory category = JournalSearchCategory.all,
  });

  /// Fetches contextual advice tip based on user search query.
  Future<JournalAdviceTip?> getAdviceTipForQuery(String query);

  /// Retrieves a specific article by ID.
  Future<JournalArticle?> getArticleById(String id);
}
