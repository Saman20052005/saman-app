import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_search_result.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_preview_sheet.dart';

/// R02 — Saman Journal Search Screen.
///
/// Final visual truth: `design/saman-Journal_community/r02_journal_search/screen.png`
/// Strictly isolates Journal content (Articles, Exercises, Foods, Recipes) from Community posts.
class JournalSearchScreen extends ConsumerStatefulWidget {
  const JournalSearchScreen({super.key});

  @override
  ConsumerState<JournalSearchScreen> createState() =>
      _JournalSearchScreenState();
}

class _JournalSearchScreenState extends ConsumerState<JournalSearchScreen> {
  late final TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(journalSearchProvider).query;
    _searchController = TextEditingController(text: initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final searchState = ref.watch(journalSearchProvider);
    final searchNotifier = ref.read(journalSearchProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // ─── Header & Search Input Bar ───────────────────────────
            _buildSearchHeader(searchState, searchNotifier, tokens),

            // ─── Filter Chips (No Community Filter) ──────────────────
            _buildCategoryFilterChips(searchState, searchNotifier, tokens),

            // ─── Results Content Stream ──────────────────────────────
            Expanded(
              child: _buildResultsStream(searchState, searchNotifier, tokens),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(
    JournalSearchState state,
    JournalSearchNotifier notifier,
    SamanHomePalette tokens,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: BoxDecoration(
        color: tokens.canvas,
      ),
      child: Row(
        children: [
          // Back button to R01
          IconButton(
            key: const ValueKey('search_back_button'),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textWhite,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Quay lại',
          ),
          const SizedBox(width: 4),

          // Search text field container
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: tokens.cardSurfaceElevated,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
                border: Border.all(
                  color: tokens.border,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: tokens.greenAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('journal_search_input_field'),
                      controller: _searchController,
                      focusNode: _focusNode,
                      style: TextStyle(
                        fontSize: 14,
                        color: tokens.textWhite,
                        fontWeight: FontWeight.w400,
                      ),
                      cursorColor: tokens.greenAccent,
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm bài viết, thực phẩm, bài tập...',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: tokens.textSecondary,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        filled: false,
                      ),
                      onChanged: notifier.onQueryChanged,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      key: const ValueKey('clear_search_button'),
                      icon: Icon(
                        Icons.cancel_rounded,
                        color: tokens.textSecondary,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        _searchController.clear();
                        notifier.clearQuery();
                      },
                      tooltip: 'Xóa tìm kiếm',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Advanced filter button
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.cardSurfaceElevated,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(
                color: tokens.border,
                width: 1,
              ),
            ),
            child: IconButton(
              icon: Icon(
                Icons.tune_rounded,
                color: tokens.textSecondary,
                size: 20,
              ),
              onPressed: () {
                JournalPreviewSheet.show(
                  context,
                  title: 'Bộ lọc nâng cao',
                  categoryLabel: 'Bộ lọc',
                  description:
                      'Tùy chỉnh khoảng calo, nhóm cơ tác động và thời lượng đọc.',
                  notice:
                      'Bộ lọc sâu sẽ được hoàn thiện cùng với hệ thống tag tri thức.',
                );
              },
              tooltip: 'Bộ lọc nâng cao',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChips(
    JournalSearchState state,
    JournalSearchNotifier notifier,
    SamanHomePalette tokens,
  ) {
    const categories = [
      JournalSearchCategory.all,
      JournalSearchCategory.articles,
      JournalSearchCategory.exercises,
      JournalSearchCategory.foods,
      JournalSearchCategory.recipes,
    ];

    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = cat == state.selectedCategory;

          final label = switch (cat) {
            JournalSearchCategory.all => 'Tất cả',
            JournalSearchCategory.articles => 'Bài viết',
            JournalSearchCategory.exercises => 'Bài tập',
            JournalSearchCategory.foods => 'Thực phẩm',
            JournalSearchCategory.recipes => 'Công thức',
          };

          return Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('filter_chip_${cat.name}'),
              onTap: () => notifier.selectCategory(cat),
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? tokens.greenAccent
                      : tokens.cardSurfaceElevated,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  border: Border.all(
                    color: isSelected
                        ? tokens.greenAccent
                        : tokens.borderSubtle,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? (tokens.isDark
                              ? const Color(0xFF003824)
                              : const Color(0xFFFFFFFF))
                          : tokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsStream(
    JournalSearchState state,
    JournalSearchNotifier notifier,
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
                Icons.search_off_rounded,
                size: 48,
                color: tokens.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Lỗi tìm kiếm',
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

    if (state.isEmptyResult) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 28,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Không tìm thấy kết quả phù hợp cho "${state.query}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hãy thử tìm bằng từ khóa khác như "protein", "ức gà", "squat" hoặc thay đổi bộ lọc.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        // If "Tất cả" is selected, we group by categories nicely
        if (state.selectedCategory == JournalSearchCategory.all) ...[
          _buildGroupedSection(
            categoryTitle: 'BÀI VIẾT',
            actionTitle: 'Xem thêm',
            items: state.results
                .where((i) => i.category == JournalSearchCategory.articles)
                .toList(),
            tokens: tokens,
          ),
          _buildGroupedSection(
            categoryTitle: 'THỰC PHẨM',
            actionTitle: 'Cơ sở dữ liệu',
            items: state.results
                .where((i) => i.category == JournalSearchCategory.foods)
                .toList(),
            tokens: tokens,
          ),
          _buildGroupedSection(
            categoryTitle: 'CÔNG THỨC',
            actionTitle: 'Thực đơn',
            items: state.results
                .where((i) => i.category == JournalSearchCategory.recipes)
                .toList(),
            tokens: tokens,
          ),
          _buildGroupedSection(
            categoryTitle: 'BÀI TẬP',
            actionTitle: 'Giáo án',
            items: state.results
                .where((i) => i.category == JournalSearchCategory.exercises)
                .toList(),
            tokens: tokens,
          ),
        ] else ...[
          // Specific category list
          ...state.results.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildItemCard(item, tokens),
              )),
        ],

        // Advice Tip Footer Card
        if (state.adviceTip != null) ...[
          const SizedBox(height: 8),
          _buildAdviceTipCard(state.adviceTip!, tokens),
        ],
      ],
    );
  }

  Widget _buildGroupedSection({
    required String categoryTitle,
    required String actionTitle,
    required List<JournalSearchResultItem> items,
    required SamanHomePalette tokens,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                categoryTitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: tokens.textSecondary,
                ),
              ),
              Text(
                actionTitle,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.greenAccent,
                ),
              ),
            ],
          ),
        ),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildItemCard(item, tokens),
            )),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildItemCard(
    JournalSearchResultItem item,
    SamanHomePalette tokens,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          JournalPreviewSheet.show(
            context,
            title: item.title,
            categoryLabel: item.badgeText ?? item.category.name,
            description: item.detailDescription ?? item.subtitle,
            metricLabel: item.metricText,
            imageAsset: item.imageAsset,
            icon: item.icon,
            notice:
                'Xem trước chi tiết kết quả tìm kiếm. Màn đích chuyên sâu đang được kết nối trong các bản phát hành tiếp theo.',
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: tokens.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Thumbnail / Icon
              if (item.imageAsset != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  child: SizedBox(
                    width: item.category == JournalSearchCategory.articles ? 76 : 56,
                    height: item.category == JournalSearchCategory.articles ? 76 : 56,
                    child: Image.asset(
                      item.imageAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: tokens.cardSurfaceElevated,
                        child: Icon(
                          Icons.image_outlined,
                          size: 24,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              else if (item.icon != null)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tokens.cardSurfaceElevated,
                    borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  ),
                  child: Icon(
                    item.icon,
                    size: 24,
                    color: tokens.greenAccent,
                  ),
                ),
              const SizedBox(width: 12),

              // Text details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.badgeText != null) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.cardSurfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.badgeText!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: tokens.greenAccent,
                              ),
                            ),
                          ),
                          if (item.readTimeMinutes != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${item.readTimeMinutes} phút đọc',
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.textWhite,
                            ),
                          ),
                        ),
                        if (item.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: tokens.greenAccent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (item.metricText != null &&
                        item.category != JournalSearchCategory.articles) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.metricText!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: tokens.greenAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Action trailing
              if (item.category == JournalSearchCategory.foods)
                IconButton(
                  icon: Icon(Icons.add_rounded, color: tokens.textWhite),
                  tooltip: 'Xem thông tin khẩu phần',
                  onPressed: () {
                    JournalPreviewSheet.show(
                      context,
                      title: item.title,
                      categoryLabel: 'Chi tiết dinh dưỡng',
                      description:
                          '${item.subtitle}\nChỉ số: ${item.metricText}',
                      notice: context.tr('journal_food_preview_note'),
                    );
                  },
                )
              else if (item.category == JournalSearchCategory.recipes)
                IconButton(
                  icon: Icon(
                    Icons.bookmark_border_rounded,
                    color: tokens.textSecondary,
                  ),
                  tooltip: 'Lưu công thức',
                  onPressed: () {
                    JournalPreviewSheet.show(
                      context,
                      title: item.title,
                      categoryLabel: 'Công thức món ăn',
                      description: item.subtitle,
                      notice: 'Đã lưu vào bộ sưu tập công thức mẫu của phiên.',
                    );
                  },
                )
              else
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

  Widget _buildAdviceTipCard(JournalAdviceTip tip, SamanHomePalette tokens) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurfaceElevated,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(
          color: tokens.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tokens.greenBadgeBg,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.greenBadgeBorder),
            ),
            child: Icon(
              tip.icon,
              size: 16,
              color: tokens.greenAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: tokens.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
