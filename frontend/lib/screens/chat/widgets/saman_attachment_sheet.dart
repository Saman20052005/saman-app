import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../tokens/saman_chat_tokens.dart';

/// Lightweight action sheet for Saman Chat composer [+] button.
///
/// Provides options:
/// - "Take food photo" (ImageSource.camera)
/// - "Upload image" (ImageSource.gallery)
class SamanAttachmentSheet extends StatelessWidget {
  final ValueChanged<ImageSource> onSelectSource;

  const SamanAttachmentSheet({
    super.key,
    required this.onSelectSource,
  });

  static Future<ImageSource?> show(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: SamanChatTokens.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SamanAttachmentSheet(
        onSelectSource: (source) => Navigator.pop(context, source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SamanChatTokens.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                'Add attachment',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SamanChatTokens.textWhite,
                ),
              ),
            ),
            const SizedBox(height: 12.0),

            // Option 1: Take food photo
            _AttachmentOptionRow(
              icon: Icons.photo_camera_rounded,
              title: 'Take food photo',
              subtitle: 'Estimate calories & macros from camera',
              iconColor: SamanChatTokens.greenAccent,
              onTap: () => onSelectSource(ImageSource.camera),
            ),

            const SizedBox(height: 6.0),

            // Option 2: Upload image
            _AttachmentOptionRow(
              icon: Icons.image_rounded,
              title: 'Upload image',
              subtitle: 'Choose photo from your device library',
              iconColor: SamanChatTokens.textSecondary,
              onTap: () => onSelectSource(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  const _AttachmentOptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SamanChatTokens.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SamanChatTokens.canvas,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SamanChatTokens.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SamanChatTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
