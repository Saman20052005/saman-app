import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';
import '../providers/journal_providers.dart';

/// Full-text reading screen for a Saman Journal article.
///
/// Built strictly on [SamanHomeTokens.of] for Dual-Theme (Light / Dark) parity,
/// with reading progress tracking, adjustable typography size, and bookmarking.
class JournalArticleDetailScreen extends ConsumerStatefulWidget {
  const JournalArticleDetailScreen({
    super.key,
    required this.articleId,
    this.initialArticle,
    this.initialBookmarked = false,
    this.initialProgress = 0.0,
    this.onBookmarkToggle,
    this.onProgressSync,
  });

  final String articleId;
  final JournalArticle? initialArticle;
  final bool initialBookmarked;
  final double initialProgress;
  final Future<bool> Function(String articleId, bool nextState)?
      onBookmarkToggle;
  final Future<void> Function(
    String articleId,
    double progress,
    int remainingMinutes,
  )? onProgressSync;

  @override
  ConsumerState<JournalArticleDetailScreen> createState() =>
      _JournalArticleDetailScreenState();
}

class _JournalArticleDetailScreenState
    extends ConsumerState<JournalArticleDetailScreen> {
  static const double _standardFontSize = 15.5;
  static const double _largeFontSize = 18.0;
  static const Duration _progressSyncDebounce = Duration(milliseconds: 800);

  final ScrollController _scrollController = ScrollController();
  late final ValueNotifier<double> _progressNotifier;

  JournalArticle? _article;
  bool _isLoading = false;
  bool _isNotFound = false;
  String? _errorMessage;

  late bool _isBookmarked;
  bool _isTogglingBookmark = false;
  bool _isLargeText = false;

  Timer? _progressDebounceTimer;
  double _latestProgress = 0.0;
  double _lastSyncedProgress = 0.0;
  bool _hasUserScrolled = false;

  @override
  void initState() {
    super.initState();
    _article = widget.initialArticle;
    _isBookmarked = widget.initialBookmarked;
    _latestProgress = widget.initialProgress.clamp(0.0, 1.0);
    _lastSyncedProgress = _latestProgress;
    _progressNotifier = ValueNotifier<double>(_latestProgress);

    _scrollController.addListener(_handleScroll);

    final needsFetch = _article == null ||
        (_article!.contentBody == null || _article!.contentBody!.trim().isEmpty);
    if (needsFetch) {
      _loadArticle();
    }
  }

  @override
  void dispose() {
    _progressDebounceTimer?.cancel();
    if (_hasUserScrolled) {
      _dispatchProgressSync(force: true);
    }
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    setState(() {
      _isLoading = true;
      _isNotFound = false;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(journalRepositoryProvider);
      final fetched = await repo.getArticleById(widget.articleId);
      if (!mounted) return;

      if (fetched == null) {
        setState(() {
          _isLoading = false;
          _isNotFound = _article == null;
        });
        return;
      }

      setState(() {
        _article = fetched;
        _isLoading = false;
        _isNotFound = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final nextProgress =
        (_scrollController.offset / maxScroll).clamp(0.0, 1.0);
    _hasUserScrolled = true;
    _latestProgress = nextProgress;

    if ((_progressNotifier.value - nextProgress).abs() >= 0.004) {
      _progressNotifier.value = nextProgress;
    }

    _progressDebounceTimer?.cancel();
    _progressDebounceTimer = Timer(_progressSyncDebounce, () {
      _dispatchProgressSync();
    });
  }

  void _dispatchProgressSync({bool force = false}) {
    final callback = widget.onProgressSync;
    if (callback == null) return;
    if (!force && (_latestProgress - _lastSyncedProgress).abs() < 0.01) {
      return;
    }

    final totalMinutes = _article?.readTimeMinutes ?? 4;
    final remainingMinutes =
        (totalMinutes * (1.0 - _latestProgress)).ceil().clamp(0, totalMinutes);
    _lastSyncedProgress = _latestProgress;

    unawaited(
      callback(widget.articleId, _latestProgress, remainingMinutes).catchError(
        (_) {},
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    if (_isTogglingBookmark) return;
    final previousState = _isBookmarked;
    final nextState = !previousState;

    setState(() {
      _isBookmarked = nextState;
      _isTogglingBookmark = true;
    });

    final callback = widget.onBookmarkToggle;
    if (callback == null) {
      if (mounted) {
        setState(() => _isTogglingBookmark = false);
      }
      return;
    }

    try {
      final confirmed = await callback(widget.articleId, nextState);
      if (!mounted) return;
      setState(() {
        _isBookmarked = confirmed;
        _isTogglingBookmark = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isBookmarked = previousState;
        _isTogglingBookmark = false;
      });
    }
  }

  void _toggleFontSize() {
    setState(() {
      _isLargeText = !_isLargeText;
    });
  }

  String _topicLabel(JournalArticle article) {
    if (article.badgeLabel != null && article.badgeLabel!.trim().isNotEmpty) {
      return article.badgeLabel!.trim();
    }
    return switch (article.topic) {
      JournalTopic.all => 'Tri thức',
      JournalTopic.workout => 'Tập luyện',
      JournalTopic.nutrition => 'Dinh dưỡng',
      JournalTopic.recovery => 'Phục hồi',
      JournalTopic.habits => 'Thói quen',
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildSliverAppBar(tokens),
          SliverToBoxAdapter(
            child: _buildBody(tokens),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(SamanHomePalette tokens) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: tokens.canvas,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        key: const ValueKey('article_detail_back_button'),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(
          Icons.arrow_back_rounded,
          color: tokens.textPrimary,
          size: 22,
        ),
        tooltip: 'Quay lại',
        onPressed: () {
          if (_hasUserScrolled) {
            _dispatchProgressSync(force: true);
          }
          Navigator.of(context).pop();
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('article_detail_font_toggle'),
              onTap: _toggleFontSize,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isLargeText
                        ? tokens.greenBadgeBg
                        : tokens.cardSurfaceElevated,
                    borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                    border: Border.all(
                      color: _isLargeText
                          ? tokens.greenBadgeBorder
                          : tokens.borderSubtle,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Aa',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _isLargeText
                          ? tokens.greenAccent
                          : tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('article_detail_bookmark_button'),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(
            _isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: _isBookmarked ? tokens.greenAccent : tokens.textPrimary,
            size: 22,
          ),
          tooltip: _isBookmarked ? 'Bỏ lưu bài viết' : 'Lưu bài viết',
          onPressed: _toggleBookmark,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: ValueListenableBuilder<double>(
          valueListenable: _progressNotifier,
          builder: (context, progress, _) {
            return LinearProgressIndicator(
              key: const ValueKey('article_detail_progress_bar'),
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: tokens.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(SamanHomePalette tokens) {
    if (_isLoading && _article == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 120),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
          ),
        ),
      );
    }

    if (_errorMessage != null && _article == null) {
      return _buildErrorState(tokens);
    }

    if (_isNotFound || _article == null) {
      return _buildNotFoundState(tokens);
    }

    final article = _article!;
    final bodyFontSize = _isLargeText ? _largeFontSize : _standardFontSize;
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 36;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverHeader(article, tokens),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metadata row
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${article.readTimeMinutes} phút đọc',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Article title
                Text(
                  article.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: _isLargeText ? 24 : 22,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    height: 1.3,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 18),

                // Summary callout card
                if (article.summary.trim().isNotEmpty) ...[
                  _buildSummaryCallout(article.summary, tokens),
                  const SizedBox(height: 22),
                ],

                // Full content body or inline loading/retry
                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            tokens.greenAccent,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (article.contentBody != null &&
                    article.contentBody!.trim().isNotEmpty)
                  ..._buildContentBlocks(
                    article.contentBody!,
                    bodyFontSize,
                    tokens,
                  )
                else if (_errorMessage != null)
                  _buildInlineRetryCard(tokens),

                const SizedBox(height: 24),
                Divider(color: tokens.divider, height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 16,
                      color: tokens.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saman Journal • Nội dung nghiên cứu',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverHeader(JournalArticle article, SamanHomePalette tokens) {
    final badgeText = _topicLabel(article).toUpperCase();

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCoverImage(article.coverImageAsset, tokens),
          // Dark scrim gradient over cover image for consistent legibility in both themes
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x140C0D0E),
                    Color(0x590C0D0E),
                    Color(0xCC0C0D0E),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Topic badge positioned over the dark scrim
          Positioned(
            left: 20,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tokens.greenAccent,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
              ),
              child: Text(
                badgeText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(String source, SamanHomePalette tokens) {
    final trimmed = source.trim();
    final isNetwork =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');

    Widget fallback() {
      return Container(
        color: tokens.cardSurfaceElevated,
        child: Center(
          child: Icon(
            Icons.article_outlined,
            size: 42,
            color: tokens.textSecondary,
          ),
        ),
      );
    }

    if (trimmed.isEmpty) {
      return fallback();
    }

    if (isNetwork) {
      return Image.network(
        trimmed,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: tokens.cardSurfaceElevated,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.greenAccent),
              ),
            ),
          );
        },
      );
    }

    return Image.asset(
      trimmed,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }

  Widget _buildSummaryCallout(String summary, SamanHomePalette tokens) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(
          color: tokens.borderSubtle,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3.5,
              color: tokens.greenAccent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TÓM TẮT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: tokens.greenAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: _isLargeText ? 16 : 14.5,
                        fontWeight: FontWeight.w400,
                        color: tokens.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContentBlocks(
    String contentBody,
    double bodyFontSize,
    SamanHomePalette tokens,
  ) {
    final normalized = contentBody.replaceAll('\r\n', '\n').trim();
    final rawBlocks = normalized.split('\n\n');
    final widgets = <Widget>[];

    for (final raw in rawBlocks) {
      final block = raw.trim();
      if (block.isEmpty) continue;

      if (block.startsWith('## ')) {
        final heading = block.substring(3).trim();
        if (heading.isEmpty) continue;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: widgets.isEmpty ? 4 : 18,
              bottom: 8,
            ),
            child: Text(
              heading,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                height: 1.35,
                letterSpacing: -0.2,
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              block,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: bodyFontSize,
                fontWeight: FontWeight.w400,
                color: tokens.textPrimary,
                height: 1.65,
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildInlineRetryCard(SamanHomePalette tokens) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Không thể tải toàn bộ nội dung bài viết.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadArticle,
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.actionButtonSurface,
              foregroundColor: tokens.textPrimary,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
              elevation: 0,
            ),
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(SamanHomePalette tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 26,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Không thể tải bài viết',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Vui lòng kiểm tra kết nối mạng và thử lại.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _loadArticle,
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.actionButtonSurface,
              foregroundColor: tokens.textPrimary,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState(SamanHomePalette tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tokens.cardSurface,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(
              Icons.article_outlined,
              size: 26,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Không tìm thấy bài viết',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bài viết này có thể đã bị gỡ hoặc không còn khả dụng trong Saman Journal.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.actionButtonSurface,
              foregroundColor: tokens.textPrimary,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Quay lại'),
          ),
        ],
      ),
    );
  }
}
