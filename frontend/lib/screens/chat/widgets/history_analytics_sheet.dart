import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/chat_controller.dart';
import '../../../presentation/providers/workout_history_providers.dart';
import '../../../services/analytics_service.dart';

class HistoryAnalyticsSheet extends ConsumerStatefulWidget {
  const HistoryAnalyticsSheet({super.key, this.service, this.onExecute});

  final AnalyticsService? service;
  final Future<String> Function(AnalyticsQuote quote)? onExecute;

  static Future<void> show(BuildContext context, {WidgetBuilder? builder}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder ?? (_) => const HistoryAnalyticsSheet(),
    );
  }

  @override
  ConsumerState<HistoryAnalyticsSheet> createState() =>
      _HistoryAnalyticsSheetState();
}

class _HistoryAnalyticsSheetState extends ConsumerState<HistoryAnalyticsSheet> {
  late final AnalyticsService _service = widget.service ?? AnalyticsService();
  int _rangeDays = 7;
  AnalyticsQuote? _quote;
  bool _loadingQuote = false;
  bool _executing = false;
  bool _executeFailed = false;
  String? _error;
  int _quoteRequestEpoch = 0;
  ProviderSubscription<int>? _authScopeSubscription;

  @override
  void initState() {
    super.initState();
    _authScopeSubscription = ref.listenManual<int>(
      workoutAuthScopeProvider,
      (_, __) {
        if (!mounted) return;
        setState(() => _quote = null);
        _loadQuote();
      },
    );
    _loadQuote();
  }

  @override
  void dispose() {
    _authScopeSubscription?.close();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final requestEpoch = ++_quoteRequestEpoch;
    setState(() {
      _loadingQuote = true;
      _quote = null;
      _error = null;
    });
    try {
      final quote = await _service.getPreflightQuote(_rangeDays);
      if (mounted && requestEpoch == _quoteRequestEpoch) {
        setState(() => _quote = quote);
      }
    } catch (_) {
      if (mounted && requestEpoch == _quoteRequestEpoch) {
        setState(() => _error = 'Không thể lấy báo giá lúc này.');
      }
    } finally {
      if (mounted && requestEpoch == _quoteRequestEpoch) {
        setState(() => _loadingQuote = false);
      }
    }
  }

  Future<void> _selectRange(int days) async {
    if (_executing || days == _rangeDays) return;
    setState(() => _rangeDays = days);
    await _loadQuote();
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (_executing || quote == null) return;
    setState(() => _executing = true);
    setState(() => _executeFailed = false);
    try {
      final report = await (widget.onExecute?.call(quote) ??
          ref
              .read(chatControllerProvider.notifier)
              .executeHistoryAnalytics(quote));
      if (mounted) Navigator.of(context).pop(report);
    } on QuoteExpiredException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Báo giá đã hết hạn. Đang lấy báo giá mới, vui lòng xác nhận lại.',
        ),
      ));
      await _loadQuote();
    } catch (_) {
      if (mounted) setState(() => _executeFailed = true);
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width > 600 ? 560 : width),
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(
              24,
              20,
              24,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Phân tích xu hướng',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in const [7, 14, 30])
                      ChoiceChip(
                        label: Text('$days ngày'),
                        selected: _rangeDays == days,
                        onSelected:
                            _executing ? null : (_) => _selectRange(days),
                      ),
                    const ChoiceChip(
                      label: Text(
                          '🔒 Từ khi đăng ký · Chưa hỗ trợ trong bản thử nghiệm'),
                      selected: false,
                      onSelected: null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loadingQuote)
                  const Center(child: CircularProgressIndicator())
                else if (_quote case final quote?)
                  _AnalyticsQuoteCard(quote: quote)
                else if (_error != null)
                  Text(_error!),
                if (_error != null && !_loadingQuote) ...[
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: _loadQuote,
                      child: const Text('Thử lấy báo giá lại')),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _quote == null || _loadingQuote || _executing
                      ? null
                      : _confirm,
                  child: _executing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_executeFailed
                          ? 'Thử lại phân tích'
                          : 'Xác nhận phân tích'),
                ),
                TextButton(
                  onPressed:
                      _executing ? null : () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsQuoteCard extends StatelessWidget {
  const _AnalyticsQuoteCard({required this.quote});

  final AnalyticsQuote quote;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phạm vi: ${quote.rangeDays} ngày'),
            Text(
                'Tìm thấy: ${quote.rawNutritionCount} bữa ăn, ${quote.workoutSessions} buổi tập'),
            if (quote.workoutTruncated)
              const Text('Đã lấy 72 buổi tập gần nhất để tối ưu hiệu năng'),
            Text('Ước lượng: ~${quote.estimatedTokens} tokens'),
          ],
        ),
      ),
    );
  }
}
