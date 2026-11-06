import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_post.dart';

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2021),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF343536),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 22,
                  color: SamanHomeTokens.greenAccent,
                ),
              ),
              Expanded(
                child: Text(
                  qaInfo.question,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.textWhite,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (qaInfo.details != null && qaInfo.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              qaInfo.details!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFBBCAAF),
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Responses strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF292A2B).withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildAvatarStack(qaInfo.respondentInitials),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    qaInfo.respondentsSummary,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFBBCAAF),
                    ),
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

  Widget _buildAvatarStack(List<String> initials) {
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
                ? const Color(0xFF39393A)
                : const Color(0xFF10B981).withOpacity(0.2),
            border: Border.all(
              color: const Color(0xFF121314),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: initial.startsWith('+')
                    ? Colors.white
                    : SamanHomeTokens.greenAccent,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
