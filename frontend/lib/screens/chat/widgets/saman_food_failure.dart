import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// State 08 presentation: Food Photo Failure.
///
/// Features:
/// - Saman assistant identity header
/// - Calm, non-punitive failure explanation
/// - Helpful photo guidance tips (full plate visible, lighting, top-down angle)
/// - "Retake photo →" primary action
/// - "Enter meal manually →" secondary action
/// - Strictly NO HTTP errors, NO model jargon, NO fake nutrition values
class SamanFoodFailure extends StatelessWidget {
  final VoidCallback onRetake;
  final VoidCallback onManualEntry;

  const SamanFoodFailure({
    super.key,
    required this.onRetake,
    required this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Assistant identity header
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SamanMonogram.chat(),
                const SizedBox(width: 8.0),
                Text(
                  'Saman',
                  style: t.assistantName,
                ),
              ],
            ),
            const SizedBox(height: 8.0),

            // Failure card
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 380.0),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(14.0),
                border: Border.all(
                  color: t.borderSubtle,
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "I couldn't estimate this meal confidently from the photo.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: t.textWhite,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 12.0),

                  // Guidance box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: t.canvas,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(
                        color: t.borderSubtle,
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Try taking another photo with:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: t.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6.0),
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _GuidanceBullet(text: 'the full plate visible'),
                              SizedBox(height: 3.0),
                              _GuidanceBullet(text: 'better lighting'),
                              SizedBox(height: 3.0),
                              _GuidanceBullet(text: 'a clearer top-down angle'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14.0),

                  // Actions: Retake photo & Enter meal manually
                  Wrap(
                    spacing: 16.0,
                    runSpacing: 10.0,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8.0),
                        onTap: onRetake,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_camera_rounded,
                                size: 16,
                                color: t.greenAccent,
                              ),
                              const SizedBox(width: 6.0),
                              Text(
                                'Retake photo',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: t.greenAccent,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: t.greenAccent,
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8.0),
                        onTap: onManualEntry,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 16,
                                color: t.textSecondary,
                              ),
                              const SizedBox(width: 6.0),
                              Text(
                                'Enter meal manually',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: t.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: t.textSecondary,
                              ),
                            ],
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

class _GuidanceBullet extends StatelessWidget {
  final String text;

  const _GuidanceBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: TextStyle(
            fontSize: 12,
            color: t.textMuted,
            height: 1.3,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: t.textMuted,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
