import '../../domain/models/journal_article.dart';
import '../../domain/models/journal_search_result.dart';
import '../../domain/repositories/journal_repository.dart';
import '../datasources/journal_fake_datasource.dart';
import '../datasources/journal_remote_datasource.dart';

/// Implementation of [JournalRepository] supporting either [JournalRemoteDatasource]
/// (real backend HTTP) or [JournalFakeDatasource] (offline fixtures).
///
/// Error Handling Invariant:
/// When remote mode is active, any network or HTTP exception is strictly propagated
/// to the caller. Silent fallback to fake fixtures is strictly prohibited.
class JournalRepositoryImpl implements JournalRepository {
  JournalRepositoryImpl({
    JournalRemoteDatasource? remoteDatasource,
    JournalFakeDatasource? fakeDatasource,
    JournalFakeDatasource? datasource,
  })  : _remoteDatasource = remoteDatasource,
        _fakeDatasource = fakeDatasource ?? datasource ?? JournalFakeDatasource();

  final JournalRemoteDatasource? _remoteDatasource;
  final JournalFakeDatasource _fakeDatasource;

  bool get isRemoteMode => _remoteDatasource != null;

  @override
  Future<List<JournalArticle>> getArticles({JournalTopic? topic}) async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getArticles(topic: topic);
    }
    return _fakeDatasource.getArticles(topic: topic);
  }

  @override
  Future<JournalArticle?> getFeaturedArticle() async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getFeaturedArticle();
    }
    return _fakeDatasource.getFeaturedArticle();
  }

  @override
  Future<JournalReadingProgress?> getReadingProgress() async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getReadingProgress();
    }
    return _fakeDatasource.getReadingProgress();
  }

  @override
  Future<List<JournalLibraryEntry>> getLibraryEntries() async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getLibrarySummary();
    }
    return _fakeDatasource.getLibraryEntries();
  }

  @override
  Future<JournalGuidedSeries?> getGuidedSeries() async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getGuidedSeries();
    }
    return _fakeDatasource.getGuidedSeries();
  }

  @override
  Future<List<JournalSearchResultItem>> search({
    required String query,
    JournalSearchCategory category = JournalSearchCategory.all,
  }) async {
    if (_remoteDatasource != null) {
      final dto = await _remoteDatasource.search(
        query: query,
        category: category,
      );
      return dto.items;
    }
    return _fakeDatasource.search(query: query, category: category);
  }

  @override
  Future<JournalAdviceTip?> getAdviceTipForQuery(String query) async {
    if (_remoteDatasource != null) {
      final dto = await _remoteDatasource.search(
        query: query,
        category: JournalSearchCategory.all,
      );
      return dto.adviceTip;
    }
    return _fakeDatasource.getAdviceTipForQuery(query);
  }

  @override
  Future<JournalArticle?> getArticleById(String id) async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getArticleById(id);
    }
    return _fakeDatasource.getArticleById(id);
  }

  @override
  Future<void> saveReadingProgress(
    String articleId,
    double progressPercent,
    int remainingMinutes,
  ) async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.saveReadingProgress(
        articleId: articleId,
        progressPercent: progressPercent,
        remainingMinutes: remainingMinutes,
      );
    }
    return _fakeDatasource.saveReadingProgress(
      articleId,
      progressPercent,
      remainingMinutes,
    );
  }

  @override
  Future<List<JournalArticle>> getBookmarkedArticles() async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.getBookmarkedArticles();
    }
    return _fakeDatasource.getBookmarkedArticles();
  }

  @override
  Future<bool> toggleBookmark(String articleId, bool desiredState) async {
    if (_remoteDatasource != null) {
      return _remoteDatasource.toggleBookmark(
        articleId: articleId,
        desiredState: desiredState,
      );
    }
    return _fakeDatasource.toggleBookmark(articleId, desiredState);
  }
}
