import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../providers/community_composer_provider.dart';
import 'post_album_order_screen.dart';
import 'post_compose_publish_screen.dart';

class PostEditMediaScreen extends ConsumerStatefulWidget {
  const PostEditMediaScreen({super.key});

  @override
  ConsumerState<PostEditMediaScreen> createState() =>
      _PostEditMediaScreenState();
}

class _PostEditMediaScreenState extends ConsumerState<PostEditMediaScreen> {
  void _onNext() {
    final composer = ref.read(communityComposerProvider);
    if (composer.selectedMediaUrls.length > 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PostAlbumOrderScreen(),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PostComposePublishScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);

    final selectedUrls = composer.selectedMediaUrls;
    final activeUrl = selectedUrls.isNotEmpty
        ? selectedUrls[composer.activeMediaIndex.clamp(0, selectedUrls.length - 1)]
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&auto=format&fit=crop';

    final double aspect = composer.aspectRatio == '4:5'
        ? (4 / 5)
        : (composer.aspectRatio == 'orig' ? 1.2 : 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildAppBar(context),

            // Main Preview Frame
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    // Photo Preview
                    Center(
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.rotate(
                                angle: composer.rotation * (3.1415926535 / 180),
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.matrix(
                                    _buildColorMatrix(
                                      composer.brightness,
                                      composer.contrast,
                                    ),
                                  ),
                                  child: Image.network(
                                    activeUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF1E1F21),
                                    ),
                                  ),
                                ),
                              ),
                              if (composer.isGridOverlayVisible)
                                _buildGridOverlay(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Thumbnail Strip (if multiple photos)
                    if (selectedUrls.length > 1) ...[
                      _buildThumbnailStrip(composer, notifier),
                      const SizedBox(height: 12),
                    ],

                    // Ratio & Rotate Controls
                    _buildRatioAndRotateBar(composer, notifier),
                    const SizedBox(height: 12),

                    // Lighting Tools
                    _buildLightingControls(composer, notifier),
                    const SizedBox(height: 12),

                    // Data Honesty Notice: Media Adjustments Preview Only
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1F21),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2E3033)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: Color(0xFFBBCAAF),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bộ lọc và xoay ảnh hiển thị trực quan trong trình soạn thảo; tệp gốc không bị can thiệp biến đổi.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFBBCAAF),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Footer utility
                    _buildFooterUtility(composer, notifier),
                    const SizedBox(height: 24),
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
            'Chỉnh ảnh',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
            ),
          ),
          TextButton(
            onPressed: _onNext,
            child: const Text(
              'Tiếp',
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

  Widget _buildGridOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: SamanHomeTokens.greenAccent.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: SamanHomeTokens.greenAccent.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: Container()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(composer.selectedMediaUrls.length, (idx) {
                  final isCurrent = idx == composer.activeMediaIndex;
                  return InkWell(
                    onTap: () => notifier.setActiveMediaIndex(idx),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrent
                              ? SamanHomeTokens.greenAccent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          composer.selectedMediaUrls[idx],
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          Text(
            '${composer.activeMediaIndex + 1}/${composer.selectedMediaUrls.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SamanHomeTokens.greenAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioAndRotateBar(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildRatioButton(
                  label: 'Gốc',
                  isActive: composer.aspectRatio == 'orig',
                  onTap: () => notifier.setAspectRatio('orig'),
                ),
                _buildRatioButton(
                  label: 'Vuông',
                  isActive: composer.aspectRatio == '1:1',
                  onTap: () => notifier.setAspectRatio('1:1'),
                ),
                _buildRatioButton(
                  label: 'Dọc (4:5)',
                  isActive: composer.aspectRatio == '4:5',
                  onTap: () => notifier.setAspectRatio('4:5'),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => notifier.rotate(),
            icon: const Icon(
              Icons.rotate_90_degrees_cw_rounded,
              color: Color(0xFFBBCAAF),
              size: 20,
            ),
            tooltip: 'Xoay 90°',
          ),
        ],
      ),
    );
  }

  Widget _buildRatioButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF292A2B) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? SamanHomeTokens.greenAccent.withOpacity(0.4)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? SamanHomeTokens.greenAccent
                  : const Color(0xFFBBCAAF),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLightingControls(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Tinh chỉnh ánh sáng',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
              ),
              Text(
                'Tự nhiên',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFBBCAAF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Brightness slider
          Row(
            children: [
              const Icon(
                Icons.light_mode_rounded,
                size: 16,
                color: Color(0xFFBBCAAF),
              ),
              const SizedBox(width: 6),
              const SizedBox(
                width: 65,
                child: Text(
                  'Độ sáng',
                  style: TextStyle(fontSize: 12, color: Color(0xFFBBCAAF)),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: composer.brightness,
                    min: -50,
                    max: 50,
                    activeColor: SamanHomeTokens.greenAccent,
                    inactiveColor: const Color(0xFF343536),
                    onChanged: (v) => notifier.setBrightness(v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${composer.brightness.round()}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBBCAAF),
                  ),
                ),
              ),
            ],
          ),
          // Contrast slider
          Row(
            children: [
              const Icon(
                Icons.contrast_rounded,
                size: 16,
                color: Color(0xFFBBCAAF),
              ),
              const SizedBox(width: 6),
              const SizedBox(
                width: 65,
                child: Text(
                  'Tương phản',
                  style: TextStyle(fontSize: 12, color: Color(0xFFBBCAAF)),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: composer.contrast,
                    min: -50,
                    max: 50,
                    activeColor: SamanHomeTokens.greenAccent,
                    inactiveColor: const Color(0xFF343536),
                    onChanged: (v) => notifier.setContrast(v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${composer.contrast.round()}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBBCAAF),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterUtility(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: () => notifier.resetAdjustments(),
          icon: const Icon(
            Icons.restart_alt_rounded,
            size: 16,
            color: Color(0xFFBBCAAF),
          ),
          label: const Text(
            'Đặt lại',
            style: TextStyle(fontSize: 12, color: Color(0xFFBBCAAF)),
          ),
        ),
        TextButton.icon(
          onPressed: () => notifier.toggleGrid(),
          icon: Icon(
            composer.isGridOverlayVisible
                ? Icons.grid_on_rounded
                : Icons.grid_off_rounded,
            size: 16,
            color: composer.isGridOverlayVisible
                ? SamanHomeTokens.greenAccent
                : const Color(0xFFBBCAAF),
          ),
          label: Text(
            'Lưới căn chỉnh',
            style: TextStyle(
              fontSize: 12,
              color: composer.isGridOverlayVisible
                  ? SamanHomeTokens.greenAccent
                  : const Color(0xFFBBCAAF),
            ),
          ),
        ),
      ],
    );
  }

  List<double> _buildColorMatrix(double brightness, double contrast) {
    final b = brightness / 100.0;
    final c = 1.0 + (contrast / 100.0);

    return <double>[
      c, 0, 0, 0, b * 255,
      0, c, 0, 0, b * 255,
      0, 0, c, 0, b * 255,
      0, 0, 0, 1, 0,
    ];
  }
}
