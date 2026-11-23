import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';
import '../../data/datasources/community_remote_datasource.dart';
import '../../domain/models/community_story.dart';
import '../providers/community_providers.dart';
import '../providers/community_social_providers.dart';

class CommunityCreateStorySheet extends ConsumerStatefulWidget {
  const CommunityCreateStorySheet({super.key});

  static Future<CommunityStory?> show(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SamanHomeTokens.of(context);

    final story = await showModalBottomSheet<CommunityStory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CommunityCreateStorySheet(),
    );

    if (story != null && messenger != null && context.mounted) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SamanFeedbackSnackBar.build(
          context: context,
          message: 'Đã đăng tin 24h thành công',
          type: FeedbackType.success,
        ),
      );
    } else if (story != null && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor:
              isDark ? SamanFeedbackSnackBar.darkBg : SamanFeedbackSnackBar.lightBg,
          content: const Text('Đã đăng tin 24h thành công'),
        ),
      );
    }

    return story;
  }

  @override
  ConsumerState<CommunityCreateStorySheet> createState() =>
      _CommunityCreateStorySheetState();
}

class _CommunityCreateStorySheetState
    extends ConsumerState<CommunityCreateStorySheet> {
  static const List<String> _bgHexPresets = <String>[
    '#087F66',
    '#1E293B',
    '#7C2D12',
    '#312E81',
  ];

  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _mediaType = 'text'; // 'text' | 'photo' | 'video'
  String _selectedBgHex = _bgHexPresets.first;
  String _privacy = 'public'; // 'public' | 'followers_only'

  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex, Color fallback) {
    final cleaned = hex.replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  String _inferMimeType(String filename, {required bool isVideo}) {
    final ext =
        filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    if (isVideo) {
      switch (ext) {
        case 'mov':
          return 'video/quicktime';
        case 'webm':
          return 'video/webm';
        case 'mkv':
          return 'video/x-matroska';
        case 'mp4':
        default:
          return 'video/mp4';
      }
    }
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = file;
        _pickedBytes = bytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể chọn ảnh từ thư viện';
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = file;
        _pickedBytes = bytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể chọn video từ thư viện';
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final caption = _captionController.text.trim();

    if (_mediaType == 'text' && caption.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập nội dung cho tin văn bản';
      });
      return;
    }
    if ((_mediaType == 'photo' || _mediaType == 'video') &&
        (_pickedFile == null || _pickedBytes == null)) {
      setState(() {
        _errorMessage = _mediaType == 'photo'
            ? 'Vui lòng chọn ảnh để đăng tin'
            : 'Vui lòng chọn video để đăng tin';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      String? uploadedMediaUrl;
      if (_mediaType == 'photo' && _pickedFile != null && _pickedBytes != null) {
        final filename =
            _pickedFile!.name.isNotEmpty ? _pickedFile!.name : 'story.jpg';
        final mimeType = _inferMimeType(filename, isVideo: false);
        final useRemote = ref.read(useRemoteCommunityProvider);
        if (useRemote) {
          final res = await ref.read(communityRemoteDatasourceProvider).uploadMedia(
                bytes: _pickedBytes!,
                filename: filename,
                mimeType: mimeType,
              );
          uploadedMediaUrl = res['media_url'] as String?;
        } else {
          final res = await ref.read(communityRepositoryProvider).uploadDmMedia(
                bytes: _pickedBytes!,
                filename: filename,
                mimeType: mimeType,
              );
          uploadedMediaUrl = res.mediaUrl;
        }
      } else if (_mediaType == 'video' &&
          _pickedFile != null &&
          _pickedBytes != null) {
        final filename =
            _pickedFile!.name.isNotEmpty ? _pickedFile!.name : 'story.mp4';
        final mimeType = _inferMimeType(filename, isVideo: true);
        final res = await ref.read(communityRepositoryProvider).uploadDmMedia(
              bytes: _pickedBytes!,
              filename: filename,
              mimeType: mimeType,
            );
        uploadedMediaUrl = res.mediaUrl;
      }

      if ((_mediaType == 'photo' || _mediaType == 'video') &&
          (uploadedMediaUrl == null || uploadedMediaUrl.trim().isEmpty)) {
        throw StateError('Không nhận được đường dẫn media sau khi tải lên');
      }

      final created =
          await ref.read(communityStoriesProvider.notifier).createStory(
                mediaType: _mediaType,
                mediaUrl: uploadedMediaUrl,
                caption: caption,
                backgroundColor: _mediaType == 'text' ? _selectedBgHex : null,
                privacy: _privacy,
              );

      if (!mounted) return;
      if (created == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Không thể đăng tin. Vui lòng thử lại.';
        });
        return;
      }
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Đăng tin thất bại. Vui lòng kiểm tra kết nối và thử lại.';
      });
    }
  }

  void _selectMode(String mode) {
    if (_mediaType == mode || _isSubmitting) return;
    setState(() {
      _mediaType = mode;
      _pickedFile = null;
      _pickedBytes = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.borderHigh,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tạo tin 24h',
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _isSubmitting ? null : () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                  tooltip: 'Đóng',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ModeSelectorRow(
              selectedMode: _mediaType,
              tokens: tokens,
              onSelect: _selectMode,
            ),
            const SizedBox(height: 16),
            if (_mediaType == 'text') ...[
              _TextStoryPreview(
                backgroundColor:
                    _parseHexColor(_selectedBgHex, tokens.greenAccent),
                caption: _captionController.text,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Màu nền',
                    style: textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _bgHexPresets.map((hex) {
                        final selected = hex == _selectedBgHex;
                        return GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedBgHex = hex),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _parseHexColor(hex, tokens.greenAccent),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? tokens.greenAccent
                                        : tokens.borderHigh,
                                    width: selected ? 2.5 : 1,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (_mediaType == 'photo') ...[
              _MediaPickerBox(
                tokens: tokens,
                icon: Icons.add_photo_alternate_outlined,
                emptyLabel: 'Chọn ảnh từ thư viện',
                pickedFileName: _pickedFile?.name,
                previewBytes: _pickedBytes,
                isVideo: false,
                onTap: _isSubmitting ? null : _pickPhoto,
              ),
              const SizedBox(height: 12),
            ] else ...[
              _MediaPickerBox(
                tokens: tokens,
                icon: Icons.video_library_outlined,
                emptyLabel: 'Chọn video ngắn (tối đa 30 giây)',
                pickedFileName: _pickedFile?.name,
                previewBytes: null,
                isVideo: true,
                fileSizeBytes: _pickedBytes?.length,
                onTap: _isSubmitting ? null : _pickVideo,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _captionController,
              enabled: !_isSubmitting,
              maxLength: 500,
              maxLines: _mediaType == 'text' ? 3 : 2,
              onChanged: (_) {
                if (_mediaType == 'text' || _errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: _mediaType == 'text'
                    ? 'Nhập nội dung tin của bạn...'
                    : 'Thêm chú thích (tùy chọn)...',
                hintStyle: textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: tokens.secondarySurface,
                counterStyle: textTheme.labelSmall?.copyWith(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.greenAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Quyền xem',
                  style: textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PrivacyChip(
                        label: 'Công khai',
                        icon: Icons.public_rounded,
                        selected: _privacy == 'public',
                        tokens: tokens,
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() => _privacy = 'public'),
                      ),
                      _PrivacyChip(
                        label: 'Người theo dõi',
                        icon: Icons.group_outlined,
                        selected: _privacy == 'followers_only',
                        tokens: tokens,
                        onTap: _isSubmitting
                            ? null
                            : () => setState(() => _privacy = 'followers_only'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: tokens.fatRose.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  border: Border.all(
                    color: tokens.fatRose.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.fatRose,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.greenAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  disabledBackgroundColor:
                      tokens.greenAccent.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(SamanHomeTokens.radiusMd),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Đăng tin',
                        style: textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
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

class _ModeSelectorRow extends StatelessWidget {
  const _ModeSelectorRow({
    required this.selectedMode,
    required this.tokens,
    required this.onSelect,
  });

  final String selectedMode;
  final SamanHomePalette tokens;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.secondarySurface,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          _ModeTab(
            label: 'Văn bản',
            icon: Icons.text_fields_rounded,
            selected: selectedMode == 'text',
            tokens: tokens,
            onTap: () => onSelect('text'),
          ),
          _ModeTab(
            label: 'Ảnh',
            icon: Icons.image_outlined,
            selected: selectedMode == 'photo',
            tokens: tokens,
            onTap: () => onSelect('photo'),
          ),
          _ModeTab(
            label: 'Video',
            icon: Icons.videocam_outlined,
            selected: selectedMode == 'video',
            tokens: tokens,
            onTap: () => onSelect('video'),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final SamanHomePalette tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tokens.cardSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
            border: selected ? Border.all(color: tokens.borderHigh) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? tokens.greenAccent : tokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextStoryPreview extends StatelessWidget {
  const _TextStoryPreview({
    required this.backgroundColor,
    required this.caption,
  });

  final Color backgroundColor;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayText =
        caption.trim().isEmpty ? 'Xem trước tin văn bản của bạn' : caption.trim();
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
      ),
      alignment: Alignment.center,
      child: Text(
        displayText,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: textTheme.titleMedium?.copyWith(
          color: caption.trim().isEmpty
              ? Colors.white.withOpacity(0.7)
              : Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MediaPickerBox extends StatelessWidget {
  const _MediaPickerBox({
    required this.tokens,
    required this.icon,
    required this.emptyLabel,
    required this.pickedFileName,
    required this.previewBytes,
    required this.isVideo,
    this.fileSizeBytes,
    required this.onTap,
  });

  final SamanHomePalette tokens;
  final IconData icon;
  final String emptyLabel;
  final String? pickedFileName;
  final Uint8List? previewBytes;
  final bool isVideo;
  final int? fileSizeBytes;
  final VoidCallback? onTap;

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: tokens.secondarySurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
          border: Border.all(color: tokens.borderHigh),
        ),
        clipBehavior: Clip.antiAlias,
        child: previewBytes != null && !isVideo
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(previewBytes!, fit: BoxFit.cover),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius:
                            BorderRadius.circular(SamanHomeTokens.radiusPill),
                      ),
                      child: Text(
                        'Đổi ảnh',
                        style: textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    pickedFileName != null && isVideo
                        ? Icons.video_file_rounded
                        : icon,
                    size: 36,
                    color: pickedFileName != null
                        ? tokens.greenAccent
                        : tokens.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      pickedFileName ?? emptyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: pickedFileName != null
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isVideo && fileSizeBytes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatSize(fileSizeBytes!)} • Chạm để đổi video',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textMuted,
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  const _PrivacyChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final SamanHomePalette tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? tokens.greenBadgeBg : tokens.secondarySurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusPill),
          border: Border.all(
            color: selected ? tokens.greenAccent : tokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? tokens.greenAccent : tokens.textSecondary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tokens.greenAccent : tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
