import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/community_providers.dart';
import '../screens/compose/post_compose_publish_screen.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
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
    final tokens = SamanHomeTokens.of(context);
    final remote = ref.watch(useRemoteCommunityProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
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
                color: tokens.secondarySurface,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chọn định dạng nhật ký thể hình của bạn',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close_rounded,
                  color: tokens.textSecondary,
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
                tokens: tokens,
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
                tokens: tokens,
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
                tokens: tokens,
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
                tokens: tokens,
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
    required SamanHomePalette tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? tokens.greenAccent.withOpacity(0.08)
              : tokens.secondarySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? tokens.greenAccent.withOpacity(0.3)
                : tokens.border,
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
                color: isActive
                    ? tokens.greenAccent
                    : tokens.cardSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isActive
                    ? (tokens.isDark
                        ? const Color(0xFF003824)
                        : const Color(0xFFFFFFFF))
                    : tokens.textPrimary,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive
                        ? tokens.greenAccent
                        : tokens.textSecondary,
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
