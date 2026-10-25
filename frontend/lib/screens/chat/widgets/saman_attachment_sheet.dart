import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../tokens/saman_chat_tokens.dart';

class SamanAttachmentResult {
  final ImageSource source;
  final String mode;

  const SamanAttachmentResult({
    required this.source,
    this.mode = 'standard',
  });
}

/// Lightweight action sheet for Saman Chat composer [+] button with mode selection.
///
/// Provides options:
/// - "Take food photo" (ImageSource.camera)
/// - "Upload image" (ImageSource.gallery)
class SamanAttachmentSheet extends StatefulWidget {
  final ValueChanged<ImageSource>? onSelectSource;
  final ValueChanged<SamanAttachmentResult>? onSelect;
  final String initialMode;

  const SamanAttachmentSheet({
    super.key,
    this.onSelectSource,
    this.onSelect,
    this.initialMode = 'standard',
  });

  static Future<SamanAttachmentResult?> show(
    BuildContext context, {
    String initialMode = 'standard',
  }) {
    return showModalBottomSheet<SamanAttachmentResult>(
      context: context,
      backgroundColor: SamanChatTokens.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SamanAttachmentSheet(
        initialMode: initialMode,
        onSelect: (result) => Navigator.pop(context, result),
      ),
    );
  }

  @override
  State<SamanAttachmentSheet> createState() => _SamanAttachmentSheetState();
}

class _SamanAttachmentSheetState extends State<SamanAttachmentSheet> {
  late String _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
  }

  void _handleSelect(ImageSource source) {
    final result = SamanAttachmentResult(source: source, mode: _selectedMode);
    if (widget.onSelect != null) {
      widget.onSelect!(result);
    } else if (widget.onSelectSource != null) {
      widget.onSelectSource!(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdvanced = _selectedMode == 'advanced';

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

            // Mode Selector Pill
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: SamanChatTokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SamanChatTokens.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMode = 'standard'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !isAdvanced ? SamanChatTokens.canvas : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: !isAdvanced
                              ? Border.all(color: SamanChatTokens.greenAccent.withOpacity(0.5))
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Tiêu chuẩn',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: !isAdvanced ? FontWeight.w600 : FontWeight.w500,
                            color: !isAdvanced ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMode = 'advanced'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isAdvanced ? SamanChatTokens.canvas : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isAdvanced
                              ? Border.all(color: const Color(0xFFFF8A3D).withOpacity(0.6))
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '✨ AI nâng cao',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF8A3D),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x33FF8A3D),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Thử nghiệm',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFFF8A3D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Text(
                isAdvanced
                    ? 'Hỗ trợ món ăn phức hợp & món Việt Nam (Gemini)'
                    : 'Phù hợp đĩa đơn lẻ (Food-101 + Dữ liệu tham chiếu)',
                style: const TextStyle(
                  fontSize: 11,
                  color: SamanChatTokens.textMuted,
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
              onTap: () => _handleSelect(ImageSource.camera),
            ),

            const SizedBox(height: 6.0),

            // Option 2: Upload image
            _AttachmentOptionRow(
              icon: Icons.image_rounded,
              title: 'Upload image',
              subtitle: 'Choose photo from your device library',
              iconColor: SamanChatTokens.textSecondary,
              onTap: () => _handleSelect(ImageSource.gallery),
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
