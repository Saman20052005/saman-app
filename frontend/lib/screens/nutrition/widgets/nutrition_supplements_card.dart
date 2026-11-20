import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_theme.dart';
import '../../../features/nutrition/presentation/providers/recipes_supplements_provider.dart';
import '../../../models/nutrition_model.dart';

String _vnNowHHmm() {
  final vnNow = DateTime.now().toUtc().add(const Duration(hours: 7));
  final hh = vnNow.hour.toString().padLeft(2, '0');
  final mm = vnNow.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatSupplementAmount(double amount) {
  if (amount == amount.roundToDouble()) {
    return amount.toInt().toString();
  }
  return amount.toString();
}

class NutritionSupplementsCard extends ConsumerWidget {
  final String dateStr;
  final List<Supplement> fallbackSupplements;

  const NutritionSupplementsCard({
    super.key,
    required this.dateStr,
    this.fallbackSupplements = const [],
  });

  Future<void> _openLogSheet(BuildContext context) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupplementLogSheet(dateStr: dateStr),
    );
  }

  Future<void> _quickAdd(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> payload,
  ) async {
    final ok = await ref
        .read(supplementsByDateProvider(dateStr).notifier)
        .addSupplement(payload);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể ghi nhận thực phẩm bổ sung. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = SamanPalette.of(context);
    final isDark = palette.isDark;
    final cardBg = isDark ? const Color(0xFF16171B) : palette.surface;
    final borderColor = isDark ? const Color(0xFF26282F) : palette.border;
    final pillBg = isDark ? const Color(0xFF212328) : palette.surfaceElevated;
    final emeraldAccent = isDark ? const Color(0xFF10B981) : palette.accent;
    final textPrimary = isDark ? const Color(0xFFF9FAFB) : palette.textPrimary;
    final textSecondary =
        isDark ? const Color(0xFF9CA3AF) : palette.textSecondary;

    final supplementsAsync = ref.watch(supplementsByDateProvider(dateStr));
    final List<Supplement> items =
        supplementsAsync.valueOrNull ?? fallbackSupplements;

    final quickChips = <({String label, Map<String, dynamic> Function() payload})>[
      (
        label: 'Creatine 5g',
        payload: () => {
              'name': 'Creatine Monohydrate',
              'amount': 5,
              'unit': 'g',
              'date': dateStr,
              'timing': _vnNowHHmm(),
            },
      ),
      (
        label: 'Whey 1 scoop',
        payload: () => {
              'name': 'Whey Protein',
              'amount': 1,
              'unit': 'scoop',
              'date': dateStr,
              'timing': _vnNowHHmm(),
            },
      ),
      (
        label: 'Multivitamin',
        payload: () => {
              'name': 'Multivitamin',
              'amount': 1,
              'unit': 'viên',
              'date': dateStr,
              'timing': _vnNowHHmm(),
            },
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 18,
                    color: emeraldAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SUPPLEMENTS',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openLogSheet(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: emeraldAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Log',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
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
          const SizedBox(height: 12),

          if (items.isEmpty) ...[
            Text(
              'Ghi nhanh 1 chạm:',
              style: TextStyle(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickChips.map((chip) {
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _quickAdd(context, ref, chip.payload()),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            size: 14,
                            color: emeraldAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chip.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 16,
                      thickness: 1,
                      color: borderColor,
                    ),
                  _SupplementRow(
                    item: items[i],
                    onDelete: (items[i].id != null && items[i].id!.isNotEmpty)
                        ? () {
                            ref
                                .read(supplementsByDateProvider(dateStr).notifier)
                                .deleteSupplement(items[i].id!);
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplementRow extends StatelessWidget {
  final Supplement item;
  final VoidCallback? onDelete;

  const _SupplementRow({
    required this.item,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final isDark = palette.isDark;
    final textPrimary = isDark ? const Color(0xFFF9FAFB) : palette.textPrimary;
    final textSecondary =
        isDark ? const Color(0xFF9CA3AF) : palette.textSecondary;
    final emeraldAccent = isDark ? const Color(0xFF10B981) : palette.accent;

    final dosageText = (item.dosage != null && item.dosage!.trim().isNotEmpty)
        ? item.dosage!.trim()
        : '${_formatSupplementAmount(item.amount)} ${item.unit}'.trim();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    dosageText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: emeraldAccent,
                    ),
                  ),
                  if (item.time.trim().isNotEmpty) ...[
                    Text(
                      ' · ',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                    Text(
                      item.time.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            onPressed: onDelete,
            tooltip: 'Xoá',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: textSecondary,
            ),
          ),
      ],
    );
  }
}

class SupplementLogSheet extends ConsumerStatefulWidget {
  final String dateStr;

  const SupplementLogSheet({
    super.key,
    required this.dateStr,
  });

  @override
  ConsumerState<SupplementLogSheet> createState() => _SupplementLogSheetState();
}

class _SupplementLogSheetState extends ConsumerState<SupplementLogSheet> {
  static const List<String> _units = ['g', 'scoop', 'viên', 'ml'];
  static const List<String> _timings = ['Sáng', 'Trước tập', 'Sau tập', 'Tối'];

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  String _selectedUnit = 'g';
  String _selectedTiming = 'Sáng';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _amountController = TextEditingController(text: '5');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên thực phẩm bổ sung.'),
        ),
      );
      return;
    }

    final parsedAmount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '.'));
    final amount = (parsedAmount != null && parsedAmount > 0) ? parsedAmount : 1.0;

    setState(() => _isSaving = true);

    final payload = <String, dynamic>{
      'name': name,
      'amount': amount,
      'unit': _selectedUnit,
      'timing': _selectedTiming,
      'date': widget.dateStr,
    };

    final ok = await ref
        .read(supplementsByDateProvider(widget.dateStr).notifier)
        .addSupplement(payload);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lưu thực phẩm bổ sung. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);
    final isDark = palette.isDark;
    final cardBg = isDark ? const Color(0xFF16171B) : palette.surface;
    final borderColor = isDark ? const Color(0xFF26282F) : palette.border;
    final pillBg = isDark ? const Color(0xFF212328) : palette.surfaceElevated;
    final emeraldAccent = isDark ? const Color(0xFF10B981) : palette.accent;
    final primaryCtaBg = isDark ? const Color(0xFFF9FAFB) : palette.accent;
    final primaryCtaText = isDark ? const Color(0xFF0C0D0E) : palette.onAccent;
    final textPrimary = isDark ? const Color(0xFFF9FAFB) : palette.textPrimary;
    final textSecondary =
        isDark ? const Color(0xFF9CA3AF) : palette.textSecondary;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: borderColor),
          left: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 20,
                      color: emeraldAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ghi nhận Supplement',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tên thực phẩm bổ sung
            Text(
              'Tên thực phẩm bổ sung',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'VD: Creatine Monohydrate, Whey Protein...',
                hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                filled: true,
                fillColor: pillBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: emeraldAccent),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Số lượng
            Text(
              'Số lượng',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '5',
                hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                filled: true,
                fillColor: pillBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: emeraldAccent),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Đơn vị (pill)
            Text(
              'Đơn vị',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _units.map((unit) {
                final selected = _selectedUnit == unit;
                return GestureDetector(
                  onTap: () => setState(() => _selectedUnit = unit),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? emeraldAccent.withOpacity(0.16)
                          : pillBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? emeraldAccent : borderColor,
                      ),
                    ),
                    child: Text(
                      unit,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? emeraldAccent : textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Thời điểm (pill)
            Text(
              'Thời điểm',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _timings.map((timing) {
                final selected = _selectedTiming == timing;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTiming = timing),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? emeraldAccent.withOpacity(0.16)
                          : pillBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? emeraldAccent : borderColor,
                      ),
                    ),
                    child: Text(
                      timing,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? emeraldAccent : textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Primary CTA Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSaving ? null : _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryCtaBg,
                  foregroundColor: primaryCtaText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryCtaText,
                        ),
                      )
                    : Text(
                        'Lưu',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primaryCtaText,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
