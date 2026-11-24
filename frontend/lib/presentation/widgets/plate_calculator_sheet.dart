import 'package:flutter/material.dart';

import '../../config/app_translations.dart';
import '../tokens/saman_workout_tokens.dart';

/// Opens the modal bottom sheet for calculating barbell plates per side.
Future<double?> showPlateCalculatorSheet(
  BuildContext context, {
  double initialWeightKg = 20.0,
  ValueChanged<double>? onApplyWeight,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PlateCalculatorSheet(
      initialWeightKg: initialWeightKg,
      onApplyWeight: onApplyWeight,
    ),
  );
}

class _PlateSpec {
  const _PlateSpec({
    required this.weightKg,
    required this.height,
    required this.width,
    required this.color,
    required this.labelColor,
  });

  final double weightKg;
  final double height;
  final double width;
  final Color color;
  final Color labelColor;
}

class _PlateCalculation {
  const _PlateCalculation({
    required this.perSideTargetKg,
    required this.platesPerSide,
    required this.remainderPerSideKg,
    required this.achievableTotalKg,
  });

  final double perSideTargetKg;
  final Map<double, int> platesPerSide;
  final double remainderPerSideKg;
  final double achievableTotalKg;

  bool get hasOddRemainder => remainderPerSideKg > 0.01;
}

/// Modal bottom sheet calculating greedy Olympic/standard barbell plates per side.
class PlateCalculatorSheet extends StatefulWidget {
  const PlateCalculatorSheet({
    super.key,
    this.initialWeightKg = 20.0,
    this.onApplyWeight,
  });

  final double initialWeightKg;
  final ValueChanged<double>? onApplyWeight;

