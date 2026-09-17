// lib/screens/nutrition/widgets/meal_review_dialog.dart
import 'package:flutter/material.dart';
import '../../../models/ai_analysis_result.dart';

enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeExt on MealType {
  String get label => switch (this) {
        MealType.breakfast => 'Bữa sáng',
        MealType.lunch => 'Bữa trưa',
        MealType.dinner => 'Bữa tối',
        MealType.snack => 'Bữa phụ',
      };
  String get value => name;
}

class MealReviewDialog extends StatefulWidget {
  final AIAnalysisResult result;

  const MealReviewDialog({super.key, required this.result});

  static Future<MealLogData?> show(
    BuildContext context,
    AIAnalysisResult result,
  ) {
    return showModalBottomSheet<MealLogData>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MealReviewDialog(result: result),
    );
  }

  @override
  State<MealReviewDialog> createState() => _MealReviewDialogState();
}

class _MealReviewDialogState extends State<MealReviewDialog> {
  late AIAnalysisResult _current;
  late double _grams;
  MealType _mealType = MealType.lunch;
  String? _selectedLabel;

  @override
  void initState() {
    super.initState();
    _current = widget.result;
    _grams = widget.result.grams;
    _selectedLabel = widget.result.foodLabel;

    final hour = DateTime.now().hour;
    _mealType = hour < 10
        ? MealType.breakfast
        : hour < 14
            ? MealType.lunch
            : hour < 19
                ? MealType.dinner
                : MealType.snack;
  }

  void _onGramsChanged(double newGrams) {
    setState(() {
      _grams = newGrams;
      _current = _current.withGrams(newGrams);
    });
  }

  void _onRelabel(FoodPrediction selected) {
    setState(() {
      _current = _current.withLabel(selected).withGrams(_grams);
    });
  }

  void _confirm() {
    Navigator.of(context).pop(MealLogData(
      foodName: _current.foodName,
      foodLabel: _current.foodLabel,
      mealType: _mealType.value,
      grams: _grams,
      calories: _current.calories,
      protein: _current.protein,
      carbs: _current.carbs,
      fat: _current.fat,
      loggedAt: DateTime.now().toIso8601String(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLow = _current.lowConfidence;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isLow) ...[
              _Banner(
                color: Colors.orange.shade50,
                border: Colors.orange.shade200,
                icon: Icons.warning_amber_rounded,
                iconColor: Colors.orange,
                text:
                    'Ảnh chưa rõ (${(_current.confidence * 100).toInt()}%) — vui lòng kiểm tra lại',
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: Text(
                  _current.foodName,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _ConfidenceBadge(confidence: _current.confidence),
            ]),
            const SizedBox(height: 4),
            Text(
              '${_grams.toStringAsFixed(0)}g  •  ${_current.calories.toStringAsFixed(0)} kcal',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _MacroChip(
                  label: 'Protein',
                  value: _current.protein,
                  color: Colors.blue),
              const SizedBox(width: 8),
              _MacroChip(
                  label: 'Carbs', value: _current.carbs, color: Colors.orange),
              const SizedBox(width: 8),
              _MacroChip(label: 'Fat', value: _current.fat, color: Colors.red),
            ]),
            const SizedBox(height: 20),
            Text('Số gram', style: theme.textTheme.labelMedium),
            Row(children: [
              Expanded(
                child: Slider(
                  value: _grams.clamp(10, 500),
                  min: 10,
                  max: 500,
                  divisions: 49,
                  label: '${_grams.toStringAsFixed(0)}g',
                  onChanged: _onGramsChanged,
                ),
              ),
              SizedBox(
                width: 56,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffix: Text('g'),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  controller: TextEditingController(
                    text: _grams.toStringAsFixed(0),
                  )..selection = TextSelection.collapsed(
                      offset: _grams.toStringAsFixed(0).length,
                    ),
                  onSubmitted: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) _onGramsChanged(parsed);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Bữa ăn', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: MealType.values
                  .map((type) => ChoiceChip(
                        label: Text(type.label),
                        selected: _mealType == type,
                        onSelected: (_) => setState(() => _mealType = type),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            if (_current.top3.length > 1) ...[
              Text(
                'Không đúng? Chọn lại:',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              ..._current.top3.map((pred) => RadioListTile<String>(
                    dense: true,
                    title: Text(pred.foodName),
                    subtitle:
                        Text('${(pred.confidence * 100).toInt()}% confidence'),
                    value: pred.label,
                    groupValue: _selectedLabel,
                    onChanged: (_) {
                      setState(() => _selectedLabel = pred.label);
                      _onRelabel(pred);
                    },
                    contentPadding: EdgeInsets.zero,
                  )),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Huỷ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _confirm,
                  child: const Text('Lưu bữa này'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class MealLogData {
  final String foodName;
  final String foodLabel;
  final String mealType;
  final double grams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String loggedAt;

  const MealLogData({
    required this.foodName,
    required this.foodLabel,
    required this.mealType,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.loggedAt,
  });
}

class _Banner extends StatelessWidget {
  final Color color, border, iconColor;
  final IconData icon;
  final String text;
  const _Banner({
    required this.color,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.text,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});
  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toInt();
    final color = pct >= 70
        ? Colors.green
        : pct >= 40
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$pct%',
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(children: [
            Text(
              '${value.toStringAsFixed(1)}g',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}
