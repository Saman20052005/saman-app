import 'package:flutter/material.dart';

import '../localization/shop_translations.dart';
import '../theme/shop_theme.dart';

/// Low-profile charcoal search pill for instant product queries.
///
/// Specs from design:
/// - Height: ~44px, full rounded pill.
/// - Surface: #16171B, subtle border #23252B.
/// - Clear button only rendered when input is non-empty.
class ShopSearchBar extends StatefulWidget {
  const ShopSearchBar({
    super.key,
    required this.onQueryChanged,
    required this.onClear,
    this.initialQuery,
  });

  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final String? initialQuery;

  @override
  State<ShopSearchBar> createState() => _ShopSearchBarState();
}

class _ShopSearchBarState extends State<ShopSearchBar> {
  late final TextEditingController _controller;
  bool _hasContent = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _hasContent = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasContent) {
      setState(() => _hasContent = hasText);
    }
  }

  @override
  void didUpdateWidget(covariant ShopSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery) {
      final current = _controller.text;
      final updated = widget.initialQuery ?? '';
      if (current != updated) {
        _controller.text = updated;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ShopTheme.surfaceCard,
        borderRadius: BorderRadius.circular(ShopTheme.radiusPill),
        border: Border.all(
          color: _hasContent ? ShopTheme.textMuted : ShopTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_rounded,
            size: 18,
            color: ShopTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onQueryChanged,
              style: ShopTheme.fontManrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: ShopTheme.textPrimary,
              ),
              cursorColor: ShopTheme.textPrimary,
              decoration: InputDecoration(
                hintText: ShopTranslations.of(context, 'search_placeholder'),
                hintStyle: ShopTheme.fontManrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: ShopTheme.textMuted,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_hasContent)
            GestureDetector(
              onTap: _clear,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: ShopTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

