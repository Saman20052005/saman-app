import 'package:flutter/material.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';

/// Doorway card in R01 leading into the upcoming Saman Community.
class JournalCommunityDoorwayCard extends StatelessWidget {
  const JournalCommunityDoorwayCard({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  static bool _isNavigating = false;
  static DateTime _lastNavTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Resets the navigation throttle state (used in unit/widget tests).
  @visibleForTesting
  static void resetNavigationState() {
    _lastNavTime = DateTime.fromMillisecondsSinceEpoch(0);
    _isNavigating = false;
  }

  /// Safe navigation to Saman Community Feed (R03) with double-tap protection.
  static Future<void> navigateToCommunity(BuildContext context) async {
    final now = DateTime.now();
    if (_isNavigating || now.difference(_lastNavTime).inMilliseconds < 400) {
      return;
    }
    _isNavigating = true;
    _lastNavTime = now;
    try {
      await Navigator.of(context).pushNamed(AppRoutes.communityFeed);
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('journal_community_doorway_card_inkwell'),
        onTap: onTap ?? () => navigateToCommunity(context),
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SamanHomeTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: SamanHomeTokens.borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: SamanHomeTokens.greenBadgeBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: SamanHomeTokens.greenBadgeBorder,
                            ),
                          ),
                          child: const Icon(
                            Icons.forum_outlined,
                            size: 16,
                            color: SamanHomeTokens.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: Text(
                            'Saman Community',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SamanHomeTokens.textWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Overlapping avatars
                  const _AvatarCluster(),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Chia sẻ hành trình. Cùng nhau tiến bộ.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: SamanHomeTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Text(
                    'Khám phá cộng đồng',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: SamanHomeTokens.greenAccent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 24,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _buildAvatarCircle(const Color(0xFF343842), 'A'),
          ),
          Positioned(
            left: 16,
            child: _buildAvatarCircle(const Color(0xFF283430), 'B'),
          ),
          Positioned(
            left: 32,
            child: _buildAvatarCircle(SamanHomeTokens.greenAccent, 'C', isAccent: true),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCircle(Color bg, String label, {bool isAccent = false}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: SamanHomeTokens.cardSurface,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 13,
          color: isAccent ? const Color(0xFF003824) : SamanHomeTokens.textWhite,
        ),
      ),
    );
  }
}
