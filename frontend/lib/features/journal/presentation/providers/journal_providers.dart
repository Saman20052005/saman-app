import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/api_client.dart';
import '../../data/datasources/journal_fake_datasource.dart';
import '../../data/datasources/journal_remote_datasource.dart';
import '../../domain/models/journal_article.dart';
import '../../domain/models/journal_search_result.dart';
import '../../domain/repositories/journal_repository.dart';
import '../../data/repositories/journal_repository_impl.dart';

// ─── Dependency Injection ─────────────────────────────────────────────────

/// Explicit toggle between Remote HTTP and Fake Datasources via DI.
/// In production/connected mode, defaults to true.
final useRemoteJournalProvider = StateProvider<bool>((ref) {
  return const bool.fromEnvironment('USE_REMOTE_JOURNAL', defaultValue: false);
});

final journalFakeDatasourceProvider = Provider<JournalFakeDatasource>((ref) {
  return JournalFakeDatasource();
});

final journalRemoteDatasourceProvider = Provider<JournalRemoteDatasource>((ref) {
  return JournalRemoteDatasourceImpl(dio: ApiClient.dio);
});

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  final useRemote = ref.watch(useRemoteJournalProvider);
  if (useRemote) {
    final remoteDs = ref.watch(journalRemoteDatasourceProvider);
    return JournalRepositoryImpl(remoteDatasource: remoteDs);
  }
  final fakeDs = ref.watch(journalFakeDatasourceProvider);
  return JournalRepositoryImpl(fakeDatasource: fakeDs);
});

// ─── R01 Journal Discover State & Notifier ────────────────────────────────

class JournalDiscoverState {
  const JournalDiscoverState({
    this.isLoading = true,
    this.error,
    this.selectedTopic = JournalTopic.recovery,
    this.featuredArticle,
    this.articles = const [],
    this.readingProgress,
    this.libraryEntries = const [],
    this.guidedSeries,
  });

  final bool isLoading;
  final String? error;
  final JournalTopic selectedTopic;
  final JournalArticle? featuredArticle;
  final List<JournalArticle> articles;
  final JournalReadingProgress? readingProgress;
  final List<JournalLibraryEntry> libraryEntries;
  final JournalGuidedSeries? guidedSeries;

  JournalDiscoverState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    JournalTopic? selectedTopic,
    JournalArticle? featuredArticle,
    List<JournalArticle>? articles,
    JournalReadingProgress? readingProgress,
    List<JournalLibraryEntry>? libraryEntries,
    JournalGuidedSeries? guidedSeries,
  }) {
    return JournalDiscoverState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selectedTopic: selectedTopic ?? this.selectedTopic,
      featuredArticle: featuredArticle ?? this.featuredArticle,
      articles: articles ?? this.articles,
      readingProgress: readingProgress ?? this.readingProgress,
      libraryEntries: libraryEntries ?? this.libraryEntries,
      guidedSeries: guidedSeries ?? this.guidedSeries,
    );
  }
}

class JournalDiscoverNotifier extends StateNotifier<JournalDiscoverState> {
  JournalDiscoverNotifier(this._repository) : super(const JournalDiscoverState()) {
    load();
  }

  final JournalRepository _repository;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repository.getFeaturedArticle(),
        _repository.getArticles(topic: state.selectedTopic),
        _repository.getReadingProgress(),
        _repository.getLibraryEntries(),
        _repository.getGuidedSeries(),
      ]);

      if (!mounted) return;

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        featuredArticle: results[0] as JournalArticle?,
        articles: results[1] as List<JournalArticle>,
        readingProgress: results[2] as JournalReadingProgress?,
        libraryEntries: results[3] as List<JournalLibraryEntry>,
        guidedSeries: results[4] as JournalGuidedSeries?,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> selectTopic(JournalTopic topic) async {
    if (state.selectedTopic == topic) return;
    state = state.copyWith(selectedTopic: topic, isLoading: true, clearError: true);
    try {
      final articles = await _repository.getArticles(topic: topic);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        articles: articles,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void retry() {
    load();
  }
}

final journalDiscoverProvider =
    StateNotifierProvider<JournalDiscoverNotifier, JournalDiscoverState>((ref) {
  final repo = ref.watch(journalRepositoryProvider);
  return JournalDiscoverNotifier(repo);
});

// ─── R02 Journal Search State & Notifier ──────────────────────────────────

class JournalSearchState {
  const JournalSearchState({
    this.query = '',
    this.selectedCategory = JournalSearchCategory.all,
    this.isLoading = false,
    this.error,
    this.results = const [],
    this.adviceTip,
  });

  final String query;
  final JournalSearchCategory selectedCategory;
  final bool isLoading;
  final String? error;
  final List<JournalSearchResultItem> results;
  final JournalAdviceTip? adviceTip;

  bool get isEmptyResult =>
      !isLoading && error == null && results.isEmpty;

  bool get isPopulated =>
      !isLoading && error == null && results.isNotEmpty;

  JournalSearchState copyWith({
    String? query,
    JournalSearchCategory? selectedCategory,
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<JournalSearchResultItem>? results,
    JournalAdviceTip? adviceTip,
  }) {
    return JournalSearchState(
      query: query ?? this.query,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      results: results ?? this.results,
      adviceTip: adviceTip ?? this.adviceTip,
    );
  }
}

class JournalSearchNotifier extends StateNotifier<JournalSearchState> {
  JournalSearchNotifier(this._repository) : super(const JournalSearchState()) {
    // Initial search with default query "protein" to match design mockup
    executeSearch(immediateQuery: 'protein');
  }

  final JournalRepository _repository;
  Timer? _debounceTimer;
  int _activeQueryId = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void onQueryChanged(String newQuery) {
    _debounceTimer?.cancel();
    if (newQuery == state.query) return;

    state = state.copyWith(query: newQuery);

    // Debounce for 300ms
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      executeSearch();
    });
  }

  void clearQuery() {
    _debounceTimer?.cancel();
    state = state.copyWith(query: '');
    executeSearch(immediateQuery: '');
  }

  void selectCategory(JournalSearchCategory category) {
    if (state.selectedCategory == category) return;
    _debounceTimer?.cancel();
    state = state.copyWith(selectedCategory: category);
    executeSearch();
  }

  Future<void> executeSearch({String? immediateQuery}) async {
    final queryToSearch = immediateQuery ?? state.query;
    final categoryToSearch = state.selectedCategory;
    final currentQueryId = ++_activeQueryId;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      query: queryToSearch,
    );

    try {
      final results = await _repository.search(
        query: queryToSearch,
        category: categoryToSearch,
      );
      final advice = await _repository.getAdviceTipForQuery(queryToSearch);

      // Guard: Discard stale response if a newer query has fired
      if (!mounted || currentQueryId != _activeQueryId) {
        return;
      }

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        results: results,
        adviceTip: advice,
      );
    } catch (e) {
      if (!mounted || currentQueryId != _activeQueryId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void retry() {
    // Retry retains current query and category
    executeSearch();
  }
}

final journalSearchProvider =
    StateNotifierProvider<JournalSearchNotifier, JournalSearchState>((ref) {
  final repo = ref.watch(journalRepositoryProvider);
  return JournalSearchNotifier(repo);
});
