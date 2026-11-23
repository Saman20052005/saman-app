import 'package:flutter/material.dart';

import '../../../config/app_translations.dart';
import '../../../providers/coach_persona_provider.dart';
import '../tokens/saman_chat_tokens.dart';

/// Shows the anchored Persona Selector menu (Phong cách Coach).
///
/// Desktop: Opens to the right of the drawer / rail trigger.
/// Mobile: Opens directly below the trigger in the drawer with bounded height & scrolling.
Future<CoachPersona?> showCoachPersonaMenu({
  required BuildContext context,
  required Rect anchorRect,
  required CoachPersona currentPersona,
  required ValueChanged<CoachPersona> onSelectPersona,
  bool isDesktop = false,
  bool isSaving = false,
}) {
  return Navigator.of(context).push<CoachPersona>(
    _CoachPersonaPopupRoute(
      anchorRect: anchorRect,
      currentPersona: currentPersona,
      onSelectPersona: onSelectPersona,
      isDesktop: isDesktop,
      isSaving: isSaving,
    ),
  );
}

class _CoachPersonaPopupRoute extends PopupRoute<CoachPersona> {
  final Rect anchorRect;
  final CoachPersona currentPersona;
  final ValueChanged<CoachPersona> onSelectPersona;
  final bool isDesktop;
  final bool isSaving;

  _CoachPersonaPopupRoute({
    required this.anchorRect,
    required this.currentPersona,
    required this.onSelectPersona,
    required this.isDesktop,
    required this.isSaving,
  });

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Đóng menu phong cách Coach';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 165);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 115);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _CoachPersonaMenuOverlay(
      anchorRect: anchorRect,
      currentPersona: currentPersona,
      onSelectPersona: (persona) {
        onSelectPersona(persona);
        Navigator.of(context).pop(persona);
      },
      onClose: () => Navigator.of(context).pop(),
      isDesktop: isDesktop,
      isSaving: isSaving,
      animation: animation,
    );
  }
}

class _CoachPersonaMenuOverlay extends StatelessWidget {
  final Rect anchorRect;
  final CoachPersona currentPersona;
  final ValueChanged<CoachPersona> onSelectPersona;
  final VoidCallback onClose;
  final bool isDesktop;
  final bool isSaving;
  final Animation<double> animation;

  const _CoachPersonaMenuOverlay({
    required this.anchorRect,
    required this.currentPersona,
    required this.onSelectPersona,
    required this.onClose,
    required this.isDesktop,
    required this.isSaving,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final reduceMotion = mediaQuery.disableAnimations;

    final double menuWidth =
        isDesktop ? 310.0 : (screenSize.width - 28.0).clamp(260.0, 310.0);
    final double maxMenuHeight =
        (screenSize.height * 0.75).clamp(260.0, 480.0);

    double left;
    double top;

    if (isDesktop) {
      // Desktop: Open to the right of the drawer / rail trigger
      left = anchorRect.right > 0 ? (anchorRect.right + 8.0) : 268.0;
      if (left + menuWidth > screenSize.width - 12.0) {
        left = (screenSize.width - menuWidth - 12.0).clamp(8.0, double.infinity);
      }
      top = anchorRect.top > 0 ? anchorRect.top : 300.0;
      const estimatedHeight = 310.0;
      if (top + estimatedHeight > screenSize.height - 16.0) {
        top = (screenSize.height - estimatedHeight - 16.0)
            .clamp(16.0, double.infinity);
      }
    } else {
      // Mobile / narrow viewport: Open right below the trigger in drawer
      left = anchorRect.left > 0
          ? anchorRect.left.clamp(8.0, screenSize.width - menuWidth - 8.0)
          : 14.0;
      top = anchorRect.bottom > 0 ? (anchorRect.bottom + 4.0) : 340.0;
      const estimatedHeight = 290.0;
      if (top + estimatedHeight > screenSize.height - 16.0) {
        // If overflowing bottom, open above trigger
        top = (anchorRect.top - estimatedHeight - 4.0)
            .clamp(16.0, double.infinity);
      }
    }

    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        // Barrier to dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Positioned Floating Menu
        Positioned(
          left: left,
          top: top,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final opacity = reduceMotion ? 1.0 : curvedAnimation.value;
              final offsetY = reduceMotion ? 0.0 : (1.0 - curvedAnimation.value) * 6.0;

              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, offsetY),
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: SamanPersonaMenu(
                currentPersona: currentPersona,
                onSelectPersona: onSelectPersona,
                onClose: onClose,
                isDesktop: isDesktop,
                isSaving: isSaving,
                width: menuWidth,
                maxHeight: maxMenuHeight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone visual component for Persona selection (reusable in popups or dialogs).
class SamanPersonaMenu extends StatelessWidget {
  final CoachPersona currentPersona;
  final ValueChanged<CoachPersona> onSelectPersona;
  final VoidCallback onClose;
  final bool isDesktop;
  final bool isSaving;
  final double width;
  final double maxHeight;

  const SamanPersonaMenu({
    super.key,
    required this.currentPersona,
    required this.onSelectPersona,
    required this.onClose,
    this.isDesktop = false,
    this.isSaving = false,
    this.width = 300.0,
    this.maxHeight = 440.0,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: t.menuSurface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: t.menuBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: t.isDark
                ? const Color(0xA6000000)
                : const Color(0x1F0F172A),
            blurRadius: 36.0,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('persona_menu_title'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.textWhite,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Saman Preferences',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSaving)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation(t.greenAccent),
                        ),
                      )
                    else
                      Semantics(
                        button: true,
                        label: 'Đóng menu',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12.0),
                          onTap: onClose,
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 6.0),
              Divider(
                color: t.menuDivider,
                height: 1.0,
              ),
              const SizedBox(height: 6.0),

              // 3 Personas
              for (final persona in CoachPersona.values)
                _buildPersonaRow(t, persona),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonaRow(SamanChatPalette t, CoachPersona persona) {
    final isSelected = persona == currentPersona;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${persona.displayName}: ${persona.shortDescription}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10.0),
          hoverColor: t.menuItemHover,
          onTap: isSaving ? null : () => onSelectPersona(persona),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? t.greenAccent.withOpacity(0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10.0),
              border: isSelected
                  ? Border.all(
                      color: t.greenAccent.withOpacity(0.20),
                      width: 1.0,
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Icon / Emoji badge
                Container(
                  width: 36.0,
                  height: 36.0,
                  decoration: BoxDecoration(
                    color: t.isDark
                        ? const Color(0xFF252830)
                        : t.surfaceElevated,
                    borderRadius: BorderRadius.circular(9.0),
                    border: Border.all(
                      color: isSelected
                          ? t.greenAccent
                          : (t.isDark ? const Color(0xFF323642) : t.border),
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      persona.emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),

                // Name and Description
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isVi = Localizations.localeOf(context).languageCode == 'vi';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isVi ? persona.vietnameseTitle : persona.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? t.textWhite : t.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            isVi ? persona.vietnameseDesc : persona.shortDescription,
                            style: TextStyle(
                              fontSize: 11,
                              color: t.textMuted,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(width: 8.0),

                // Selected Checkmark
                if (isSelected)
                  Icon(
                    Icons.check_rounded,
                    color: t.greenAccent,
                    size: 18,
                  )
                else
                  const SizedBox(width: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
