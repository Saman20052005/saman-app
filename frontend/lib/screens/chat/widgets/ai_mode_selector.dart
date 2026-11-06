import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/chat_controller.dart';

class AIModeSelector extends ConsumerWidget {
  const AIModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = ref.watch(
      chatControllerProvider.select((state) => state.selectedAIMode),
    );
    return Material(
      color: Colors.transparent,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final mode in AIMode.values)
            _AIModeChip(mode: mode, isActive: mode == selectedMode),
        ],
      ),
    );
  }
}

class _AIModeChip extends StatelessWidget {
  const _AIModeChip({required this.mode, required this.isActive});

  final AIMode mode;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (name, explanation) = switch (mode) {
      AIMode.swift3 => (
          'Swift 3',
          'Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.',
        ),
      AIMode.core3 => ('Core 3', 'Core 3 đang hoạt động.'),
      AIMode.pro3 => (
          'Pro 3',
          'Chế độ Pro 3 sẽ ra mắt trong bản cập nhật tới.',
        ),
    };
    final badge = isActive ? 'Đang dùng' : 'Sắp ra mắt';
    final foreground = isActive ? colors.onPrimary : theme.disabledColor;

    // Locked chips cannot select a mode. The surrounding focusable control
    // only explains availability, including for keyboard and screen readers.
    return Semantics(
      button: true,
      selected: isActive,
      label: '$name, $badge. $explanation',
      child: InkWell(
        customBorder: theme.chipTheme.shape,
        onTap: () {
          if (isActive) return;
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(content: Text(explanation)));
        },
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: ChoiceChip(
              selected: isActive,
              onSelected: isActive ? (_) {} : null,
              showCheckmark: false,
              selectedColor: colors.primary,
              avatar: Icon(
                isActive ? Icons.check_circle_outline : Icons.lock_outline,
                color: foreground,
              ),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: foreground)),
                  Text(badge,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
