import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/community_composer_provider.dart';
import '../../tokens/saman_ig_tokens.dart';
import 'post_compose_publish_screen.dart';

class PostAlbumOrderScreen extends ConsumerWidget {
  const PostAlbumOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);
    final urls = composer.selectedMediaUrls;

    return Scaffold(
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, ig),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grid of Photos (2 columns)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: urls.length + (urls.length < 10 ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == urls.length) {
                          // Add photo slot
                          return _buildAddPhotoSlot(
                            context,
                            urls,
                            notifier,
                            ig,
                          );
                        }

                        final url = urls[index];
                        final isCover = index == 0;

                        return _buildPhotoCard(
                          context: context,
                          url: url,
                          index: index,
                          isCover: isCover,
                          totalCount: urls.length,
                          ig: ig,
                          onRemove: () => notifier.removeMedia(index),
                          onMoveUp: index > 0
                              ? () => notifier.reorderMedia(index, index - 1)
                              : null,
                          onMoveDown: index < urls.length - 1
                              ? () => notifier.reorderMedia(index, index + 2)
                              : null,
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Instruction Tip
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ig.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ig.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 18,
                            color: ig.primaryAction,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đổi thứ tự ảnh để bài viết mạch lạc hơn. Ảnh đầu tiên được đặt làm ảnh bìa đại diện trên bảng tin.',
                              style: ig.caption(
                                fontSize: 12,
                                color: ig.textSecondary,
                              ).copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Metadata preview card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: ig.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ig.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.collections_rounded,
                                  size: 18,
                                  color: ig.primaryAction,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${urls.length}/10 ảnh đã chọn',
                                    overflow: TextOverflow.ellipsis,
                                    style: ig.username(
                                      fontSize: 13,
                                      color: ig.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: ig.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Tự động lưu',
                              style: ig.caption(
                                fontSize: 11,
                                color: ig.primaryAction,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, SamanIgTokens ig) {
    return Container(
      height: 52,
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
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ig.textPrimary,
              size: 22,
            ),
          ),
          Text(
            'Sắp xếp ảnh',
            style: ig.displayTitle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PostComposePublishScreen(),
                ),
              );
            },
            child: Text(
              'Xong',
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

  Widget _buildPhotoCard({
    required BuildContext context,
    required String url,
    required int index,
    required bool isCover,
    required int totalCount,
    required SamanIgTokens ig,
    required VoidCallback onRemove,
    required VoidCallback? onMoveUp,
    required VoidCallback? onMoveDown,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCover ? ig.primaryAction : ig.border,
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImageView(url, ig),
            // Top Controls: Order badge & Remove
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCover ? ig.primaryAction : ig.scrim,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ig.onPrimaryAction,
                        ),
                      ),
                    ),
                  ),
                  if (totalCount > 1)
                    InkWell(
                      onTap: onRemove,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ig.scrim,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: ig.onPrimaryAction,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Bottom Controls: Cover tag & Reorder controls
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isCover)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ig.scrim,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: ig.primaryAction.withOpacity(0.6),
                        ),
                      ),
                      child: Text(
                        'Ảnh bìa',
                        style: TextStyle(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: ig.primaryAction,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onMoveUp != null)
                        InkWell(
                          onTap: onMoveUp,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ig.scrim,
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              size: 14,
                              color: ig.onPrimaryAction,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      if (onMoveDown != null)
                        InkWell(
                          onTap: onMoveDown,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ig.scrim,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: ig.onPrimaryAction,
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

  Widget _buildImageView(String path, SamanIgTokens ig) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: ig.surface,
          child: Icon(
            Icons.broken_image_outlined,
            color: ig.textSecondary,
          ),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Container(
      color: ig.surface,
      child: Icon(
        Icons.image_outlined,
        color: ig.textSecondary,
      ),
    );
  }

  Future<void> _pickMorePhotos(
    BuildContext context,
    List<String> currentUrls,
    CommunityComposerNotifier notifier,
  ) async {
    if (currentUrls.length >= 10) return;
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
      if (pickedFiles.isEmpty) return;

      final merged = <String>[...currentUrls];
      for (final file in pickedFiles) {
        if (!merged.contains(file.path) && merged.length < 10) {
          merged.add(file.path);
        }
      }
      if (merged.length > currentUrls.length) {
        notifier.setInitialMedia(merged);
      }
      if (currentUrls.length + pickedFiles.length > 10 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                  ? 'Maximum 10 photos allowed'
                  : 'Chỉ thêm được tối đa 10 ảnh',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      // Fallback in headless environment
    }
  }

  Widget _buildAddPhotoSlot(
    BuildContext context,
    List<String> currentUrls,
    CommunityComposerNotifier notifier,
    SamanIgTokens ig,
  ) {
    return InkWell(
      onTap: () => _pickMorePhotos(context, currentUrls, notifier),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: ig.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ig.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_rounded,
              color: ig.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              '+ Thêm ảnh',
              style: ig.caption(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ig.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tối đa 10 ảnh',
              style: ig.caption(
                fontSize: 10,
                color: ig.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
