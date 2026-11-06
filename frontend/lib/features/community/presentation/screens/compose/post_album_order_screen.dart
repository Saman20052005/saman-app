import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../providers/community_composer_provider.dart';
import 'post_compose_publish_screen.dart';

class PostAlbumOrderScreen extends ConsumerWidget {
  const PostAlbumOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);
    final urls = composer.selectedMediaUrls;

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context),

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
                          return _buildAddPhotoSlot(context, notifier);
                        }

                        final url = urls[index];
                        final isCover = index == 0;

                        return _buildPhotoCard(
                          context: context,
                          url: url,
                          index: index,
                          isCover: isCover,
                          totalCount: urls.length,
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
                        color: const Color(0xFF1E1F21),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E3033)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 18,
                            color: SamanHomeTokens.greenAccent,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đổi thứ tự ảnh để bài viết mạch lạc hơn. Ảnh đầu tiên được đặt làm ảnh bìa đại diện trên bảng tin.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFBBCAAF),
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
                        color: const Color(0xFF1E1F21),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E3033)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.collections_rounded,
                                  size: 18,
                                  color: SamanHomeTokens.greenAccent,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${urls.length}/10 ảnh đã chọn',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: SamanHomeTokens.textWhite,
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
                              color: const Color(0xFF292A2B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Tự động lưu',
                              style: TextStyle(
                                fontSize: 11,
                                color: SamanHomeTokens.greenAccent,
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

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 52,
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
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
              size: 22,
            ),
          ),
          const Text(
            'Sắp xếp ảnh',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
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
            child: const Text(
              'Xong',
              style: TextStyle(
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

  Widget _buildPhotoCard({
    required BuildContext context,
    required String url,
    required int index,
    required bool isCover,
    required int totalCount,
    required VoidCallback onRemove,
    required VoidCallback? onMoveUp,
    required VoidCallback? onMoveDown,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCover
              ? SamanHomeTokens.greenAccent.withOpacity(0.5)
              : const Color(0xFF292A2B),
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
                color: const Color(0xFF1E1F21),
              ),
            ),
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
                      color: isCover
                          ? SamanHomeTokens.greenAccent
                          : const Color(0xFF1F2021).withOpacity(0.85),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCover
                              ? const Color(0xFF003824)
                              : SamanHomeTokens.textWhite,
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
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: SamanHomeTokens.greenAccent.withOpacity(0.4),
                        ),
                      ),
                      child: const Text(
                        'Ảnh bìa',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SamanHomeTokens.greenAccent,
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
          color: const Color(0xFF16171A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF272930),
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_rounded,
              color: Color(0xFFBBCAAF),
              size: 28,
            ),
            SizedBox(height: 6),
            Text(
              '+ Thêm ảnh',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFBBCAAF),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Tối đa 10 ảnh',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF71767B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
