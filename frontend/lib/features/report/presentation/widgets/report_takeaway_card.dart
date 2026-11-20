import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';

class ReportTakeawayCard extends StatelessWidget {
  final String takeaway;

  const ReportTakeawayCard({
    super.key,
    required this.takeaway,
  });

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final cardBg = isDark ? const Color(0xFF131417) : p.surface;
    final borderCol = isDark ? const Color(0xFF23252A) : p.border;
    final emerald = isDark ? const Color(0xFF10B981) : p.accent;
    final bodyCol = isDark ? const Color(0xFFD1D5DB) : p.textSecondary;
    final labelCol = isDark ? Colors.white : p.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              color: emerald,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: bodyCol,
                ),
                children: [
                  TextSpan(
                    text: 'Weekly takeaway: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: labelCol,
                    ),
                  ),
                  TextSpan(
                    text: takeaway,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
