import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_community_doorway_card.dart';
import '../widgets/journal_hero_card.dart';
import '../widgets/journal_library_entry_cards.dart';
import '../widgets/journal_preview_sheet.dart';
import '../widgets/journal_reading_progress_card.dart';
import '../widgets/journal_topic_chips.dart';

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
    final state = ref.watch(journalDiscoverProvider);
    final notifier = ref.read(journalDiscoverProvider.notifier);

    return Scaffold(
      backgroundColor: SamanHomeTokens.canvas,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────────────
            _buildHeader(context),

            // ─── Minimal Internal Tabs ───────────────────────────────
            _buildInternalTabs(),

            // ─── Body Stream or Backlog Notice Tab ────────────────────
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildKhamPhaContent(state, notifier)
                  : _buildBacklogTabPlaceholder(
                      _selectedTabIndex == 1 ? 'Thư viện' : 'Cẩm nang',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: SamanHomeTokens.canvas,
        border: Border(
          bottom: BorderSide(color: SamanHomeTokens.borderSubtle, width: 0.5),
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
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: SamanHomeTokens.textWhite,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Quay lại',
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Saman Journal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: SamanHomeTokens.textWhite,
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
                icon: const Icon(
                  Icons.bookmark_border_rounded,
                  color: SamanHomeTokens.textSecondary,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Đã lưu',
                onPressed: () {
                  JournalPreviewSheet.show(
                    context,
                    title: 'Bài viết đã lưu',
                    categoryLabel: 'Bộ sưu tập',
                    description:
                        'Danh sách các nghiên cứu và cẩm nang bạn đã bookmark.',
                    notice:
                        'Tính năng đồng bộ bookmark Journal sẽ được liên kết trong bản phát hành tới.',
                  );
                },
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: SamanHomeTokens.greenAccent,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: Color(0xFF003824),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInternalTabs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: SamanHomeTokens.canvas,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTabItem(label: 'Khám phá', index: 0),
            const SizedBox(width: 20),
            _buildTabItem(label: 'Thư viện', index: 1),
            const SizedBox(width: 20),
            _buildTabItem(label: 'Cẩm nang', index: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({required String label, required int index}) {
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
                  ? SamanHomeTokens.greenAccent
                  : SamanHomeTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2.5,
            width: isSelected ? 48 : 0,
            decoration: BoxDecoration(
              color: isSelected
                  ? SamanHomeTokens.greenAccent
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
  ) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(SamanHomeTokens.greenAccent),
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
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: SamanHomeTokens.textSecondary,
              ),
              const SizedBox(height: 12),
              const Text(
                'Không thể tải nội dung',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: SamanHomeTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: notifier.retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SamanHomeTokens.actionButtonSurface,
                  foregroundColor: SamanHomeTokens.textWhite,
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
        _buildSearchTriggerBar(),
        const SizedBox(height: 16),

        // ─── A. Featured Editorial Story ─────────────────────────────
        if (state.featuredArticle != null)
          JournalHeroCard(article: state.featuredArticle!),
        const SizedBox(height: 16),

        // ─── B. Topic Navigation Chips ───────────────────────────────
        JournalTopicChips(
          selectedTopic: state.selectedTopic,
          onTopicSelected: notifier.selectTopic,
        ),
        const SizedBox(height: 18),

        // ─── C. Tiếp tục đọc (Resume Reading) ────────────────────────
        if (state.readingProgress != null) ...[
          JournalReadingProgressCard(progress: state.readingProgress!),
          const SizedBox(height: 18),
        ],

        // ─── D. Thư viện (Knowledge Libraries) ───────────────────────
        if (state.libraryEntries.isNotEmpty) ...[
          JournalLibraryEntryCards(entries: state.libraryEntries),
          const SizedBox(height: 18),
        ],

        // ─── E. Bắt đầu cùng Saman (Guided series) ───────────────────
        if (state.guidedSeries != null) ...[
          _buildGuidedSeriesCard(state.guidedSeries!),
          const SizedBox(height: 18),
        ],

        // ─── F. Saman Community Doorway ──────────────────────────────
        const JournalCommunityDoorwayCard(),
      ],
    );
  }

  Widget _buildSearchTriggerBar() {
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
            color: SamanHomeTokens.cardSurfaceElevated,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: SamanHomeTokens.borderSubtle,
              width: 1,
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: SamanHomeTokens.textSecondary,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tìm kiến thức, bài tập, món ăn…',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: SamanHomeTokens.textSecondary,
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

  Widget _buildGuidedSeriesCard(dynamic series) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          JournalPreviewSheet.show(
            context,
            title: series.title,
            categoryLabel: series.badgeLabel,
            description: series.subtitle,
            notice:
                'Khóa học 5 bài nền tảng sẽ được mở trong bản phát hành chính thức.',
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SamanHomeTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: SamanHomeTokens.borderSubtle,
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
                          decoration: const BoxDecoration(
                            color: SamanHomeTokens.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          series.badgeLabel.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: SamanHomeTokens.greenAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      series.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: SamanHomeTokens.textWhite,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      series.subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SamanHomeTokens.textSecondary,
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
                      color: SamanHomeTokens.cardSurfaceElevated,
                      child: const Icon(
                        Icons.school_outlined,
                        color: SamanHomeTokens.textSecondary,
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

  Widget _buildBacklogTabPlaceholder(String tabName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: SamanHomeTokens.cardSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                size: 28,
                color: SamanHomeTokens.greenAccent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Mục "$tabName" đang được xây dựng',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Các màn chuyên sâu của Thư viện và Cẩm nang thuộc danh mục backlog chưa duyệt. Vui lòng quay lại tab Khám phá.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: SamanHomeTokens.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedTabIndex = 0;
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Quay lại Khám phá'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanHomeTokens.actionButtonSurface,
                foregroundColor: SamanHomeTokens.textWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
