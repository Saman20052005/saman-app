import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Sporty Quick-Action Dock for Saman Home.
///
/// Final visual truth: `design/saman-home/home-screen.png`
/// Exactly 2 compact action cards in a balanced 2-column grid:
/// 1. `+ Log meal` (opens meal logging flow)
/// 2. `💧 Add water` (instantly logs +250ml water)
class QuickActionDock extends StatelessWidget {
  const QuickActionDock({
    super.key,
    this.onLogMealTap,
    this.onAddWaterTap,
  });

  final VoidCallback? onLogMealTap;
  final VoidCallback? onAddWaterTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionButton(
              icon: Icons.add_rounded,
              label: 'Log meal',
              tooltip: 'Log meal',
              onTap: onLogMealTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionButton(
              icon: Icons.water_drop_outlined,
              label: 'Add water',
              tooltip: 'Add 250ml water',
              onTap: onAddWaterTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: SamanHomeTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
            border: Border.all(
              color: SamanHomeTokens.border,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: SamanHomeTokens.iconContainerBg,
                  borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                    width: 0.8,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 16,
                  color: SamanHomeTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: SamanHomeTokens.textWhite,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
