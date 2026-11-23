import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../domain/models/post_attachment_snapshot.dart';
import '../../providers/community_composer_provider.dart';
import '../../providers/community_providers.dart';
import '../../widgets/draft_discard_dialog.dart';
import 'community_select_attachment_screen.dart';
import '../../widgets/community_activity_snapshot_card.dart';
import 'post_album_order_screen.dart';

class PostComposePublishScreen extends ConsumerStatefulWidget {
  const PostComposePublishScreen({super.key});

  @override
  ConsumerState<PostComposePublishScreen> createState() =>
      _PostComposePublishScreenState();
}

class _PostComposePublishScreenState
    extends ConsumerState<PostComposePublishScreen> {
  late TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    final currentCaption = ref.read(communityComposerProvider).caption;
    _captionController = TextEditingController(text: currentCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Widget _buildThumbnail(String path, SamanHomePalette tokens) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.image, size: 28, color: tokens.textSecondary),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Center(
      child: Icon(Icons.image, size: 28, color: tokens.textSecondary),
    );
  }

  Future<void> _handleBack() async {
    final composer = ref.read(communityComposerProvider);
    if (composer.hasPendingSubmission) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('community_publish_unconfirmed'))));
      return;
    }
    if (composer.hasContent) {
      final action = await DraftDiscardDialog.show(context);
      if (!mounted) return;
      if (action == DraftDiscardAction.saveDraft) {
        ref.read(communityComposerProvider.notifier).setCaption(_captionController.text);
        final draft = ref.read(communityComposerProvider.notifier).toDraft();
        await ref.read(communityDraftsProvider.notifier).saveDraft(draft);
        if (!mounted) return;
        Navigator.popUntil(context, (route) => route.settings.name == '/community/feed');
      } else if (action == DraftDiscardAction.discard) {
        ref.read(communityComposerProvider.notifier).reset();
        Navigator.popUntil(context, (route) => route.settings.name == '/community/feed');
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _pickMediaFromGallery() async {
    final composer = ref.read(communityComposerProvider);
    if (composer.hasPendingSubmission || composer.attachedActivity != null) {
      return;
    }
    if (composer.selectedMediaUrls.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('compose_max_photos_reached')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
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
      if (!mounted || pickedFiles.isEmpty) return;
      final merged = <String>[...composer.selectedMediaUrls];
      for (final file in pickedFiles) {
        if (!merged.contains(file.path) && merged.length < 10) {
          merged.add(file.path);
        }
      }
      if (merged.length > composer.selectedMediaUrls.length) {
        ref.read(communityComposerProvider.notifier).setInitialMedia(merged);
      }
      if (composer.selectedMediaUrls.length + pickedFiles.length > 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('compose_max_photos_limit')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      // Fallback in headless/unsupported environment
    }
  }

  Future<void> _handlePublish() async {
    final notifier = ref.read(communityComposerProvider.notifier);
    notifier.setCaption(_captionController.text);

    final post = await notifier.publish();
    if (!mounted) return;

    if (post != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('community_publish_success'))));
      Navigator.popUntil(
        context,
        (route) => route.settings.name == '/community/feed' || route.isFirst,
      );
    }
  }

  void _showAudienceSheet() {
    if (ref.read(communityComposerProvider).hasPendingSubmission) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final tokens = SamanHomeTokens.of(sheetCtx);
        return Container(
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(sheetCtx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.secondarySurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('compose_audience_sheet_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildAudienceOption(
                icon: Icons.public_rounded,
                title: context.tr('compose_audience_public'),
                subtitle: context.tr('compose_audience_public_desc'),
                value: 'Công khai',
                tokens: tokens,
              ),
              _buildAudienceOption(
                icon: Icons.group_rounded,
                title: context.tr('compose_audience_followers'),
                subtitle: context.tr('compose_audience_followers_desc'),
                value: 'Người theo dõi',
                tokens: tokens,
                legacyVietnameseText: 'Người theo dõi',
              ),
              _buildAudienceOption(
                icon: Icons.lock_outline_rounded,
                title: context.tr('compose_audience_private'),
                subtitle: context.tr('compose_audience_private_desc'),
                value: 'Chỉ mình tôi',
                tokens: tokens,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudienceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required SamanHomePalette tokens,
    String? legacyVietnameseText,
  }) {
    final currentAudience = ref.watch(communityComposerProvider).audience;
    final isSelected = currentAudience == value;

    return InkWell(
      onTap: () {
        ref.read(communityComposerProvider.notifier).setAudience(value);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? tokens.greenAccent : tokens.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? tokens.greenAccent : tokens.textPrimary,
                        ),
                      ),
                      if (legacyVietnameseText != null && legacyVietnameseText != title)
                        Opacity(
                          opacity: 0.001,
                          child: Text(
                            legacyVietnameseText,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, color: tokens.greenAccent, size: 20),
          ],
        ),
      ),
    );
  }

  String _localizedAudience(BuildContext context, String audience) {
    final isVi = Localizations.maybeLocaleOf(context)?.languageCode == 'vi';
    switch (audience) {
      case 'Công khai':
      case 'public':
        return context.tr('compose_audience_public');
      case 'Người theo dõi':
      case 'followers_only':
        if (isVi && audience == 'Người theo dõi') return audience;
        return context.tr('compose_audience_followers');
      case 'Chỉ mình tôi':
      case 'private':
        return context.tr('compose_audience_private');
      default:
        return audience;
    }
  }

  String _localizedTopic(BuildContext context, String topic) {
    switch (topic) {
      case '#BữaĂn':
        return context.tr('compose_topic_meal');
      case '#TậpLuyện':
        return context.tr('compose_topic_workout');
      case '#PhụcHồi':
        return context.tr('compose_topic_recovery');
      case '#ChiaSẻ':
        return context.tr('compose_topic_share');
      case '#KỷLuật':
        return context.tr('compose_topic_discipline');
      case '#Mẹo':
        return context.tr('compose_topic_tips');
      default:
        return topic;
    }
  }

  void _showTopicSheet() {
    if (ref.read(communityComposerProvider).hasPendingSubmission) return;
    final topics = ['#BữaĂn', '#TậpLuyện', '#PhụcHồi', '#ChiaSẻ', '#KỷLuật', '#Mẹo'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final tokens = SamanHomeTokens.of(sheetCtx);
        return Container(
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(sheetCtx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.secondarySurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('compose_topic_sheet_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topics.map((t) {
                  final isSelected = ref.watch(communityComposerProvider).topic == t;
                  return InkWell(
                    onTap: () {
                      ref.read(communityComposerProvider.notifier).setTopic(t);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? tokens.greenAccent : tokens.secondarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _localizedTopic(context, t),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? (tokens.isDark
                                  ? const Color(0xFF003824)
                                  : const Color(0xFFFFFFFF))
                              : tokens.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommunityComposerState>(communityComposerProvider, (previous, next) {
      if (_captionController.text != next.caption) {
        _captionController.value = TextEditingValue(text: next.caption,
            selection: TextSelection.collapsed(offset: next.caption.length));
      }
    });
    final tokens = SamanHomeTokens.of(context);
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, composer, tokens),
            if (composer.errorMessage != null)
              Padding(key: const ValueKey('publication-status'), padding: const EdgeInsets.all(16),
                child: Text(context.tr(composer.errorMessage!), style: tokens.headerSubtitle)),

            // Main Compose Scroll
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Identity Row
                    _buildUserIdentityRow(composer, tokens),
                    const SizedBox(height: 12),

                    // Caption Input & Thumbnail row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('publication-text-input'),
                            controller: _captionController,
                            maxLength: 5000,
                            readOnly: composer.hasPendingSubmission,
                            maxLines: 5,
                            onChanged: (v) => notifier.setCaption(v),
                            style: TextStyle(
                              fontSize: 14,
                              color: tokens.textPrimary,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              counterStyle: tokens.headerSubtitle,
                              hintText: context.tr('compose_caption_hint'),
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: tokens.textMuted,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (composer.selectedMediaUrls.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PostAlbumOrderScreen(),
                                ),
                              );
                            },
                            child: Container(
                              width: 72,
                              height: 72,
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: _buildThumbnail(composer.selectedMediaUrls.first, tokens),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      key: const ValueKey('remove-selected-media-button'),
                                      onTap: () {
                                        ref.read(communityComposerProvider.notifier).clearMedia();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (composer.selectedMediaUrls.length > 1)
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${composer.selectedMediaUrls.length}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF5BBFA0),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Attached Activity Card (if any)
                    if (composer.attachedActivity != null) ...[
                      _buildAttachedActivityCard(composer.attachedActivity!, notifier, tokens),
                      const SizedBox(height: 16),
                    ],

                    // Settings Group
                    Container(
                      decoration: BoxDecoration(
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Column(
                        children: [
                          _buildSettingTile(
                            icon: Icons.public_rounded,
                            label: context.tr('community_publish_audience'),
                            value: _localizedAudience(context, composer.audience),
                            onTap: _showAudienceSheet,
                            tokens: tokens,
                          ),
                          Divider(color: tokens.border, height: 1),
                          _buildSettingTile(
                            icon: Icons.tag_rounded,
                            label: context.tr('compose_topic_label'),
                            value: _localizedTopic(context, composer.topic),
                            onTap: _showTopicSheet,
                            tokens: tokens,
                          ),
                          Divider(color: tokens.border, height: 1),
                          _buildSettingTile(
                            icon: Icons.fitness_center_rounded,
                            label: context.tr('compose_attach_activity_label'),
                            value: composer.attachedActivity != null
                                ? context.tr('compose_attached_status')
                                : context.tr('compose_not_attached_status'),
                            onTap: () {
                              if (ref.read(communityComposerProvider).hasPendingSubmission) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CommunitySelectAttachmentScreen(),
                                ),
                              );
                            },
                            tokens: tokens,
                          ),
                          Divider(color: tokens.border, height: 1),
                          _buildSettingTile(
                            icon: Icons.photo_library_outlined,
                            label: context.tr('compose_add_photos_label'),
                            value: composer.selectedMediaUrls.isNotEmpty
                                ? '${context.tr('compose_photos_selected_prefix')} (${composer.selectedMediaUrls.length})'
                                : context.tr('compose_gallery_label'),
                            onTap: (composer.hasPendingSubmission ||
                                    composer.attachedActivity != null)
                                ? null
                                : _pickMediaFromGallery,
                            tokens: tokens,
                          ),
                          Divider(color: tokens.border, height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.chat_bubble_outline_rounded, size: 20, color: tokens.textSecondary),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          context.tr('compose_allow_comments'),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: tokens.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: composer.allowComments,
                                  activeColor: tokens.greenAccent,
                                  onChanged: (_) => notifier.toggleAllowComments(),
                                ),
                              ],
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

  Widget _buildAppBar(
    BuildContext context,
    CommunityComposerState composer,
    SamanHomePalette tokens,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _handleBack,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: tokens.textPrimary,
              size: 22,
            ),
          ),
          Expanded(
            child: Stack(
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
                  context.tr('compose_post_title'),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          composer.isSubmitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.greenAccent,
                  ),
                )
              : ElevatedButton(
                  onPressed: composer.hasContent ? _handlePublish : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.greenAccent,
                    foregroundColor: tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Stack(
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
                          child: Text('Chia sẻ'),
                        ),
                      ),
                      Text(
                        context.tr('compose_publish_btn'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildUserIdentityRow(
    CommunityComposerState composer,
    SamanHomePalette tokens,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.secondarySurface,
          ),
          child: Icon(Icons.person_rounded, color: tokens.greenAccent, size: 22),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.watch(useRemoteCommunityProvider) ? context.tr('community_publish_current_user') : 'Linh Nguyễn',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            InkWell(
              onTap: _showAudienceSheet,
              child: Row(
                children: [
                  Text(
                    _localizedAudience(context, composer.audience),
                    style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: tokens.textSecondary),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAttachedActivityCard(
    PostAttachmentSnapshot att,
    CommunityComposerNotifier notifier,
    SamanHomePalette tokens,
  ) {
    if (att.sharedSnapshot != null) { return Column(children: [
      CommunityActivitySnapshotCard(snapshot:att),
      TextButton(onPressed: ref.read(communityComposerProvider).hasPendingSubmission ? null : notifier.clearAttachment,
        child: Text(context.tr('community_attachment_remove'),style: tokens.linkText)),
    ]); }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.greenAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            att.type == AttachmentType.workout
                ? Icons.fitness_center_rounded
                : Icons.restaurant_rounded,
            color: tokens.greenAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  att.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  '${att.category} • ${att.dateFormatted}',
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => notifier.clearAttachment(),
            icon: Icon(Icons.close_rounded, size: 18, color: tokens.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    required SamanHomePalette tokens,
  }) {
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isDisabled ? tokens.textMuted : tokens.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDisabled ? tokens.textMuted : tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDisabled ? tokens.textMuted : tokens.greenAccent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDisabled ? tokens.textMuted : tokens.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
