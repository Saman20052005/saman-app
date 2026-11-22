import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';
import '../../domain/models/journal_search_result.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_community_doorway_card.dart';
import '../widgets/journal_hero_card.dart';
import '../widgets/journal_library_entry_cards.dart';
import '../widgets/journal_reading_progress_card.dart';
import '../widgets/journal_topic_chips.dart';
import 'journal_article_detail_screen.dart';
import 'journal_search_screen.dart';

/// R01 — Saman Journal Discover Screen.
///
/// Final visual truth: `design/saman-Journal_community/r01_journal_discover/screen.png`
/// Clean, dark obsidian performance architecture.
class JournalDiscoverScreen extends ConsumerStatefulWidget {
  const JournalDiscoverScreen({super.key});

  @override
  ConsumerState<JournalDiscoverScreen> createState() =>
      _JournalDiscoverScreenState();
}

class _JournalDiscoverScreenState extends ConsumerState<JournalDiscoverScreen> {
  int _selectedTabIndex = 0; // 0: Khám phá, 1: Thư viện, 2: Cẩm nang
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToSearch() {
    Navigator.of(context).pushNamed(AppRoutes.journalSearch);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final state = ref.watch(journalDiscoverProvider);
    final notifier = ref.read(journalDiscoverProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────────────
            _buildHeader(context, tokens),

            // ─── Minimal Internal Tabs ───────────────────────────────
            _buildInternalTabs(tokens),

            // ─── Body Stream or Real Data Tabs ───────────────────────
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildKhamPhaContent(state, notifier, tokens)
                  : _selectedTabIndex == 1
                      ? _buildThuVienContent(state, notifier, tokens)
                      : _buildCamNangContent(state, notifier, tokens),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SamanHomePalette tokens) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(
          bottom: BorderSide(color: tokens.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('journal_back_button'),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: tokens.textWhite,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Quay lại',
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Saman Journal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tokens.textWhite,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('journal_bookmarks_button'),
                icon: Icon(
                  Icons.bookmark_border_rounded,
                  color: tokens.textSecondary,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Đã lưu',
                onPressed: () {
                  _showBookmarksSheet(context, tokens);
                },
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tokens.greenAccent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInternalTabs(SamanHomePalette tokens) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.canvas,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTabItem(label: 'Khám phá', index: 0, tokens: tokens),
            const SizedBox(width: 20),
            _buildTabItem(label: 'Thư viện', index: 1, tokens: tokens),
            const SizedBox(width: 20),
            _buildTabItem(label: 'Cẩm nang', index: 2, tokens: tokens),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required String label,
    required int index,
    required SamanHomePalette tokens,
  }) {
    final isSelected = _selectedTabIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? tokens.greenAccent
                  : tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2.5,
            width: isSelected ? 48 : 0,
            decoration: BoxDecoration(
              color: isSelected
                  ? tokens.greenAccent
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKhamPhaContent(
    JournalDiscoverState state,
    JournalDiscoverNotifier notifier,
    SamanHomePalette tokens,
  ) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: tokens.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Không thể tải nội dung',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.textWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: notifier.retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.actionButtonSurface,
                  foregroundColor: tokens.textWhite,
                ),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        // ─── Search Bar Trigger ──────────────────────────────────────
        _buildSearchTriggerBar(tokens),
        const SizedBox(height: 16),

        // ─── A. Featured Editorial Story ─────────────────────────────
        if (state.featuredArticle != null)
          JournalHeroCard(
            article: state.featuredArticle!,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => JournalArticleDetailScreen(
                    articleId: state.featuredArticle!.id,
                    initialArticle: state.featuredArticle,
                    initialBookmarked: state.bookmarkedIds.contains(state.featuredArticle!.id),
                    onBookmarkToggle: (id, nextState) => notifier.toggleBookmark(id),
                    onProgressSync: (id, prog, rem) => notifier.syncReadingProgress(id, prog, rem),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),

        // ─── B. Topic Navigation Chips ───────────────────────────────
        JournalTopicChips(
          selectedTopic: state.selectedTopic,
          onTopicSelected: notifier.selectTopic,
        ),
        const SizedBox(height: 18),

        // ─── C. Tiếp tục đọc (Resume Reading) ────────────────────────
        if (state.readingProgress != null) ...[
          JournalReadingProgressCard(
            progress: state.readingProgress!,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => JournalArticleDetailScreen(
                    articleId: state.readingProgress!.articleId,
                    initialProgress: state.readingProgress!.progressPercent,
                    initialBookmarked: state.bookmarkedIds.contains(state.readingProgress!.articleId),
                    onBookmarkToggle: (id, nextState) => notifier.toggleBookmark(id),
                    onProgressSync: (id, prog, rem) => notifier.syncReadingProgress(id, prog, rem),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
        ],

        // ─── D. Thư viện (Knowledge Libraries) ───────────────────────
        if (state.libraryEntries.isNotEmpty) ...[
          JournalLibraryEntryCards(entries: state.libraryEntries),
          const SizedBox(height: 18),
        ],

        // ─── E. Bắt đầu cùng Saman (Guided series) ───────────────────
        if (state.guidedSeries != null) ...[
          _buildGuidedSeriesCard(state.guidedSeries!, tokens),
          const SizedBox(height: 18),
        ],

        // ─── F. Saman Community Doorway ──────────────────────────────
        const JournalCommunityDoorwayCard(),
      ],
    );
  }

  Widget _buildSearchTriggerBar(SamanHomePalette tokens) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('journal_search_bar_trigger'),
        onTap: _navigateToSearch,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tokens.cardSurfaceElevated,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: tokens.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: tokens.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tìm kiến thức, bài tập, món ăn…',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidedSeriesCard(dynamic series, SamanHomePalette tokens) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTabIndex = 2; // Jump directly to Cẩm nang tab
          });
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: tokens.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: tokens.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          series.badgeLabel.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: tokens.greenAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      series.title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: tokens.textWhite,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      series.subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Image.asset(
                    series.coverImageAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: tokens.cardSurfaceElevated,
                      child: Icon(
                        Icons.school_outlined,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThuVienContent(
    JournalDiscoverState state,
    JournalDiscoverNotifier notifier,
    SamanHomePalette tokens,
  ) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        // Category headers and search jump
        Text(
          context.tr('journal_libraries'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: tokens.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Khám phá kho dữ liệu động tác chuẩn xác và bảng thành phần dinh dưỡng.',
          style: TextStyle(
            fontSize: 13,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Library entries
        if (state.libraryEntries.isNotEmpty)
          JournalLibraryEntryCards(entries: state.libraryEntries),
        const SizedBox(height: 24),

        // Quick Search Action Cards
        Row(
          children: [
            Expanded(
              child: _buildQuickSearchCard(
                title: 'Tra cứu bài tập',
                subtitle: 'Kỹ thuật & nhóm cơ',
                icon: Icons.fitness_center_rounded,
                category: JournalSearchCategory.exercises,
                tokens: tokens,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickSearchCard(
                title: 'Tra cứu thực phẩm',
                subtitle: 'Calories & Macro',
                icon: Icons.restaurant_rounded,
                category: JournalSearchCategory.foods,
                tokens: tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Bookmarked articles section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr('journal_bookmarks_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.textWhite,
                ),
              ),
            ),
            if (state.bookmarkedArticles.isNotEmpty)
              TextButton(
                onPressed: () => _showBookmarksSheet(context, tokens),
                child: Text(
                  context.tr('journal_view_all'),
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.greenAccent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (state.bookmarkedArticles.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(color: tokens.borderSubtle, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.bookmark_border_rounded, color: tokens.textSecondary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('journal_bookmarks_empty'),
                    style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          ...state.bookmarkedArticles.take(3).map((article) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildArticleTile(
                article: article,
                notifier: notifier,
                tokens: tokens,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCamNangContent(
    JournalDiscoverState state,
    JournalDiscoverNotifier notifier,
    SamanHomePalette tokens,
  ) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
        ),
      );
    }

    final series = state.guidedSeries;

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        if (series != null) ...[
          // Series banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(color: tokens.borderSubtle, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tokens.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      series.badgeLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.greenAccent,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  series.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  series.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Lessons list
          Text(
            context.tr('journal_lessons_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textWhite,
            ),
          ),
          const SizedBox(height: 10),

          if (series.lessons.isNotEmpty)
            ...series.lessons.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final lesson = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildLessonTile(
                  index: idx,
                  article: lesson,
                  notifier: notifier,
                  tokens: tokens,
                ),
              );
            })
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chưa có bài học nào trong lộ trình này.',
                style: TextStyle(color: tokens.textSecondary, fontSize: 13),
              ),
            ),
          const SizedBox(height: 20),
        ],

        // Also display all topic articles
        Text(
          context.tr('journal_topics_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: tokens.textWhite,
          ),
        ),
        const SizedBox(height: 10),
        ...state.articles.map((article) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildArticleTile(
              article: article,
              notifier: notifier,
              tokens: tokens,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildQuickSearchCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required JournalSearchCategory category,
    required SamanHomePalette tokens,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => JournalSearchScreen(
                initialCategory: category,
                initialQuery: '',
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(color: tokens.borderSubtle, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tokens.greenAccent, size: 22),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArticleTile({
    required JournalArticle article,
    required JournalDiscoverNotifier notifier,
    required SamanHomePalette tokens,
  }) {
    final state = ref.watch(journalDiscoverProvider);
    final isBookmarked = state.bookmarkedIds.contains(article.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => JournalArticleDetailScreen(
                articleId: article.id,
                initialArticle: article,
                initialBookmarked: isBookmarked,
                onBookmarkToggle: (id, nextState) => notifier.toggleBookmark(id),
                onProgressSync: (id, prog, rem) => notifier.syncReadingProgress(id, prog, rem),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            border: Border.all(color: tokens.borderSubtle, width: 0.8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Image.asset(
                    article.coverImageAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: tokens.cardSurfaceElevated,
                      child: Icon(Icons.menu_book_rounded, color: tokens.textSecondary, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.textWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${article.readTimeMinutes} phút đọc • ${article.badgeLabel ?? "Kiến thức"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: isBookmarked ? tokens.greenAccent : tokens.textSecondary,
                  size: 20,
                ),
                onPressed: () => notifier.toggleBookmark(article.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLessonTile({
    required int index,
    required JournalArticle article,
    required JournalDiscoverNotifier notifier,
    required SamanHomePalette tokens,
  }) {
    final state = ref.watch(journalDiscoverProvider);
    final isBookmarked = state.bookmarkedIds.contains(article.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => JournalArticleDetailScreen(
                articleId: article.id,
                initialArticle: article,
                initialBookmarked: isBookmarked,
                onBookmarkToggle: (id, nextState) => notifier.toggleBookmark(id),
                onProgressSync: (id, prog, rem) => notifier.syncReadingProgress(id, prog, rem),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            border: Border.all(color: tokens.borderSubtle, width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tokens.cardSurfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.borderSubtle, width: 0.8),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.textWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${article.readTimeMinutes} phút đọc • ${article.badgeLabel ?? "Bài học"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: tokens.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookmarksSheet(BuildContext context, SamanHomePalette tokens) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Consumer(
          builder: (ctx, ref, _) {
            final state = ref.watch(journalDiscoverProvider);
            final notifier = ref.read(journalDiscoverProvider.notifier);
            final bookmarks = state.bookmarkedArticles;

            return Container(
              height: MediaQuery.of(bottomSheetContext).size.height * 0.75,
              decoration: BoxDecoration(
                color: tokens.cardSurfaceElevated,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ctx.tr('journal_bookmarks_title'),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: tokens.textWhite,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                          onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.borderSubtle),
                  Expanded(
                    child: bookmarks.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                ctx.tr('journal_bookmarks_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: bookmarks.length,
                            itemBuilder: (_, index) {
                              final item = bookmarks[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildArticleTile(
                                  article: item,
                                  notifier: notifier,
                                  tokens: tokens,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
