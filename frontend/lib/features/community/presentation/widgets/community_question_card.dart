import 'package:flutter/material.dart';
import '../../domain/models/community_post.dart';
import '../tokens/saman_ig_tokens.dart';

class CommunityQuestionCard extends StatelessWidget {
  final PostQaInfo qaInfo;
  final VoidCallback? onJoinDiscussion;

  const CommunityQuestionCard({
    super.key,
    required this.qaInfo,
    this.onJoinDiscussion,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ig.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 22,
                  color: ig.primaryAction,
                ),
              ),
              Expanded(
                child: Text(
                  qaInfo.question,
                  style: ig.displayTitle(fontSize: 17).copyWith(height: 1.3),
                ),
              ),
            ],
          ),
          if (qaInfo.details != null && qaInfo.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              qaInfo.details!,
              style: ig.body(
                fontSize: 14,
                color: ig.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Responses strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: ig.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildAvatarStack(qaInfo.respondentInitials, ig),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    qaInfo.respondentsSummary,
                    style: ig.caption(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarStack(List<String> initials, SamanIgTokens ig) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: initials.take(3).map((initial) {
        return Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: initial.startsWith('+')
                ? ig.surfaceElevated
                : ig.primaryAction.withOpacity(0.18),
            border: Border.all(
              color: ig.canvas,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              initial,
              style: ig.caption(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: initial.startsWith('+')
                    ? ig.textPrimary
                    : ig.primaryAction,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
