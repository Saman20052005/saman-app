import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_translations.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Tactile water card with 8-segment ratio meter, +250ml quick action & custom ml sheet.
class NutritionWaterCard extends StatelessWidget {
  final int currentWater;
  final int targetWater;
  final bool hasTarget;
  final bool isUpdating;
  final VoidCallback? onAddWater;
  final ValueChanged<int>? onAddCustomWater;

  const NutritionWaterCard({
    super.key,
    required this.currentWater,
    required this.targetWater,
    this.hasTarget = true,
    this.isUpdating = false,
    this.onAddWater,
    this.onAddCustomWater,
  });

  Future<void> _openCustomWaterSheet(BuildContext context) async {
    final callback = onAddCustomWater;
    if (callback == null || isUpdating) return;
    final selectedMl = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CustomWaterAmountSheet(),
    );
    if (selectedMl != null && context.mounted) {
      callback(selectedMl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final tokens = SamanHomeTokens.of(context);
    final isDark = palette.isDark;
    final cardBg = isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderCol = isDark ? const Color(0xFF26282F) : tokens.border;
    final pillBg = isDark ? const Color(0xFF212328) : tokens.cardSurfaceElevated;
    final waterAccent = isDark ? const Color(0xFF4EDEAF) : tokens.waterCyan;
    final inkPrimary = isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final inkMuted = isDark ? const Color(0xFF9CA3AF) : tokens.textSecondary;
    final inkRemaining = isDark ? const Color(0xFFCBD5E1) : tokens.textSecondary;
    final emptySegment = isDark ? const Color(0xFF26282F) : tokens.progressTrack;

    final bool isTargetValid = hasTarget && targetWater > 0;
    final int remaining = isTargetValid ? targetWater - currentWater : 0;
    final bool goalReached = isTargetValid && remaining <= 0;
    final double fraction = isTargetValid
        ? (currentWater / targetWater).clamp(0.0, 1.0)
        : 0.0;
    final int percentage = isTargetValid
        ? (currentWater / targetWater * 100).round()
        : 0;
    final numberFormat = NumberFormat('#,###');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.water_drop_rounded,
                    size: 18,
                    color: waterAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'WATER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: inkMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isTargetValid
                      ? (goalReached
                          ? 'Goal reached!'
                          : '${numberFormat.format(remaining)} ml remaining')
                      : 'Set hydration target',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isTargetValid && goalReached
                        ? waterAccent
                        : inkRemaining,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Middle Row: Value comparison & +250 ml button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            numberFormat.format(currentWater),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: inkPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isTargetValid
                                ? '/ ${numberFormat.format(targetWater)} ml'
                                : '/ — ml',
                            style: TextStyle(
                              fontSize: 12,
                              color: inkMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTargetValid
                          ? '$percentage% of daily hydration'
                          : 'Hydration goal not set',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onAddCustomWater != null) ...[
                    Tooltip(
                      message: context.tr('water_custom_tooltip'),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey('water_custom_input_button'),
                          onTap: isUpdating
                              ? null
                              : () => _openCustomWaterSheet(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderCol),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: isUpdating ? inkMuted : waterAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Tactile +250 ml button with double-tap prevention
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isUpdating ? null : onAddWater,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderCol),
                        ),
                        child: Center(
                          child: isUpdating
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: waterAccent,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 16,
                                      color: waterAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '250 ml',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: inkPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. 8-segment progress strip
          Row(
            children: List.generate(8, (index) {
              final double startThreshold = index / 8.0;
              final double endThreshold = (index + 1) / 8.0;

              final bool isFullyFilled = fraction >= endThreshold;
              final bool isPartiallyFilled =
                  !isFullyFilled && fraction > startThreshold;

              Color segmentColor;
              BoxBorder? border;

              if (isFullyFilled) {
                segmentColor = waterAccent;
              } else if (isPartiallyFilled) {
                segmentColor = waterAccent.withOpacity(0.25);
                border = Border.all(
                  color: waterAccent.withOpacity(0.6),
                );
              } else {
                segmentColor = emptySegment;
              }

              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(
                    right: index == 7 ? 0 : 5,
                  ),
                  decoration: BoxDecoration(
                    color: segmentColor,
                    borderRadius: BorderRadius.circular(999),
                    border: border,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CustomWaterAmountSheet extends StatefulWidget {
  const _CustomWaterAmountSheet();

  @override
  State<_CustomWaterAmountSheet> createState() =>
      _CustomWaterAmountSheetState();
}

class _CustomWaterAmountSheetState extends State<_CustomWaterAmountSheet> {
  static const List<int> _quickAmounts = [100, 350, 500, 750];

  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  int? _selectedQuickAmount;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectQuickAmount(int amount) {
    final text = '$amount';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _selectedQuickAmount = amount;
      _errorText = null;
    });
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1 || parsed > 5000) {
      setState(() {
        _errorText = context.tr('water_custom_error_invalid');
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDark = palette.isDark;

    final sheetBg = isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final pillBg = isDark ? const Color(0xFF212328) : tokens.cardSurfaceElevated;
    final borderCol = isDark ? const Color(0xFF26282F) : tokens.border;
    final waterAccent = isDark ? const Color(0xFF4EDEAF) : tokens.waterCyan;
    final inkPrimary = isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final inkMuted = isDark ? const Color(0xFF9CA3AF) : tokens.textSecondary;
    final errorColor = isDark ? const Color(0xFFEF4444) : palette.danger;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderCol)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + bottomInset + safeBottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.water_drop_rounded,
                  size: 20,
                  color: waterAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('water_custom_title'),
                    style: textTheme.titleMedium?.copyWith(
                      color: inkPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    color: inkMuted,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('water_custom_subtitle'),
              style: textTheme.bodySmall?.copyWith(
                color: inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('water_custom_quick_label'),
              style: textTheme.labelMedium?.copyWith(
                color: inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((amount) {
                final isSelected = _selectedQuickAmount == amount;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectQuickAmount(amount),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? waterAccent.withOpacity(0.16)
                            : pillBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? waterAccent : borderCol,
                        ),
                      ),
                      child: Text(
                        '+$amount ml',
                        style: textTheme.labelLarge?.copyWith(
                          color: isSelected ? waterAccent : inkPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('water_custom_ml_input'),
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: textTheme.titleMedium?.copyWith(
                color: inkPrimary,
                fontWeight: FontWeight.w600,
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value.trim());
                setState(() {
                  _selectedQuickAmount =
                      _quickAmounts.contains(parsed) ? parsed : null;
                  if (_errorText != null) {
                    _errorText = null;
                  }
                });
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: context.tr('water_custom_hint'),
                hintStyle: textTheme.bodyMedium?.copyWith(color: inkMuted),
                suffixText: 'ml',
                suffixStyle: textTheme.labelLarge?.copyWith(
                  color: inkMuted,
                  fontWeight: FontWeight.w600,
                ),
                errorText: _errorText,
                errorStyle: textTheme.bodySmall?.copyWith(color: errorColor),
                filled: true,
                fillColor: pillBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderCol),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderCol),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: waterAccent, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: errorColor),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: errorColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: inkMuted,
                        side: BorderSide(color: borderCol),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        context.tr('water_custom_cancel'),
                        style: textTheme.labelLarge?.copyWith(
                          color: inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      key: const ValueKey('water_custom_submit_button'),
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: waterAccent,
                        foregroundColor:
                            isDark ? const Color(0xFF0C0D0E) : palette.onAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        context.tr('water_custom_submit'),
                        style: textTheme.labelLarge?.copyWith(
                          color: isDark
                              ? const Color(0xFF0C0D0E)
                              : palette.onAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
