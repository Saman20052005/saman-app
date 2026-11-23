import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_translations.dart';
import '../../../controllers/chat_controller.dart';
import '../../../features/membership/domain/models/membership_plan.dart';
import '../../../features/membership/presentation/providers/membership_providers.dart';
import '../../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../../../features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import '../../../presentation/providers/workout_history_providers.dart';
import '../../../services/analytics_service.dart';
import '../tokens/saman_chat_tokens.dart';

const bool _kEnableAiPaywall =
    bool.fromEnvironment('ENABLE_AI_PAYWALL', defaultValue: false);

class HistoryAnalyticsSheet extends ConsumerStatefulWidget {
  const HistoryAnalyticsSheet({
    super.key,
    this.service,
    this.onExecute,
    this.isDemo = false,
    this.initialQuote,
  });

  final AnalyticsService? service;
  final Future<String> Function(AnalyticsQuote quote)? onExecute;
  final bool isDemo;
  final AnalyticsQuote? initialQuote;

  static Future<void> show(
    BuildContext context, {
    WidgetBuilder? builder,
    AnalyticsService? service,
    bool isDemo = false,
  }) {
    final t = SamanChatTokens.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor:
          t.isDark ? const Color(0xBF000000) : const Color(0x660F172A),
      builder: builder ??
          (_) => HistoryAnalyticsSheet(
                service: service,
                isDemo: isDemo,
              ),
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
  bool _paywallBlocked = false;
  String? _error;
  int _quoteRequestEpoch = 0;
  ProviderSubscription<int>? _authScopeSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuote != null) {
      _quote = widget.initialQuote;
      _rangeDays = widget.initialQuote!.rangeDays;
    }
    _authScopeSubscription = ref.listenManual<int>(
      workoutAuthScopeProvider,
      (_, __) {
        if (!mounted) return;
        setState(() => _quote = null);
        _loadQuote();
      },
    );
    if (widget.initialQuote == null) {
      _loadQuote();
    }
  }

  @override
  void dispose() {
    _authScopeSubscription?.close();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final targetDays = _rangeDays;
    final requestEpoch = ++_quoteRequestEpoch;
    setState(() {
      _loadingQuote = true;
      _quote = null;
      _error = null;
      _paywallBlocked = false;
    });
    try {
      final quote = await _service.getPreflightQuote(targetDays);
      if (mounted &&
          requestEpoch == _quoteRequestEpoch &&
          targetDays == _rangeDays &&
          quote.rangeDays == _rangeDays) {
        setState(() => _quote = quote);
      }
    } on DioException catch (e) {
      if (mounted &&
          requestEpoch == _quoteRequestEpoch &&
          targetDays == _rangeDays) {
        if (e.response?.statusCode == 403) {
          setState(() {
            _paywallBlocked = true;
            _error = null;
            _executeFailed = false;
          });
        } else {
          setState(() => _error = 'quote_fetch_error');
        }
      }
    } catch (_) {
      if (mounted &&
          requestEpoch == _quoteRequestEpoch &&
          targetDays == _rangeDays) {
        setState(() => _error = 'quote_fetch_error');
      }
    } finally {
      if (mounted && requestEpoch == _quoteRequestEpoch) {
        setState(() => _loadingQuote = false);
      }
    }
  }

  Future<void> _selectRange(int days) async {
    if (_executing || days == _rangeDays) return;
    setState(() {
      _rangeDays = days;
      _quote = null;
      if (days == 7 || days == 14) {
        _paywallBlocked = false;
      }
    });
    await _loadQuote();
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (_executing || quote == null || quote.rangeDays != _rangeDays) return;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          context.tr('quote_expired_msg'),
        ),
      ));
      await _loadQuote();
    } on DioException catch (e) {
      if (mounted) {
        if (e.response?.statusCode == 403) {
          setState(() {
            _paywallBlocked = true;
            _error = null;
            _executeFailed = false;
          });
        } else {
          setState(() => _executeFailed = true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _executeFailed = true);
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final accountState = ref.watch(accountMembershipProvider);
    final hasExtendedMemory = accountState.entitlements.any(
      (e) =>
          e['benefit_id'] == 'ai.extended_memory' && e['status'] == 'granted',
    );
    final quote = _quote;
    final isMatchingQuote = quote != null && quote.rangeDays == _rangeDays;
    final hasData = isMatchingQuote &&
        (quote.rawNutritionCount > 0 || quote.workoutSessions > 0);
    final canConfirm = isMatchingQuote &&
        !_loadingQuote &&
        !_executing &&
        !_paywallBlocked &&
        (!widget.isDemo ? true : hasData);

    final t = SamanChatTokens.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width > 600 ? 560 : width),
        child: Container(
          decoration: BoxDecoration(
            color: t.isDark ? const Color(0xFF131922) : t.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28.0)),
            border: Border.all(
              color: t.isDark ? const Color(0x14FFFFFF) : t.border,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: t.isDark
                    ? const Color(0xD9000000)
                    : const Color(0x1F0F172A),
                offset: const Offset(0, -12),
                blurRadius: 40.0,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20.0,
                12.0,
                20.0,
                16.0 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Drag Handle
                  Center(
                    child: Container(
                      width: 40.0,
                      height: 4.0,
                      decoration: BoxDecoration(
                        color: t.isDark ? const Color(0x40808080) : t.border,
                        borderRadius: BorderRadius.circular(2.0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),

                  // 2. Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Icon(
                          Icons.trending_up_rounded,
                          size: 22.0,
                          color: t.isDark
                              ? const Color(0xFFCBD5E1)
                              : t.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('trend_analytics_title'),
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w600,
                                color: t.textWhite,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              context.tr('trend_analytics_desc'),
                              style: TextStyle(
                                fontSize: 12.0,
                                color: t.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _executing
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20.0,
                          color: t.textMuted,
                        ),
                        splashRadius: 20.0,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36.0,
                          minHeight: 36.0,
                        ),
                        tooltip: context.tr('dialog_close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),

                  // 3. Time Range Section
                  Text(
                    context.tr('time_range_header'),
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8.0),

                  // Segmented Control Pill
                  Container(
                    height: 44.0,
                    padding: const EdgeInsets.all(3.0),
                    decoration: BoxDecoration(
                      color: t.isDark
                          ? const Color(0xFF161D26)
                          : t.surfaceElevated,
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(
                        color: t.isDark ? const Color(0x0DFFFFFF) : t.border,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final days in const [7, 14, 30])
                          Expanded(
                            child: _TimeRangeTab(
                              days: days,
                              isSelected: _rangeDays == days,
                              enabled: !_executing,
                              showLock: days == 30 &&
                                  ((_kEnableAiPaywall && !hasExtendedMemory) ||
                                      (_paywallBlocked && _rangeDays == 30)),
                              onTap: () => _selectRange(days),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6.0),

                  // Locked row: Từ khi đăng ký
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14.0,
                          color: t.textMuted,
                        ),
                        const SizedBox(width: 6.0),
                        Text(
                          context.tr('since_registration'),
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            color: t.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            context.tr('unsupported_in_preview'),
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.0,
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14.0),

                  // 4. Data Preview Card
                  if (_paywallBlocked)
                    _PaywallBlockedCard(
                      onUpgradeTap: () async {
                        final selectedTier = await showUpgradeBottomSheet(
                          context,
                          tier: MembershipTier.pro,
                        );
                        if (selectedTier != null && context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlanDetailScreen(tier: selectedTier),
                            ),
                          );
                        }
                      },
                    )
                  else
                    _PreviewDataCard(
                      rangeDays: _rangeDays,
                      quote: isMatchingQuote ? _quote : null,
                      loading: _loadingQuote,
                      error: _error,
                      isDemo: widget.isDemo,
                      onRetry: _loadQuote,
                    ),
                  const SizedBox(height: 14.0),

                  // 5. Context & Scope guidance (Only if hasData)
                  if (hasData && !_loadingQuote && !_paywallBlocked) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('saman_will_analyze_header'),
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.8,
                              color: t.isDark
                                  ? const Color(0xFFA3A3A3)
                                  : t.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            context.tr('saman_analyze_scope_desc'),
                            style: TextStyle(
                              fontSize: 12.0,
                              color: t.isDark
                                  ? const Color(0xFFE2E8F0)
                                  : t.textPrimary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          Text(
                            context.tr('analytics_result_destination'),
                            style: TextStyle(
                              fontSize: 12.0,
                              color: t.isDark
                                  ? const Color(0xFFA3A3A3)
                                  : t.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14.0),
                  ],

                  // 6. Action buttons
                  // Primary Confirm Button
                  SizedBox(
                    width: double.infinity,
                    height: 48.0,
                    child: FilledButton(
                      onPressed: canConfirm ? _confirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: t.isDark
                            ? const Color(0xFF262F3D)
                            : t.greenAccent,
                        disabledBackgroundColor: t.isDark
                            ? Colors.white.withOpacity(0.05)
                            : t.composerSendDisabledBg,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: t.isDark
                            ? const Color(0xFF94A3B8)
                            : t.composerSendDisabledIcon,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24.0),
                          side: BorderSide(
                            color: t.isDark
                                ? (canConfirm
                                    ? const Color(0x0FFFFFFF)
                                    : const Color(0x0DFFFFFF))
                                : Colors.transparent,
                            width: 1.0,
                          ),
                        ),
                        elevation: canConfirm ? 1 : 0,
                        shadowColor: t.isDark
                            ? const Color(0x1F000000)
                            : const Color(0x140F172A),
                        padding: EdgeInsets.zero,
                      ),
                      child: _executing
                          ? const SizedBox.square(
                              dimension: 18.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _executeFailed
                                  ? context.tr('retry_analytics')
                                  : context.tr('confirm_analytics'),
                              style: TextStyle(
                                fontSize: 14.0,
                                fontWeight: FontWeight.w600,
                                color: canConfirm
                                    ? Colors.white
                                    : (t.isDark
                                        ? const Color(0xFF94A3B8)
                                        : t.composerSendDisabledIcon),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4.0),

                  // Secondary Cancel Button
                  SizedBox(
                    width: double.infinity,
                    height: 44.0,
                    child: TextButton(
                      onPressed:
                          _executing ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: t.textMuted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22.0),
                        ),
                      ),
                      child: Text(
                        context.tr('cancel_action'),
                        style: TextStyle(
                          fontSize: 13.0,
                          fontWeight: FontWeight.w500,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRangeTab extends StatelessWidget {
  const _TimeRangeTab({
    required this.days,
    required this.isSelected,
    required this.enabled,
    this.showLock = false,
    required this.onTap,
  });

  final int days;
  final bool isSelected;
  final bool enabled;
  final bool showLock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: context.tr('days_unit_format').replaceAll('{days}', '$days'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20.0),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 38.0,
            decoration: BoxDecoration(
              color: isSelected
                  ? (t.isDark ? const Color(0xFF262F3D) : t.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20.0),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: t.isDark
                            ? const Color(0x1A000000)
                            : const Color(0x140F172A),
                        offset: const Offset(0, 1),
                        blurRadius: 2.0,
                      ),
                    ]
                  : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected) ...[
                    Icon(
                      Icons.check_rounded,
                      size: 14.0,
                      color: t.isDark ? const Color(0xFFE2E8F0) : t.greenAccent,
                    ),
                    const SizedBox(width: 4.0),
                  ],
                  Text(
                    context.tr('days_unit_format').replaceAll('{days}', '$days'),
                    style: TextStyle(
                      fontSize: isSelected ? 12.5 : 12.0,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? t.greenAccent : t.textMuted,
                    ),
                  ),
                  if (showLock) ...[
                    const SizedBox(width: 4.0),
                    Icon(
                      Icons.lock_outline,
                      size: 13.0,
                      color: t.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewDataCard extends StatelessWidget {
  const _PreviewDataCard({
    required this.rangeDays,
    required this.quote,
    required this.loading,
    required this.error,
    required this.isDemo,
    required this.onRetry,
  });

  final int rangeDays;
  final AnalyticsQuote? quote;
  final bool loading;
  final String? error;
  final bool isDemo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final isMatching = quote != null && quote!.rangeDays == rangeDays;
    final meals = isMatching ? (quote?.rawNutritionCount ?? 0) : 0;
    final workouts = isMatching ? (quote?.workoutSessions ?? 0) : 0;
    final hasData = isMatching && (meals > 0 || workouts > 0);
    final dividerColor = t.isDark ? const Color(0x0FFFFFFF) : t.border;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF17202B) : t.surfaceElevated,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: t.isDark ? const Color(0x12FFFFFF) : t.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic Title Row
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('data_in_past_days_format').replaceAll('{days}', '$rangeDays'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: t.isDark ? const Color(0xFFE2E8F0) : t.textPrimary,
                  ),
                ),
              ),
              if (isDemo)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: t.isDark ? Colors.white.withOpacity(0.05) : t.surface,
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: t.isDark ? Colors.white.withOpacity(0.1) : t.border,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    context.tr('sample_data_badge'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: t.isDark ? const Color(0xFFA3A3A3) : t.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12.0),

          // Two Stat Columns with Divider
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$meals',
                      style: TextStyle(
                        fontSize: 26.0,
                        fontWeight: FontWeight.bold,
                        color: t.textWhite,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      context.tr('unit_meals'),
                      style: TextStyle(
                        fontSize: 12.0,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1.0,
                height: 42.0,
                color: t.isDark ? const Color(0x14FFFFFF) : t.border,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$workouts',
                      style: TextStyle(
                        fontSize: 26.0,
                        fontWeight: FontWeight.bold,
                        color: t.textWhite,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      context.tr('unit_workouts'),
                      style: TextStyle(
                        fontSize: 12.0,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (loading) ...[
            const SizedBox(height: 14.0),
            Center(
              child: SizedBox.square(
                dimension: 20.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  color: t.greenAccent,
                ),
              ),
            ),
          ] else if (error != null) ...[
            const SizedBox(height: 10.0),
            Text(
              context.tr(error!),
              style: TextStyle(
                fontSize: 12.0,
                color: t.isDark
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFDC2626),
              ),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                context.tr('retry_fetch_quote'),
                style: TextStyle(fontSize: 12.0, color: t.greenAccent),
              ),
            ),
          ] else if (hasData) ...[
            const SizedBox(height: 12.0),
            // Coverage line if activeDays > 0
            if (isMatching && quote!.activeDays > 0)
              Text(
                context.tr('logged_days_format')
                    .replaceAll('{active}', '${quote!.activeDays}')
                    .replaceAll('{total}', '${quote!.rangeDays}'),
                style: TextStyle(
                  fontSize: 12.0,
                  color: t.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 10.0),
            Divider(
              color: dividerColor,
              height: 1.0,
              thickness: 1.0,
            ),
            const SizedBox(height: 10.0),
            // Token row
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('estimated_tokens'),
                    style: TextStyle(
                      fontSize: 12.0,
                      color: t.textMuted,
                    ),
                  ),
                ),
                Text(
                  context.tr('tokens_format').replaceAll('{count}', '${quote!.estimatedTokens}'),
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: t.greenAccent,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Frame 2: Empty State
            const SizedBox(height: 12.0),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                rangeDays == 7
                    ? context.tr('no_logs_range_7')
                    : context.tr('no_logs_range_other'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.0,
                  color: t.isDark ? const Color(0xFFA3A3A3) : t.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            if (isMatching && quote != null && !isDemo) ...[
              const SizedBox(height: 10.0),
              Divider(
                color: dividerColor,
                height: 1.0,
                thickness: 1.0,
              ),
              const SizedBox(height: 10.0),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('estimated_tokens'),
                      style: TextStyle(
                        fontSize: 12.0,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    context.tr('tokens_format').replaceAll('{count}', '${quote!.estimatedTokens}'),
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: t.greenAccent,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PaywallBlockedCard extends StatelessWidget {
  const _PaywallBlockedCard({
    required this.onUpgradeTap,
  });

  final VoidCallback onUpgradeTap;

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF17202B) : t.surfaceElevated,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: t.greenAccent.withOpacity(0.35),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: t.greenAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 18.0,
                  color: t.greenAccent,
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  'Phân tích lịch sử 30 ngày dành cho hội viên nâng cao',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: t.isDark ? const Color(0xFFE2E8F0) : t.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),
          SizedBox(
            height: 44.0,
            child: FilledButton(
              onPressed: onUpgradeTap,
              style: FilledButton.styleFrom(
                backgroundColor: t.greenAccent,
                foregroundColor:
                    t.isDark ? const Color(0xFF0B1117) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              child: const Text(
                'Mở khóa gói hội viên',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
