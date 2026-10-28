import 'package:flutter/material.dart';

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
                        color: const Color(0xFF16171A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF26282F)),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFFE5E7EB),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
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
                          color: Color(0xFFF3F4F6),
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Your progress, in perspective.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFA1A1AA),
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
                    color: const Color(0xFF16171A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF26282F)),
                  ),
                  child: const Icon(
                    Icons.file_upload_outlined,
                    color: Color(0xFFA1A1AA),
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
                  color: const Color(0xFF141517),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF212328)),
                ),
                child: const Icon(
                  Icons.file_upload_outlined,
                  color: Color(0xFF52525B),
                  size: 19,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
