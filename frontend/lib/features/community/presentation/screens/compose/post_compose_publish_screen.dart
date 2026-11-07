import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../../config/app_translations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Widget _buildThumbnail(String path) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.image, size: 28, color: Color(0xFFBBCAAF)),
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return const Center(
      child: Icon(Icons.image, size: 28, color: Color(0xFFBBCAAF)),
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
        await ref.read(communityRepositoryProvider).saveDraft(draft);
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
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1F21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF343536),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Who can see this post?'
                    : 'Ai có thể xem bài viết này?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
                ),
              ),
              const SizedBox(height: 12),
              _buildAudienceOption(
                icon: Icons.public_rounded,
                title: context.tr('compose_audience_public'),
                subtitle: Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Anyone in Saman community can see'
                    : 'Mọi người trong cộng đồng Saman đều có thể xem',
                value: 'Công khai',
              ),
              _buildAudienceOption(
                icon: Icons.group_rounded,
                title: context.tr('compose_audience_followers'),
                subtitle: Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Only your followers can see'
                    : 'Chỉ những người đang theo dõi bạn mới có thể xem',
                value: 'Người theo dõi',
                legacyVietnameseText: 'Người theo dõi',
              ),
              _buildAudienceOption(
                icon: Icons.lock_outline_rounded,
                title: context.tr('compose_audience_private'),
                subtitle: Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                    ? 'Save as personal private journal'
                    : 'Lưu dưới dạng nhật ký riêng tư cá nhân',
                value: 'Chỉ mình tôi',
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
            Icon(icon, color: isSelected ? SamanHomeTokens.greenAccent : const Color(0xFFBBCAAF), size: 22),
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
                          color: isSelected ? SamanHomeTokens.greenAccent : SamanHomeTokens.textWhite,
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
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBBCAAF)),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: SamanHomeTokens.greenAccent, size: 20),
          ],
        ),
      ),
    );
  }

  void _showTopicSheet() {
    if (ref.read(communityComposerProvider).hasPendingSubmission) return;
    final topics = ['#BữaĂn', '#TậpLuyện', '#PhụcHồi', '#ChiaSẻ', '#KỷLuật', '#Mẹo'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1F21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF343536),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Chọn chủ đề bài viết',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.textWhite,
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
                        color: isSelected ? SamanHomeTokens.greenAccent : const Color(0xFF292A2B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF003824) : SamanHomeTokens.textWhite,
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
    final composer = ref.watch(communityComposerProvider);
    final notifier = ref.read(communityComposerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121314),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top App Bar
            _buildAppBar(context, composer),
            if (composer.errorMessage != null)
              Padding(key: const ValueKey('publication-status'), padding: const EdgeInsets.all(16),
                child: Text(context.tr(composer.errorMessage!), style: SamanHomeTokens.headerSubtitle)),

            // Main Compose Scroll
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Identity Row
                    _buildUserIdentityRow(composer),
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
                            style: const TextStyle(
                              fontSize: 14,
                              color: SamanHomeTokens.textWhite,
                              height: 1.4,
                            ),
                            decoration: const InputDecoration(
                              filled: false,
                              counterStyle: SamanHomeTokens.headerSubtitle,
                              hintText: 'Viết chú thích cho bài tập hoặc bữa ăn hôm nay...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF71767B),
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
                                border: Border.all(color: const Color(0xFF292A2B)),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: _buildThumbnail(composer.selectedMediaUrls.first),
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
                                            color: SamanHomeTokens.greenAccent,
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
                      _buildAttachedActivityCard(composer.attachedActivity!, notifier),
                      const SizedBox(height: 16),
                    ],

                    // Settings Group
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1F21),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF292A2B)),
                      ),
                      child: Column(
                        children: [
                          _buildSettingTile(
                            icon: Icons.public_rounded,
                            label: context.tr('community_publish_audience'),
                            value: composer.audience,
                            onTap: _showAudienceSheet,
                          ),
                          const Divider(color: Color(0xFF292A2B), height: 1),
                          _buildSettingTile(
                            icon: Icons.tag_rounded,
                            label: 'Chủ đề',
                            value: composer.topic,
                            onTap: _showTopicSheet,
                          ),
                          const Divider(color: Color(0xFF292A2B), height: 1),
                          _buildSettingTile(
                            icon: Icons.fitness_center_rounded,
                            label: 'Đính kèm hoạt động',
                            value: composer.attachedActivity != null
                                ? 'Đã đính kèm'
                                : 'Chưa đính kèm',
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
                          ),
                          const Divider(color: Color(0xFF292A2B), height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.chat_bubble_outline_rounded, size: 20, color: Color(0xFFBBCAAF)),
                                      SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          'Cho phép bình luận',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: SamanHomeTokens.textWhite,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: composer.allowComments,
                                  activeColor: SamanHomeTokens.greenAccent,
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

  Widget _buildAppBar(BuildContext context, CommunityComposerState composer) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121314),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2021), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _handleBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: SamanHomeTokens.textWhite,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
              ],
            ),
          ),
          composer.isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SamanHomeTokens.greenAccent,
                  ),
                )
              : ElevatedButton(
                  onPressed: composer.hasContent ? _handlePublish : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SamanHomeTokens.greenAccent,
                    foregroundColor: const Color(0xFF003824),
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

  Widget _buildUserIdentityRow(CommunityComposerState composer) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF292A2B),
          ),
          child: const Icon(Icons.person_rounded, color: SamanHomeTokens.greenAccent, size: 22),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.watch(useRemoteCommunityProvider) ? context.tr('community_publish_current_user') : 'Linh Nguyễn',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            InkWell(
              onTap: _showAudienceSheet,
              child: Row(
                children: [
                  Text(
                    composer.audience,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFBBCAAF)),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Color(0xFFBBCAAF)),
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
  ) {
    if (att.sharedSnapshot != null) { return Column(children: [
      CommunityActivitySnapshotCard(snapshot:att),
      TextButton(onPressed: ref.read(communityComposerProvider).hasPendingSubmission ? null : notifier.clearAttachment,
        child: Text(context.tr('community_attachment_remove'),style: SamanHomeTokens.linkText)),
    ]); }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SamanHomeTokens.greenAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            att.type == AttachmentType.workout
                ? Icons.fitness_center_rounded
                : Icons.restaurant_rounded,
            color: SamanHomeTokens.greenAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  att.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
                Text(
                  '${att.category} • ${att.dateFormatted}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFBBCAAF)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => notifier.clearAttachment(),
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFBBCAAF)),
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
    required VoidCallback onTap,
  }) {
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
                  Icon(icon, size: 20, color: const Color(0xFFBBCAAF)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: SamanHomeTokens.textWhite,
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
                  style: const TextStyle(fontSize: 12, color: SamanHomeTokens.greenAccent),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFBBCAAF)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
