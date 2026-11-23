import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/community_composer_provider.dart';
import '../../tokens/saman_ig_tokens.dart';
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
    final ig = SamanIgTokens.of(context);
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
      backgroundColor: ig.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            _buildAppBar(context, ig),

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
                                  child: _buildImageView(activeUrl, ig),
                                ),
                              ),
                              if (composer.isGridOverlayVisible)
                                _buildGridOverlay(ig),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Thumbnail Strip (if multiple photos)
                    if (selectedUrls.length > 1) ...[
                      _buildThumbnailStrip(composer, notifier, ig),
                      const SizedBox(height: 12),
                    ],

                    // Ratio & Rotate Controls
                    _buildRatioAndRotateBar(composer, notifier, ig),
                    const SizedBox(height: 12),

                    // Lighting Tools
                    _buildLightingControls(composer, notifier, ig),
                    const SizedBox(height: 12),

                    // Data Honesty Notice: Media Adjustments Preview Only
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: ig.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ig.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: ig.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bộ lọc và xoay ảnh hiển thị trực quan trong trình soạn thảo; tệp gốc không bị can thiệp biến đổi.',
                              style: ig.caption(
                                fontSize: 11,
                                color: ig.textSecondary,
                              ).copyWith(height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Footer utility
                    _buildFooterUtility(composer, notifier, ig),
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
            'Chỉnh ảnh',
            style: ig.displayTitle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
            ),
          ),
          TextButton(
            onPressed: _onNext,
            child: Text(
              'Tiếp',
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

  Widget _buildGridOverlay(SamanIgTokens ig) {
    final gridColor = ig.primaryAction.withOpacity(0.35);
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: gridColor,
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
                          right: BorderSide(color: gridColor),
                          bottom: BorderSide(color: gridColor),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: gridColor),
                          bottom: BorderSide(color: gridColor),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: gridColor),
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
                          right: BorderSide(color: gridColor),
                          bottom: BorderSide(color: gridColor),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: gridColor),
                          bottom: BorderSide(color: gridColor),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: gridColor),
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
                          right: BorderSide(color: gridColor),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: gridColor),
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
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: ig.surface,
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
                              ? ig.primaryAction
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _buildImageView(
                          composer.selectedMediaUrls[idx],
                          ig,
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
            style: ig.caption(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ig.primaryAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioAndRotateBar(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: ig.surface,
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
                  ig: ig,
                ),
                _buildRatioButton(
                  label: 'Vuông',
                  isActive: composer.aspectRatio == '1:1',
                  onTap: () => notifier.setAspectRatio('1:1'),
                  ig: ig,
                ),
                _buildRatioButton(
                  label: 'Dọc (4:5)',
                  isActive: composer.aspectRatio == '4:5',
                  onTap: () => notifier.setAspectRatio('4:5'),
                  ig: ig,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => notifier.rotate(),
            icon: Icon(
              Icons.rotate_90_degrees_cw_rounded,
              color: ig.textSecondary,
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
    required SamanIgTokens ig,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? ig.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? ig.primaryAction.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ig.caption(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? ig.primaryAction : ig.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLightingControls(
    CommunityComposerState composer,
    CommunityComposerNotifier notifier,
    SamanIgTokens ig,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Tinh chỉnh ánh sáng',
                  overflow: TextOverflow.ellipsis,
                  style: ig.username(
                    fontSize: 13,
                    color: ig.textPrimary,
                  ),
                ),
              ),
              Text(
                'Tự nhiên',
                style: ig.caption(
                  fontSize: 11,
                  color: ig.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Brightness slider
          Row(
            children: [
              Icon(
                Icons.light_mode_rounded,
                size: 16,
                color: ig.textSecondary,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 65,
                child: Text(
                  'Độ sáng',
                  style: ig.caption(fontSize: 12, color: ig.textSecondary),
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
                    activeColor: ig.primaryAction,
                    inactiveColor: ig.surfaceElevated,
                    onChanged: (v) => notifier.setBrightness(v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${composer.brightness.round()}',
                  textAlign: TextAlign.end,
                  style: ig.caption(
                    fontSize: 11,
                    color: ig.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          // Contrast slider
          Row(
            children: [
              Icon(
                Icons.contrast_rounded,
                size: 16,
                color: ig.textSecondary,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 65,
                child: Text(
                  'Tương phản',
                  style: ig.caption(fontSize: 12, color: ig.textSecondary),
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
                    activeColor: ig.primaryAction,
                    inactiveColor: ig.surfaceElevated,
                    onChanged: (v) => notifier.setContrast(v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${composer.contrast.round()}',
                  textAlign: TextAlign.end,
                  style: ig.caption(
                    fontSize: 11,
                    color: ig.textSecondary,
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
    SamanIgTokens ig,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: () => notifier.resetAdjustments(),
          icon: Icon(
            Icons.restart_alt_rounded,
            size: 16,
            color: ig.textSecondary,
          ),
          label: Text(
            'Đặt lại',
            style: ig.caption(fontSize: 12, color: ig.textSecondary),
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
                ? ig.primaryAction
                : ig.textSecondary,
          ),
          label: Text(
            'Lưới căn chỉnh',
            style: ig.caption(
              fontSize: 12,
              color: composer.isGridOverlayVisible
                  ? ig.primaryAction
                  : ig.textSecondary,
            ),
          ),
        ),
      ],
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
