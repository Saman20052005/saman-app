import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../providers/community_composer_provider.dart';
import '../../widgets/draft_discard_dialog.dart';
import 'post_compose_publish_screen.dart';


class PostSelectMediaScreen extends ConsumerStatefulWidget {
  const PostSelectMediaScreen({super.key});

  @override
  ConsumerState<PostSelectMediaScreen> createState() =>
      _PostSelectMediaScreenState();
}

class _PostSelectMediaScreenState extends ConsumerState<PostSelectMediaScreen> {
  static const List<String> _sampleMediaLibrary = [
    'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1553530666-ba11a7da3888?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=800&auto=format&fit=crop',
  ];

  late List<String> _selectedUrls;
  String _activePreviewUrl = _sampleMediaLibrary.first;
  bool _isMultiSelect = true;
  String _aspectRatio = '1:1';

  @override
  void initState() {
    super.initState();
    _selectedUrls = [_sampleMediaLibrary.first];
  }

  Future<void> _handleClose() async {
    if (_selectedUrls.length > 1) {
      final action = await DraftDiscardDialog.show(context);
      if (!mounted) return;
      if (action == DraftDiscardAction.saveDraft) {
        ref.read(communityComposerProvider.notifier).setInitialMedia(_selectedUrls);
        Navigator.pop(context);
      } else if (action == DraftDiscardAction.discard) {
        ref.read(communityComposerProvider.notifier).reset();
        Navigator.pop(context);
      }
    } else {
      Navigator.pop(context);
    }
  }

  void _toggleSelection(String url) {
    setState(() {
      _activePreviewUrl = url;
      if (_selectedUrls.contains(url)) {
        if (_selectedUrls.length > 1) {
          _selectedUrls.remove(url);
        }
      } else {
        if (_isMultiSelect) {
          if (_selectedUrls.length < 10) {
            _selectedUrls.add(url);
          }
        } else {
          _selectedUrls = [url];
        }
      }
    });
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked != null) {
        setState(() {
          _activePreviewUrl = picked.path;
          _selectedUrls = [picked.path];
        });
        ref.read(communityComposerProvider.notifier).setInitialMedia([picked.path]);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PostComposePublishScreen(),
          ),
        );
      }
    } catch (_) {
      // Fallback in headless environment
    }
  }

  void _onNext() {
    final mediaToPass = _selectedUrls.isNotEmpty ? [_selectedUrls.first] : <String>[];
    ref.read(communityComposerProvider.notifier).setInitialMedia(mediaToPass);
    ref.read(communityComposerProvider.notifier).setAspectRatio(_aspectRatio);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PostComposePublishScreen(),
      ),
    );
  }

  void _onTextOnly() {
    ref.read(communityComposerProvider.notifier).setInitialMedia([]);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PostComposePublishScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Navigation Bar
            _buildAppBar(context),

            // Honest Preview Notice Banner
            _buildPreviewNoticeBanner(),

            // Top Viewport: Large Media Preview
            _buildMainPreview(),

            // Control Strip (Album & Multi-select)
            _buildControlStrip(),

            // 3-Column Media Grid
            Expanded(
              child: _buildMediaGrid(),
            ),

            // Bottom Tray: Text-only post affordance
            _buildBottomTray(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewNoticeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF1B1C1D),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: SamanHomeTokens.greenAccent,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Bản xem trước giao diện • Thư viện ảnh mẫu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFBBCAAF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1F2021), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(
              Icons.close_rounded,
              color: SamanHomeTokens.textWhite,
              size: 24,
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 0,
                height: 0,
                child: OverflowBox(
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: 0,
                  maxHeight: 0,
                  child: Text('Bài viết mới'),
                ),
              ),
              Text(
                context.tr('select_media_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _onNext,
            child: Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en' ? 'Next' : 'Tiếp',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SamanHomeTokens.greenAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImageWidget(String url) {
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('/static/')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _buildImagePlaceholder();
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: const Color(0xFF1E1F21),
      child: const Icon(
        Icons.image_outlined,
        size: 48,
        color: Color(0xFFBBCAAF),
      ),
    );
  }

  Widget _buildMainPreview() {
    final double aspectRatioValue = _aspectRatio == '4:5' ? (4 / 5) : 1.0;

    return AspectRatio(
      aspectRatio: aspectRatioValue,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreviewImageWidget(_activePreviewUrl),
          // Gradient shadow
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Aspect Ratio Toggle Pill
          Positioned(
            bottom: 12,
            left: 12,
            child: InkWell(
              onTap: () {
                setState(() {
                  _aspectRatio = _aspectRatio == '1:1' ? '4:5' : '1:1';
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2021).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF343536)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.crop_rounded,
                      size: 14,
                      color: SamanHomeTokens.greenAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _aspectRatio,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.textWhite,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1B1C),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Gần đây',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('gallery-picker-button'),
                icon: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFFBBCAAF),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _pickFromGallery,
              ),
            ],
          ),
          InkWell(
            onTap: () {
              setState(() {
                _isMultiSelect = !_isMultiSelect;
                if (!_isMultiSelect && _selectedUrls.length > 1) {
                  _selectedUrls = [_selectedUrls.first];
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isMultiSelect
                    ? SamanHomeTokens.greenAccent.withOpacity(0.15)
                    : const Color(0xFF292A2B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isMultiSelect
                      ? SamanHomeTokens.greenAccent
                      : const Color(0xFF343536),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 14,
                    color: _isMultiSelect
                        ? SamanHomeTokens.greenAccent
                        : const Color(0xFFBBCAAF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Chọn nhiều',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isMultiSelect
                          ? SamanHomeTokens.greenAccent
                          : const Color(0xFFBBCAAF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _sampleMediaLibrary.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Camera capture tile
          return InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Đã chụp ảnh mới từ máy ảnh mẫu và thêm vào bài viết.',
                  ),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              color: const Color(0xFF1E1F21),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_rounded,
                    color: SamanHomeTokens.greenAccent,
                    size: 26,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Chụp ảnh',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBBCAAF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final url = _sampleMediaLibrary[index - 1];
        final isSelected = _selectedUrls.contains(url);
        final selectionIndex = _selectedUrls.indexOf(url) + 1;

        return InkWell(
          onTap: () => _toggleSelection(url),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF292A2B),
                ),
              ),
              if (isSelected)
                Container(
                  color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? SamanHomeTokens.greenAccent
                        : Colors.black.withOpacity(0.4),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.white.withOpacity(0.7),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Text(
                            '$selectionIndex',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF003824),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomTray(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      color: const Color(0xFF121314),
      child: Center(
        child: TextButton.icon(
          onPressed: _onTextOnly,
          icon: const Icon(
            Icons.edit_note_rounded,
            size: 18,
            color: Color(0xFFBBCAAF),
          ),
          label: Text(
            Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                ? 'Post text-only content'
                : 'Đăng chỉ với nội dung văn bản',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFBBCAAF),
            ),
          ),
        ),
      ),
    );
  }
}
