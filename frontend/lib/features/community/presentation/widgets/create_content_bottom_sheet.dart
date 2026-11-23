import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/community_providers.dart';
import '../screens/compose/post_compose_publish_screen.dart';
import '../tokens/saman_ig_tokens.dart';
import '../../domain/models/post_attachment_snapshot.dart';
import '../screens/compose/community_ask_question_screen.dart';
import '../screens/compose/community_select_attachment_screen.dart';
import '../screens/compose/post_select_media_screen.dart';

class CreateContentBottomSheet extends ConsumerWidget {
  const CreateContentBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const CreateContentBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ig = SamanIgTokens.of(context);
    final remote = ref.watch(useRemoteCommunityProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ig.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tạo nội dung mới',
                      style: ig.displayTitle(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chọn định dạng nhật ký thể hình của bạn',
                      style: ig.caption(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close_rounded,
                  color: ig.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Options Grid (2x2)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.2,
            children: [
              _buildOptionCard(
                context: context,
                icon: Icons.article_rounded,
                title: 'Bài viết',
                subtitle: 'Ảnh & nhật ký',
                isActive: true,
                ig: ig,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => remote ? const PostComposePublishScreen() : const PostSelectMediaScreen(),
                    ),
                  );
                },
              ),
              _buildOptionCard(
                context: context,
                icon: Icons.fitness_center_rounded,
                title: 'Chia sẻ buổi tập',
                subtitle: 'Kinetic & Tải trọng',
                isActive: false,
                ig: ig,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommunitySelectAttachmentScreen(
                        initialTab: AttachmentType.workout,
                        continueToComposer: true,
                      ),
                    ),
                  );
                },
              ),
              _buildOptionCard(
                context: context,
                icon: Icons.restaurant_rounded,
                title: 'Chia sẻ bữa ăn',
                subtitle: 'Macros & Calo',
                isActive: false,
                ig: ig,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommunitySelectAttachmentScreen(
                        initialTab: AttachmentType.meal,
                        continueToComposer: true,
                      ),
                    ),
                  );
                },
              ),
              _buildOptionCard(
                context: context,
                icon: Icons.help_outline_rounded,
                title: 'Đặt câu hỏi',
                subtitle: 'Hỏi cộng đồng',
                isActive: false,
                ig: ig,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommunityAskQuestionScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required SamanIgTokens ig,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? ig.primaryAction.withOpacity(0.1)
              : ig.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? ig.primaryAction.withOpacity(0.35)
                : ig.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive ? ig.primaryAction : ig.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isActive ? ig.onPrimaryAction : ig.textPrimary,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ig.username(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: ig.caption(
                    fontSize: 11,
                    color: isActive ? ig.primaryAction : ig.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
