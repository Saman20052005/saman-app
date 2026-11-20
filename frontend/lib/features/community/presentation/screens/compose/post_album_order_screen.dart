import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../providers/community_composer_provider.dart';
import 'post_compose_publish_screen.dart';

class PostAlbumOrderScreen extends ConsumerWidget {
  const PostAlbumOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);
    final urls = composer.selectedMediaUrls;

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, tokens),

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
                          return _buildAddPhotoSlot(context, notifier, tokens);
                        }

                        final url = urls[index];
                        final isCover = index == 0;

                        return _buildPhotoCard(
                          context: context,
                          url: url,
                          index: index,
                          isCover: isCover,
                          totalCount: urls.length,
                          tokens: tokens,
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
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 18,
                            color: tokens.greenAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đổi thứ tự ảnh để bài viết mạch lạc hơn. Ảnh đầu tiên được đặt làm ảnh bìa đại diện trên bảng tin.',
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textSecondary,
                                height: 1.4,
                              ),
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
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.border),
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
                                  color: tokens.greenAccent,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${urls.length}/10 ảnh đã chọn',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.textPrimary,
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
                              color: tokens.secondarySurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Tự động lưu',
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.greenAccent,
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

  Widget _buildAppBar(BuildContext context, SamanHomePalette tokens) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Text(
            'Sắp xếp ảnh',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: tokens.greenAccent,
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
    required SamanHomePalette tokens,
    required VoidCallback onRemove,
    required VoidCallback? onMoveUp,
    required VoidCallback? onMoveDown,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCover
              ? tokens.greenAccent.withOpacity(0.5)
              : tokens.border,
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: tokens.cardSurface,
              ),
            ),
            // Top Controls: Order badge & Remove (dark translucent overlay kept for image contrast)
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
                      color: isCover
                          ? tokens.greenAccent
                          : const Color(0xFF1F2021).withOpacity(0.85),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCover
                              ? (tokens.isDark
                                  ? const Color(0xFF003824)
                                  : const Color(0xFFFFFFFF))
                              : Colors.white,
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
                          color: Colors.black.withOpacity(0.6),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Bottom Controls: Cover tag & Reorder controls (dark translucent overlay kept for image contrast)
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
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF5BBFA0).withOpacity(0.4),
                        ),
                      ),
                      child: const Text(
                        'Ảnh bìa',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5BBFA0),
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
                              color: Colors.black.withOpacity(0.6),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              size: 14,
                              color: Colors.white,
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
                              color: Colors.black.withOpacity(0.6),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
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

  Widget _buildAddPhotoSlot(
    BuildContext context,
    CommunityComposerNotifier notifier,
    SamanHomePalette tokens,
  ) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chọn thêm ảnh từ thư viện mẫu.'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_rounded,
              color: tokens.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              '+ Thêm ảnh',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tối đa 10 ảnh',
              style: TextStyle(
                fontSize: 10,
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
