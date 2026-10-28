import 'package:flutter/material.dart';

class ReportTakeawayCard extends StatelessWidget {
  final String takeaway;

  const ReportTakeawayCard({
    super.key,
    required this.takeaway,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131417),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF23252A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF10B981),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFFD1D5DB),
                ),
                children: [
                  const TextSpan(
                    text: 'Weekly takeaway: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
