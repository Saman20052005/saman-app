import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_theme.dart';
import '../../../controllers/chat_controller.dart';
import '../../../features/membership/domain/models/membership_plan.dart';
import '../../../features/membership/presentation/providers/membership_providers.dart';
import '../../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../../../features/membership/presentation/widgets/upgrade_bottom_sheet.dart';

const bool _kEnableAiPaywall =
    bool.fromEnvironment('ENABLE_AI_PAYWALL', defaultValue: false);

class AIModeSelector extends ConsumerWidget {
  const AIModeSelector({super.key});

  Future<void> _openPro3Paywall(BuildContext context) async {
    final selectedTier =
        await showUpgradeBottomSheet(context, tier: MembershipTier.pro);
    if (context.mounted && selectedTier != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/membership/detail/${selectedTier.name}',
          ),
          builder: (_) => PlanDetailScreen(tier: selectedTier),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = ref.watch(
      chatControllerProvider.select((state) => state.selectedAIMode),
    );
    final entitlements = ref.watch(
      accountMembershipProvider.select((state) => state.entitlements),
    );
    final hasPro3Access = !_kEnableAiPaywall ||
        entitlements.any(
          (e) =>
              e['benefit_id'] == 'ai.advanced_thinking' &&
              e['status'] == 'granted',
        );

    return Material(
      color: Colors.transparent,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final mode in AIMode.values)
            _AIModeChip(
              mode: mode,
              isActive: mode == selectedMode,
              isLocked: mode == AIMode.pro3 && !hasPro3Access,
              onTap: () {
                if (mode == AIMode.pro3 && !hasPro3Access) {
                  _openPro3Paywall(context);
                  return;
                }
                ref.read(chatControllerProvider.notifier).setAIMode(mode);
              },
            ),
        ],
      ),
    );
  }
}

class _AIModeChip extends StatelessWidget {
  const _AIModeChip({
    required this.mode,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
  });

  final AIMode mode;
  final bool isActive;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = SamanPalette.of(context);
    final (name, description, defaultIcon) = switch (mode) {
      AIMode.swift3 => ('Swift 3', 'Nhanh gọn', Icons.bolt_outlined),
      AIMode.core3 => ('Core 3', 'Sẵn sàng', Icons.tune_outlined),
      AIMode.pro3 => ('Pro 3', 'Chuyên sâu', Icons.auto_awesome_outlined),
    };
    final badge = isActive
        ? 'Đang dùng'
        : (isLocked ? 'Pro' : description);
    final foreground = isActive
        ? colors.onPrimary
        : (isLocked ? palette.textMuted : colors.onSurface);
    final iconData = isActive
        ? Icons.check_circle_outline
        : (isLocked ? Icons.lock_outline : defaultIcon);

    return Semantics(
      button: true,
      selected: isActive,
      label: '$name, $badge',
      child: ChoiceChip(
        selected: isActive,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: colors.primary,
        backgroundColor: palette.surfaceElevated,
        side: BorderSide(
          color: isActive ? colors.primary : palette.border,
        ),
        avatar: Icon(
          iconData,
          size: 18,
          color: foreground,
        ),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
            Text(
              badge,
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
