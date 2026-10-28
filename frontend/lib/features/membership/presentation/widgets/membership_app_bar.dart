import 'package:flutter/material.dart';
import '../tokens/membership_tokens.dart';

class MembershipAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const MembershipAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      decoration: const BoxDecoration(
        color: MembershipTokens.canvas,
        border: Border(
          bottom: BorderSide(
            color: MembershipTokens.border,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Back',
                child: InkWell(
                  onTap: () {
                    if (onBack != null) {
                      onBack!();
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: MembershipTokens.minTouchTarget,
                    height: MembershipTokens.minTouchTarget,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back,
                      color: MembershipTokens.textPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: MembershipTokens.headline(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null)
                trailing!
              else
                const SizedBox(width: MembershipTokens.minTouchTarget),
            ],
          ),
        ),
      ),
    );
  }
}
