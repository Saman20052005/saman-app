import 'package:flutter/material.dart';
import '../tokens/membership_tokens.dart';

class PrimaryMembershipButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtext;

  const PrimaryMembershipButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MembershipTokens.primaryCtaMinHeight,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: MembershipTokens.primaryCtaBg,
              foregroundColor: MembershipTokens.primaryCtaText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  MembershipTokens.buttonRadius,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return MembershipTokens.primaryCtaPressed;
                }
                return null;
              }),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  text,
                  style: MembershipTokens.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: MembershipTokens.primaryCtaText,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    icon,
                    size: 18,
                    color: MembershipTokens.primaryCtaText,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (subtext != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              subtext!,
              style: MembershipTokens.mono(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: MembershipTokens.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}
