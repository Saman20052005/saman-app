import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../tokens/saman_chat_tokens.dart';

/// Reusable user photo message component for Saman Chat.
///
/// Right-aligned bubble displaying the user's submitted meal photo,
/// optional question/caption, and timestamp.
class SamanUserPhotoMessage extends StatelessWidget {
  final String imagePath;
  final String? caption;
  final DateTime? timestamp;

  const SamanUserPhotoMessage({
    super.key,
    required this.imagePath,
    this.caption,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(timestamp ?? DateTime.now());
    final isNetwork = imagePath.startsWith('http://') || imagePath.startsWith('https://');
    final fileExists = !isNetwork && File(imagePath).existsSync();

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(left: 48.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 260.0),
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: SamanChatTokens.userBubble,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18.0),
                  topRight: Radius.circular(4.0),
                  bottomLeft: Radius.circular(18.0),
                  bottomRight: Radius.circular(18.0),
                ),
                border: Border.all(
                  color: SamanChatTokens.borderSubtle,
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photo thumbnail container
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: SamanChatTokens.surface,
                        border: Border.all(
                          color: SamanChatTokens.borderSubtle,
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: isNetwork
                            ? Image.network(
                                imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              )
                            : fileExists
                                ? Image.file(
                                    File(imagePath),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                  )
                                : _buildPlaceholder(),
                      ),
                    ),
                  ),

                  // Optional user caption
                  if (caption != null && caption!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8.0),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(
                        caption!.trim(),
                        style: SamanChatTokens.userMessage,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4.0),
            Padding(
              padding: const EdgeInsets.only(right: 2.0),
              child: Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 11,
                  color: SamanChatTokens.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: SamanChatTokens.surfaceElevated,
      child: const Center(
        child: Icon(
          Icons.restaurant_rounded,
          color: SamanChatTokens.textMuted,
          size: 32,
        ),
      ),
    );
  }
}
