import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';

class ReportHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onExport;

  const ReportHeader({
    super.key,
    required this.onBack,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    final isDark = p.isDark;
    final btnBg = isDark ? const Color(0xFF16171A) : p.surface;
    final btnBorder = isDark ? const Color(0xFF26282F) : p.border;
    final iconCol = isDark ? const Color(0xFFE5E7EB) : p.textPrimary;
    final titleCol = isDark ? const Color(0xFFF3F4F6) : p.textPrimary;
    final mutedCol = isDark ? const Color(0xFFA1A1AA) : p.textSecondary;
    final disabledBg = isDark ? const Color(0xFF141517) : p.surfaceElevated;
    final disabledBorder = isDark ? const Color(0xFF212328) : p.border;
    final disabledIcon = isDark ? const Color(0xFF52525B) : p.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                // Back Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: btnBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: btnBorder),
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: iconCol,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Report',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: titleCol,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your progress, in perspective.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: mutedCol,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Export / Share Button (Disabled with tooltip explanation per design handover)
          if (onExport != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onExport,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: btnBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: btnBorder),
                  ),
                  child: Icon(
                    Icons.file_upload_outlined,
                    color: mutedCol,
                    size: 19,
                  ),
                ),
              ),
            )
          else
            Tooltip(
              message: 'Export is not yet supported in this version',
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: disabledBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: disabledBorder),
                ),
                child: Icon(
                  Icons.file_upload_outlined,
                  color: disabledIcon,
                  size: 19,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
