import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/community_composer_provider.dart';
import '../../tokens/saman_ig_tokens.dart';
import '../../widgets/draft_discard_dialog.dart';
import 'post_album_order_screen.dart';
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
  bool _isMultiSelect = false;
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
    if (_selectedUrls.contains(url)) {
      if (_selectedUrls.length > 1) {
        setState(() {
          _selectedUrls.remove(url);
          if (_activePreviewUrl == url && _selectedUrls.isNotEmpty) {
            _activePreviewUrl = _selectedUrls.first;
          }
        });
      }
      return;
    }

    if (_isMultiSelect) {
      if (_selectedUrls.length >= 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                  ? 'Maximum 10 photos allowed'
                  : 'Tối đa 10 ảnh',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      setState(() {
        _selectedUrls.add(url);
        _activePreviewUrl = url;
      });
      return;
    }

    setState(() {
      _activePreviewUrl = url;
      _selectedUrls = [url];
    });
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      List<XFile> pickedFiles = const [];
      try {
        pickedFiles = await picker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 90,
        );
      } catch (_) {
        final single = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 90,
        );
        if (single != null) {
          pickedFiles = [single];
        }
      }
      if (pickedFiles.isNotEmpty) {
        if (pickedFiles.length > 10 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Maximum 10 photos selected'
                    : 'Chỉ chọn tối đa 10 ảnh',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        final paths = pickedFiles.take(10).map((e) => e.path).toList();
        setState(() {
          _activePreviewUrl = paths.first;
          _selectedUrls = paths;
          if (paths.length > 1) {
            _isMultiSelect = true;
          }
        });
        final notifier = ref.read(communityComposerProvider.notifier);
        notifier.setInitialMedia(paths);
        notifier.setAspectRatio(_aspectRatio);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => paths.length > 1
                ? const PostAlbumOrderScreen()
                : const PostComposePublishScreen(),
          ),
        );
      }
    } catch (_) {
      // Fallback in headless environment
    }
  }

  void _onNext() {
    final mediaToPass = _selectedUrls.take(10).toList();
    final notifier = ref.read(communityComposerProvider.notifier);
    notifier.setInitialMedia(mediaToPass);
    notifier.setAspectRatio(_aspectRatio);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => mediaToPass.length > 1
            ? const PostAlbumOrderScreen()
            : const PostComposePublishScreen(),
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
    final ig = SamanIgTokens.of(context);
    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Navigation Bar
            _buildAppBar(context, ig),

            // Honest Preview Notice Banner
            _buildPreviewNoticeBanner(ig),

            // Top Viewport: Large Media Preview
            _buildMainPreview(ig),

            // Control Strip (Album & Multi-select)
            _buildControlStrip(ig),

            // 3-Column Media Grid
            Expanded(
              child: _buildMediaGrid(ig),
            ),

            // Bottom Tray: Text-only post affordance
            _buildBottomTray(context, ig),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewNoticeBanner(SamanIgTokens ig) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: ig.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: ig.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Bản xem trước giao diện • Thư viện ảnh mẫu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ig.caption(
                fontSize: 11,
                color: ig.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanIgTokens ig) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ig.canvas,
        border: Border(
          bottom: BorderSide(color: ig.border, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _handleClose,
            icon: Icon(
              Icons.close_rounded,
              color: ig.textPrimary,
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
                style: ig.displayTitle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ig.textPrimary,
                ).copyWith(letterSpacing: -0.2),
              ),
            ],
          ),
          TextButton(
            onPressed: _onNext,
            child: Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en' ? 'Next' : 'Tiếp',
              style: ig.buttonLabel(
                fontSize: 15,
                color: ig.primaryAction,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImageWidget(String url, SamanIgTokens ig) {
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('/static/')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(ig),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _buildImagePlaceholder(ig);
  }

  Widget _buildImagePlaceholder(SamanIgTokens ig) {
    return Container(
      color: ig.surface,
      child: Icon(
        Icons.image_outlined,
        size: 48,
        color: ig.textSecondary,
      ),
    );
  }

  Widget _buildMainPreview(SamanIgTokens ig) {
    final double aspectRatioValue = _aspectRatio == '4:5' ? (4 / 5) : 1.0;

    return AspectRatio(
      aspectRatio: aspectRatioValue,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreviewImageWidget(_activePreviewUrl, ig),
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
          // Aspect Ratio Toggle Pill (dark translucent overlay kept for image contrast)
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
                  color: ig.scrim,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ig.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.crop_rounded,
                      size: 14,
                      color: ig.onPrimaryAction,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _aspectRatio,
                      style: TextStyle(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ig.onPrimaryAction,
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

  Widget _buildControlStrip(SamanIgTokens ig) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ig.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Gần đây',
                style: ig.displayTitle(
                  fontSize: 15,
                  color: ig.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('gallery-picker-button'),
                icon: Icon(
                  Icons.photo_library_outlined,
                  color: ig.textSecondary,
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
                  _selectedUrls = [_activePreviewUrl];
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isMultiSelect
                    ? ig.primaryAction.withOpacity(0.15)
                    : ig.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isMultiSelect ? ig.primaryAction : ig.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 14,
                    color: _isMultiSelect
                        ? ig.primaryAction
                        : ig.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Chọn nhiều',
                    style: ig.caption(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isMultiSelect
                          ? ig.primaryAction
                          : ig.textSecondary,
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

  Widget _buildMediaGrid(SamanIgTokens ig) {
    final gridItems = [
      ..._selectedUrls.where((u) => !_sampleMediaLibrary.contains(u)),
      ..._sampleMediaLibrary,
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: gridItems.length + 1,
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
              color: ig.surface,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_camera_rounded,
                    color: ig.primaryAction,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chụp ảnh',
                    style: ig.caption(
                      fontSize: 11,
                      color: ig.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final url = gridItems[index - 1];
        final isSelected = _selectedUrls.contains(url);
        final selectionIndex = _selectedUrls.indexOf(url) + 1;

        return InkWell(
          onTap: () => _toggleSelection(url),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPreviewImageWidget(url, ig),
              if (isSelected)
                Container(
                  color: ig.primaryAction.withOpacity(0.25),
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
                        ? ig.primaryAction
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
                            style: TextStyle(
                              fontFamily: SamanIgTokens.fontFamily,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ig.onPrimaryAction,
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

  Widget _buildBottomTray(BuildContext context, SamanIgTokens ig) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      color: ig.canvas,
      child: Center(
        child: TextButton.icon(
          onPressed: _onTextOnly,
          icon: Icon(
            Icons.edit_note_rounded,
            size: 18,
            color: ig.textSecondary,
          ),
          label: Text(
            Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                ? 'Post text-only content'
                : 'Đăng chỉ với nội dung văn bản',
            style: ig.caption(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ig.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
