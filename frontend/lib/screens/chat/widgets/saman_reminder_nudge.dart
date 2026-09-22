import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/saman_nudge.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// Approved presentation for State 04 — Saman Reminder / Proactive Nudge.
///
/// Visual rules:
/// - Conversation-first presentation directly in the chat feed
/// - Header row: [S monogram] + "Saman" + timestamp
/// - Surface-container card with natural guidance copy
/// - Contextual telemetry line (e.g. • 1,780 / 2,400 kcal · 35g protein remaining)
/// - Primary green CTA ("Plan dinner →") and secondary ghost dismiss ("Later")
/// - Strictly NO telemetry badges, NO red alert styling, NO fake unread counts
class SamanReminderNudge extends StatelessWidget {
  final SamanNudge nudge;

  const SamanReminderNudge({
    super.key,
    required this.nudge,
  });

  String _formatTimestamp(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Assistant signature header with timestamp
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SamanMonogram.chat(),
                      SizedBox(width: 8.0),
                      Text(
                        'Saman',
                        style: SamanChatTokens.assistantName,
                      ),
                    ],
                  ),
                  if (nudge.timestamp != null)
                    Text(
                      _formatTimestamp(nudge.timestamp!),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8.0),

            // 2. Nudge Card Bubble
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: SamanChatTokens.surface,
                borderRadius: BorderRadius.circular(14.0),
                border: Border.all(
                  color: SamanChatTokens.borderSubtle,
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Conversational message
                  Text(
                    nudge.message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: SamanChatTokens.textWhite,
                      height: 1.5,
                      letterSpacing: -0.1,
                    ),
                  ),

                  // Supporting telemetry context line
                  if (nudge.supportingLine != null &&
                      nudge.supportingLine!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10.0),
                    Text(
                      nudge.supportingLine!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: SamanChatTokens.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],

                  const SizedBox(height: 14.0),

                  // Action Footer: Primary green button + Secondary Later text
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Primary action button
                      Material(
                        color: SamanChatTokens.greenAccent,
                        borderRadius: BorderRadius.circular(8.0),
                        child: InkWell(
                          onTap: nudge.onPrimary,
                          borderRadius: BorderRadius.circular(8.0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 7.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  nudge.primaryLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF003824),
                                  ),
                                ),
                                const SizedBox(width: 4.0),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: Color(0xFF003824),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Secondary "Later" dismiss action
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: nudge.onSecondary,
                          borderRadius: BorderRadius.circular(6.0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 6.0,
                            ),
                            child: Text(
                              nudge.secondaryLabel,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: SamanChatTokens.textMuted,
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
          ],
        ),
      ),
    );
  }
}