  @override
  State<PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends State<PlateCalculatorSheet> {
  static const List<double> _barOptions = [20.0, 15.0, 10.0];
  static const List<double> _standardPlates = [
    25.0,
    20.0,
    15.0,
    10.0,
    5.0,
    2.5,
    1.25,
  ];

  late double _barWeightKg;
  late double _targetWeightKg;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _barWeightKg = 20.0;
    _targetWeightKg =
        widget.initialWeightKg > 0 ? widget.initialWeightKg : 20.0;
    _weightController = TextEditingController(
      text: _formatKg(_targetWeightKg),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  String _tr(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return AppTranslations.text(key, locale);
  }

  static String _formatKg(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-6) {
      return value.round().toString();
    }
    if (((value * 10) - (value * 10).roundToDouble()).abs() < 1e-6) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  static _PlateCalculation _calculatePlates({
    required double targetWeightKg,
    required double barWeightKg,
  }) {
    if (targetWeightKg <= barWeightKg) {
      return _PlateCalculation(
        perSideTargetKg: 0.0,
        platesPerSide: const {},
        remainderPerSideKg: 0.0,
        achievableTotalKg: barWeightKg,
      );
    }

    final perSideTarget = (targetWeightKg - barWeightKg) / 2.0;
    double remaining = perSideTarget;
    final counts = <double, int>{};

    for (final plate in _standardPlates) {
      final count = ((remaining + 1e-6) / plate).floor();
      if (count > 0) {
        counts[plate] = count;
        remaining -= count * plate;
      }
    }

    final loadedPerSide = perSideTarget - remaining;
    final achievableTotal = barWeightKg + (loadedPerSide * 2.0);

    return _PlateCalculation(
      perSideTargetKg: perSideTarget,
      platesPerSide: counts,
      remainderPerSideKg: remaining < 0 ? 0.0 : remaining,
      achievableTotalKg: achievableTotal,
    );
  }

  static _PlateSpec _specForPlate(double weightKg, SamanWorkoutPalette t) {
    if (weightKg >= 25.0) {
      return const _PlateSpec(
        weightKg: 25.0,
        height: 70,
        width: 14,
        color: Color(0xFFEF4444),
        labelColor: Colors.white,
      );
    }
    if (weightKg >= 20.0) {
      return const _PlateSpec(
        weightKg: 20.0,
        height: 64,
        width: 13,
        color: Color(0xFF3B82F6),
        labelColor: Colors.white,
      );
    }
    if (weightKg >= 15.0) {
      return const _PlateSpec(
        weightKg: 15.0,
        height: 56,
        width: 12,
        color: Color(0xFFF59E0B),
        labelColor: Color(0xFF0C0D0E),
      );
    }
    if (weightKg >= 10.0) {
      return const _PlateSpec(
        weightKg: 10.0,
        height: 48,
        width: 11,
        color: Color(0xFF10B981),
        labelColor: Colors.white,
      );
    }
    if (weightKg >= 5.0) {
      return _PlateSpec(
        weightKg: 5.0,
        height: 40,
        width: 10,
        color: t.isDark ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
        labelColor: t.isDark ? const Color(0xFF0F172A) : Colors.white,
      );
    }
    if (weightKg >= 2.5) {
      return _PlateSpec(
        weightKg: 2.5,
        height: 32,
        width: 9,
        color: t.isDark ? const Color(0xFF475569) : const Color(0xFF1E293B),
        labelColor: Colors.white,
      );
    }
    return const _PlateSpec(
      weightKg: 1.25,
      height: 26,
      width: 8,
      color: Color(0xFF94A3B8),
      labelColor: Color(0xFF0F172A),
    );
  }

  void _setTargetWeight(double nextWeight, {bool updateText = true}) {
    final clamped = nextWeight.clamp(0.0, 500.0);
    setState(() {
      _targetWeightKg = clamped;
      if (updateText) {
        final formatted = _formatKg(clamped);
        _weightController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    });
  }

  void _adjustWeight(double delta) {
    final next = (_targetWeightKg + delta).clamp(_barWeightKg, 500.0);
    _setTargetWeight(next);
  }

  void _selectBar(double barKg) {
    setState(() {
      _barWeightKg = barKg;
      if (_targetWeightKg < barKg) {
        _targetWeightKg = barKg;
        final formatted = _formatKg(barKg);
        _weightController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final calc = _calculatePlates(
      targetWeightKg: _targetWeightKg,
      barWeightKg: _barWeightKg,
    );

    final plateChips = <_PlateSpec>[];
    for (final entry in calc.platesPerSide.entries) {
      final spec = _specForPlate(entry.key, t);
      for (var i = 0; i < entry.value; i++) {
        plateChips.add(spec);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanWorkoutTokens.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: t.border),
          left: BorderSide(color: t.border),
          right: BorderSide(color: t.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingMd,
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingXl + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.borderHover,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingMd),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.emeraldBadgeBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: t.emeraldBadgeBorder),
                          ),
                          child: Icon(
                            Icons.calculate_outlined,
                            size: 18,
                            color: t.emeraldAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr(context, 'plate_calculator'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: t.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('plate_calc_close_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: t.textSecondary, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingMd),

              // Barbell selector
              Text(
                _tr(context, 'barbell_weight').toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: _barOptions.map((barKg) {
                  final isSelected = (_barWeightKg - barKg).abs() < 0.01;
                  final idx = _barOptions.indexOf(barKg);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: idx < _barOptions.length - 1 ? 8 : 0,
                      ),
                      child: InkWell(
                        key: ValueKey('plate_calc_bar_${barKg.toInt()}'),
                        onTap: () => _selectBar(barKg),
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? t.emeraldBadgeBg
                                : t.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusMd,
                            ),
                            border: Border.all(
                              color: isSelected
                                  ? t.emeraldBadgeBorder
                                  : t.borderSubtle,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${barKg.toInt()} kg',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? t.emeraldAccent
                                    : t.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // Target weight input + ±2.5 kg controls
              Text(
                _tr(context, 'target_weight').toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _WeightStepButton(
                    key: const ValueKey('plate_calc_minus_2_5'),
                    label: '-2.5',
                    palette: t,
                    onTap: () => _adjustWeight(-2.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: t.surfaceElevated,
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('plate_calc_target_input'),
                              controller: _weightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                              cursorColor: t.emeraldAccent,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                filled: false,
                              ),
                              onChanged: (raw) {
                                final normalized = raw.replaceAll(',', '.');
                                final parsed = double.tryParse(normalized);
                                if (parsed != null) {
                                  _setTargetWeight(parsed, updateText: false);
                                }
                              },
                            ),
                          ),
                          Text(
                            'kg',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _WeightStepButton(
                    key: const ValueKey('plate_calc_plus_2_5'),
                    label: '+2.5',
                    palette: t,
                    onTap: () => _adjustWeight(2.5),
                  ),
                ],
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // Visual Barbell Diagram
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: t.surfaceElevated,
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusLg,
                  ),
                  border: Border.all(color: t.borderSubtle),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 80,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _BarbellDiagram(
                            barWeightKg: _barWeightKg,
                            plates: plateChips,
                            palette: t,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _tr(context, 'per_side_plates').toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: t.textMuted,
                          ),
                        ),
                        Text(
                          '${_formatKg(calc.perSideTargetKg)} kg',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.emeraldAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (calc.platesPerSide.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _tr(context, 'bar_only_label'),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            color: t.textSecondary,
                          ),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: calc.platesPerSide.entries.map((entry) {
                            final spec = _specForPlate(entry.key, t);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: t.cardSurface,
                                borderRadius: BorderRadius.circular(
                                  SamanWorkoutTokens.radiusSm,
                                ),
                                border: Border.all(color: t.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: spec.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${entry.value}×${_formatKg(entry.key)}kg',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),

              if (calc.hasOddRemainder) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('plate_calc_odd_warning'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.amberAccent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(
                      SamanWorkoutTokens.radiusMd,
                    ),
                    border: Border.all(
                      color: t.amberAccent.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: t.amberAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tr(context, 'plate_odd_warning').replaceAll(
                            '{weight}',
                            _formatKg(calc.achievableTotalKg),
                          ),
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: t.amberAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (widget.onApplyWeight != null) ...[
                const SizedBox(height: SamanWorkoutTokens.spacingLg),
                SafeArea(
                  top: false,
                  child: ElevatedButton(
                    key: const ValueKey('plate_calc_apply_button'),
                    onPressed: () {
                      final applied = _targetWeightKg < _barWeightKg
                          ? _barWeightKg
                          : _targetWeightKg;
                      widget.onApplyWeight?.call(applied);
                      Navigator.of(context).pop(applied);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      backgroundColor: t.buttonPrimary,
                      foregroundColor: t.buttonPrimaryText,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                      ),
                    ),
                    child: Text(
                      '${_tr(context, 'apply_weight')} (${_formatKg(_targetWeightKg < _barWeightKg ? _barWeightKg : _targetWeightKg)} kg)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: t.buttonPrimaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightStepButton extends StatelessWidget {
  const _WeightStepButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final SamanWorkoutPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
          border: Border.all(color: palette.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarbellDiagram extends StatelessWidget {
  const _BarbellDiagram({
    required this.barWeightKg,
    required this.plates,
    required this.palette,
  });

  final double barWeightKg;
  final List<_PlateSpec> plates;
  final SamanWorkoutPalette palette;

  @override
  Widget build(BuildContext context) {
    final shaftColor =
        palette.isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final collarColor =
        palette.isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left sleeve tip
        Container(
          width: 14,
          height: 8,
          decoration: BoxDecoration(
            color: shaftColor,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(4),
            ),
          ),
        ),
        // Left plates (outermost smallest -> innermost largest)
        ...plates.reversed.map(
          (spec) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: spec.width,
            height: spec.height,
            decoration: BoxDecoration(
              color: spec.color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.black.withOpacity(0.18),
                width: 0.8,
              ),
            ),
          ),
        ),
        // Left collar
        Container(
          width: 8,
          height: 22,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: collarColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Center bar shaft with weight badge
        SizedBox(
          width: 96,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 10,
                color: shaftColor,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.cardSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '${barWeightKg.toInt()}kg',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Right collar
        Container(
          width: 8,
          height: 22,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: collarColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Right plates (innermost largest -> outermost smallest)
        ...plates.map(
          (spec) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: spec.width,
            height: spec.height,
            decoration: BoxDecoration(
              color: spec.color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.black.withOpacity(0.18),
                width: 0.8,
              ),
            ),
          ),
        ),
        // Right sleeve tip
        Container(
          width: 14,
          height: 8,
          decoration: BoxDecoration(
            color: shaftColor,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}
