import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/app_translations.dart';
import '../../../controllers/chat_controller.dart';
import '../tokens/saman_chat_tokens.dart';

/// The approved CP-03 global composer visual system for Saman Chat.
///
/// Visual structure:
///   [ + / × ] [ Hỏi Saman về dinh dưỡng, bài tập... ] [ Core 3 v ] [ ^ (send) ]
///
/// Features:
/// - Single unified rounded container (borderRadius: 24.0)
/// - Left '+' button toggles tools popover (transforms into '×' when open)
/// - Multiline expandable input field, pinned bottom controls when expanding
/// - Vietnamese IME-aware Enter key handling (does not submit while actively composing)
/// - Mode button toggles AI Mode rollout popover (Core 3 active, Swift 3 & Pro 3 locked)
/// - Directional popovers: opens downward when space permits, flips upward near screen bottom or with keyboard
/// - Closes popover upon outside tap, re-tap, or Escape key without losing draft text
/// - Strict monochrome send button; passive waiting indicator during processing (mic hidden)
class SamanChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final bool isLoading;
  final String? loadingHintText;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onAttachFoodPhoto;
  final VoidCallback? onOpenAnalytics;
  final AIMode activeMode;
  final ValueChanged<AIMode>? onModeSelected;
  final String? hintText;

  const SamanChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.isLoading = false,
    this.loadingHintText,
    this.hintText,
    this.onAttachmentTap,
    this.onVoiceTap,
    this.onAttachFoodPhoto,
    this.onOpenAnalytics,
    this.activeMode = AIMode.core3,
    this.onModeSelected,
  });

  @override
  State<SamanChatComposer> createState() => _SamanChatComposerState();
}

class _SamanChatComposerState extends State<SamanChatComposer> with WidgetsBindingObserver {
  late final FocusNode _internalFocusNode;
  final LayerLink _toolsLayerLink = LayerLink();
  final LayerLink _modeLayerLink = LayerLink();
  final GlobalKey _toolsKey = GlobalKey();
  final GlobalKey _modeKey = GlobalKey();
  final GlobalKey _textFieldKey = GlobalKey();

  OverlayEntry? _activeOverlay;
  bool _isToolsMenuOpen = false;
  bool _isModeMenuOpen = false;
  bool _hasText = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant SamanChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _activeOverlay?.remove();
    _activeOverlay = null;
    WidgetsBinding.instance.removeObserver(this);
    _isToolsMenuOpen = false;
    _isModeMenuOpen = false;
    widget.controller.removeListener(_handleTextChange);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _activeOverlay == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activeOverlay?.markNeedsBuild();
      }
    });
  }

  @override
  void deactivate() {
    _closeAllPopovers(notify: false);
    super.deactivate();
  }

  void _handleTextChange() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      if (mounted) {
        setState(() => _hasText = hasText);
      }
    }
  }

  void _closeAllPopovers({bool notify = true}) {
    _activeOverlay?.remove();
    _activeOverlay = null;
    if (_isToolsMenuOpen || _isModeMenuOpen) {
      if (notify && mounted) {
        setState(() {
          _isToolsMenuOpen = false;
          _isModeMenuOpen = false;
        });
      } else {
        _isToolsMenuOpen = false;
        _isModeMenuOpen = false;
      }
    }
  }

  void _toggleToolsMenu() {
    if (_isToolsMenuOpen) {
      _closeAllPopovers();
      return;
    }
    _openToolsMenu();
  }

  void _openToolsMenu() {
    _closeAllPopovers();
    FocusManager.instance.primaryFocus?.unfocus();

    _activeOverlay = OverlayEntry(
      builder: (overlayContext) {
        final renderBox = _toolsKey.currentContext?.findRenderObject() as RenderBox?;
        final offset = (renderBox != null && renderBox.attached)
            ? renderBox.localToGlobal(Offset.zero)
            : Offset.zero;
        final targetHeight = (renderBox != null && renderBox.attached)
            ? renderBox.size.height
            : 36.0;
        final mediaQuery = MediaQuery.of(overlayContext);
        final screenHeight = mediaQuery.size.height;
        final topSafe = mediaQuery.padding.top + 8.0;
        final bottomSafe = mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom + 8.0;
        final spaceAbove = offset.dy - topSafe;
        final spaceBelow = screenHeight - (offset.dy + targetHeight) - bottomSafe;
        final effectiveOpensUpward = spaceAbove >= 180.0 || spaceAbove >= spaceBelow;

        return Stack(
          children: [
            // Barrier
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeAllPopovers,
              ),
            ),
            // Popover Card
            Positioned(
              child: CompositedTransformFollower(
                link: _toolsLayerLink,
                showWhenUnlinked: false,
                targetAnchor: effectiveOpensUpward ? Alignment.topLeft : Alignment.bottomLeft,
                followerAnchor: effectiveOpensUpward ? Alignment.bottomLeft : Alignment.topLeft,
                offset: Offset(0, effectiveOpensUpward ? -8.0 : 8.0),
                child: FocusScope(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                      _closeAllPopovers();
                      _effectiveFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: _AnimatedPopoverCard(
                      opensUpward: effectiveOpensUpward,
                      child: Container(
                        width: 250.0,
                      decoration: BoxDecoration(
                        color: SamanChatTokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(14.0),
                        border: Border.all(
                          color: SamanChatTokens.borderSubtle,
                          width: 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 16.0,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPopoverItem(
                              icon: Icons.add_a_photo_outlined,
                              title: 'Phân tích ảnh món ăn',
                              subtitle: 'Standard & Advanced AI',
                              onTap: () {
                                _closeAllPopovers();
                                if (widget.onAttachFoodPhoto != null) {
                                  widget.onAttachFoodPhoto!();
                                } else {
                                  widget.onAttachmentTap?.call();
                                }
                              },
                            ),
                            const Divider(
                              height: 1.0,
                              thickness: 1.0,
                              color: SamanChatTokens.borderSubtle,
                            ),
                            _buildPopoverItem(
                              icon: Icons.insights_outlined,
                              title: 'Phân tích lịch sử',
                              subtitle: '7, 14, 30 ngày',
                              onTap: () {
                                _closeAllPopovers();
                                widget.onOpenAnalytics?.call();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Overlay.of(context).insert(_activeOverlay!);
  setState(() => _isToolsMenuOpen = true);
}

  void _toggleModeMenu() {
    if (_isModeMenuOpen) {
      _closeAllPopovers();
      return;
    }
    _openModeMenu();
  }

  void _openModeMenu() {
    _closeAllPopovers();
    FocusManager.instance.primaryFocus?.unfocus();
    final renderBox = _modeKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final targetSize = renderBox?.size ?? const Size(72.0, 36.0);
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final topSafe = mediaQuery.padding.top + 8.0;
    final bottomSafe = mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom + 8.0;
    final spaceAbove = offset.dy - topSafe;
    final spaceBelow = screenHeight - (offset.dy + targetSize.height) - bottomSafe;
    final opensUpward = spaceAbove >= 220.0 || spaceAbove >= spaceBelow;

    _activeOverlay = OverlayEntry(
      builder: (overlayContext) {
        return _ModeMenuOverlay(
          targetKey: _modeKey,
          targetOffset: offset,
          targetSize: targetSize,
          opensUpward: opensUpward,
          onClose: _closeAllPopovers,
          onSelectMedium: () {
            _closeAllPopovers();
          },
          activeMode: widget.activeMode,
          onModeSelected: widget.onModeSelected,
          onLockedThinkingLevelTapped: (level) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(
              SnackBar(
                content: Text(context.tr('badge_coming_soon')),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onRequestFocusComposer: () {
            _effectiveFocusNode.requestFocus();
          },
        );
      },
    );

    Overlay.of(context).insert(_activeOverlay!);
    setState(() => _isModeMenuOpen = true);
  }

Widget _buildPopoverItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title: $subtitle',
      child: InkWell(
        onTap: onTap,
        hoverColor: SamanChatTokens.actionRowHoverBg,
        focusColor: SamanChatTokens.actionRowFocusBg,
        highlightColor: SamanChatTokens.actionRowPressedBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
          child: Row(
            children: [
              Icon(icon, size: 20.0, color: SamanChatTokens.textWhite),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: SamanChatTokens.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolsButton({required bool disableAnimations}) {
    return CompositedTransformTarget(
      link: _toolsLayerLink,
      child: Semantics(
        button: true,
        label: _isToolsMenuOpen ? 'Đóng công cụ' : 'Thêm công cụ',
        child: Tooltip(
          message: _isToolsMenuOpen ? 'Đóng công cụ' : 'Thêm công cụ',
          child: SizedBox(
            width: 48.0,
            height: 48.0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: _toolsKey,
                  borderRadius: BorderRadius.circular(18.0),
                  hoverColor: SamanChatTokens.actionRowHoverBg,
                  focusColor: SamanChatTokens.actionRowFocusBg,
                  highlightColor: SamanChatTokens.actionRowPressedBg,
                  onTap: _toggleToolsMenu,
                  child: AnimatedContainer(
                    duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                    width: 36.0,
                    height: 36.0,
                    decoration: BoxDecoration(
                      color: _isToolsMenuOpen ? SamanChatTokens.surface : SamanChatTokens.iconContainerBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                      transitionBuilder: (child, animation) => RotationTransition(
                        turns: Tween<double>(begin: 0.875, end: 1.0).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        _isToolsMenuOpen ? Icons.close_rounded : Icons.add_rounded,
                        key: ValueKey(_isToolsMenuOpen ? 'tools_close_icon' : 'tools_add_icon'),
                        color: _isToolsMenuOpen ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                        size: 20.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _modeTitle(BuildContext context, AIMode mode) {
    return switch (mode) {
      AIMode.swift3 => context.tr('model_swift_3_title'),
      AIMode.core3 => context.tr('model_core_3_title'),
      AIMode.pro3 => context.tr('model_pro_3_title'),
    };
  }

  Widget _buildModeButton({required bool disableAnimations}) {
    return CompositedTransformTarget(
      link: _modeLayerLink,
      child: Semantics(
        button: true,
        label: 'AI: ${_modeTitle(context, widget.activeMode)}. ',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: _modeKey,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(16.0),
            hoverColor: SamanChatTokens.actionRowHoverBg,
            focusColor: SamanChatTokens.actionRowFocusBg,
            highlightColor: SamanChatTokens.actionRowPressedBg,
            onTap: _toggleModeMenu,
            child: Container(
              height: 48.0,
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              decoration: BoxDecoration(
                color: _isModeMenuOpen ? const Color(0x1FFFFFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(16.0),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6.0,
                    height: 6.0,
                    margin: const EdgeInsets.only(right: 6.0),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    _modeTitle(context, widget.activeMode),
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: _isModeMenuOpen ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2.0),
                  AnimatedSwitcher(
                    duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                    transitionBuilder: (child, animation) => RotationTransition(
                      turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      _isModeMenuOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      key: ValueKey(_isModeMenuOpen ? 'mode_chevron_up' : 'mode_chevron_down'),
                      size: 18.0,
                      color: _isModeMenuOpen ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Semantics(
      label: widget.loadingHintText ?? 'Saman đang phản hồi',
      child: SizedBox(
        width: 48.0,
        height: 48.0,
        child: Center(
          child: Container(
            width: 34.0,
            height: 34.0,
            decoration: BoxDecoration(
              color: SamanChatTokens.composerStopBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: SamanChatTokens.borderSubtle,
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 16.0,
              height: 16.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: SamanChatTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton({required bool canSend, required bool disableAnimations}) {
    if (widget.isLoading) {
      return _buildLoadingIndicator();
    }
    return Semantics(
      button: true,
      enabled: canSend,
      label: 'Gửi tin nhắn',
      child: SizedBox(
        width: 48.0,
        height: 48.0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18.0),
              hoverColor: SamanChatTokens.actionRowHoverBg,
              focusColor: SamanChatTokens.actionRowFocusBg,
              highlightColor: SamanChatTokens.actionRowPressedBg,
              onTap: canSend ? widget.onSend : null,
              child: AnimatedContainer(
                duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: canSend
                      ? SamanChatTokens.greenAccent
                      : SamanChatTokens.composerSendDisabledBg,
                  shape: BoxShape.circle,
                  boxShadow: canSend
                      ? [
                          BoxShadow(
                            color: SamanChatTokens.greenAccent.withOpacity(0.35),
                            offset: const Offset(0, 2),
                            blurRadius: 6.0,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: canSend
                      ? const Color(0xFF052E16)
                      : SamanChatTokens.composerSendDisabledIcon,
                  size: 20.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({required bool isSingleLine, required bool canSend}) {
    return TextField(
      key: _textFieldKey,
      focusNode: _effectiveFocusNode,
      controller: widget.controller,
      enabled: true,
      style: SamanChatTokens.composerInput,
      cursorColor: SamanChatTokens.textWhite,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.send,
      minLines: 1,
      maxLines: isSingleLine ? 1 : 5,
      textAlignVertical: isSingleLine ? TextAlignVertical.center : TextAlignVertical.top,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.transparent,
        hoverColor: Colors.transparent,
        hintText: widget.hintText ?? 'Hỏi Saman...',
        hintStyle: SamanChatTokens.composerHint.copyWith(
          color: const Color(0xFF9CA3AF),
        ),
        isDense: true,
        contentPadding: isSingleLine
            ? const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0)
            : const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
      onSubmitted: (value) {
        if (widget.controller.value.composing.isValid &&
            !widget.controller.value.composing.isCollapsed) {
          return;
        }
        if (canSend) widget.onSend();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.isLoading && _hasText;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isToolsMenuOpen || _isModeMenuOpen) {
              _closeAllPopovers();
              _effectiveFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
            final composing = widget.controller.value.composing;
            if (composing.isValid && !composing.isCollapsed) {
              return KeyEventResult.ignored;
            }
            if (canSend) {
              widget.onSend();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(minHeight: _hasText ? 88.0 : 52.0),
        padding: _hasText
            ? const EdgeInsets.fromLTRB(14.0, 10.0, 12.0, 8.0)
            : const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: SamanChatTokens.composerBg,
          borderRadius: BorderRadius.circular(_hasText ? 22.0 : 26.0),
          border: Border.all(
            color: SamanChatTokens.composerBorder,
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(0, 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: _hasText
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140.0),
                    child: _buildInputField(isSingleLine: false, canSend: canSend),
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildToolsButton(disableAnimations: disableAnimations),
                      const Spacer(),
                      _buildModeButton(disableAnimations: disableAnimations),
                      const SizedBox(width: 8.0),
                      _buildSendButton(canSend: canSend, disableAnimations: disableAnimations),
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildToolsButton(disableAnimations: disableAnimations),
                  const SizedBox(width: 4.0),
                  Expanded(
                    child: _buildInputField(isSingleLine: true, canSend: canSend),
                  ),
                  const SizedBox(width: 4.0),
                  _buildModeButton(disableAnimations: disableAnimations),
                  if (widget.isLoading) ...[
                    const SizedBox(width: 4.0),
                    _buildLoadingIndicator(),
                  ],
                ],
              ),
      ),
    );
  }
}

class _AnimatedPopoverCard extends StatefulWidget {
  final Widget child;
  final bool opensUpward;

  const _AnimatedPopoverCard({
    required this.child,
    required this.opensUpward,
  });

  @override
  State<_AnimatedPopoverCard> createState() => _AnimatedPopoverCardState();
}

class _AnimatedPopoverCardState extends State<_AnimatedPopoverCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    final beginOffset = widget.opensUpward ? const Offset(0, 6.0) : const Offset(0, -6.0);
    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ModeMenuOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final Offset targetOffset;
  final Size targetSize;
  final bool opensUpward;
  final VoidCallback onClose;
  final VoidCallback onSelectMedium;
  final AIMode activeMode;
  final ValueChanged<AIMode>? onModeSelected;
  final ValueChanged<String> onLockedThinkingLevelTapped;
  final VoidCallback onRequestFocusComposer;

  const _ModeMenuOverlay({
    required this.targetKey,
    required this.targetOffset,
    required this.targetSize,
    required this.opensUpward,
    required this.onClose,
    required this.onSelectMedium,
    required this.activeMode,
    this.onModeSelected,
    required this.onLockedThinkingLevelTapped,
    required this.onRequestFocusComposer,
  });

  @override
  State<_ModeMenuOverlay> createState() => _ModeMenuOverlayState();
}

class _ModeMenuOverlayState extends State<_ModeMenuOverlay> {
  bool _isThinkingSubmenuOpen = false;
  bool _isHoveringTrigger = false;
  bool _isHoveringSubmenu = false;
  Timer? _openDebounceTimer;
  Timer? _closeGraceTimer;
  late final FocusNode _triggerFocusNode;
  final GlobalKey _triggerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _triggerFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _openDebounceTimer?.cancel();
    _closeGraceTimer?.cancel();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isDesktop = screenSize.width >= 600.0;
    const mainMenuWidth = 270.0;
    const submenuWidth = 240.0;
    const gap = 6.0;

    final targetBox = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetOffset = (targetBox != null && targetBox.attached)
        ? targetBox.localToGlobal(Offset.zero)
        : widget.targetOffset;
    final targetSize = (targetBox != null && targetBox.attached)
        ? targetBox.size
        : widget.targetSize;

    final modeRight = targetOffset.dx + targetSize.width;
    double mainMenuLeft = modeRight - mainMenuWidth;
    mainMenuLeft = mainMenuLeft.clamp(12.0, screenSize.width - mainMenuWidth - 12.0);
    final mainMenuRight = mainMenuLeft + mainMenuWidth;

    final topSafe = mediaQuery.padding.top + 8.0;
    final bottomSafe = mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom + 8.0;

    final spaceAbove = targetOffset.dy - topSafe;
    final spaceBelow = screenSize.height - (targetOffset.dy + targetSize.height) - bottomSafe;
    final effectiveOpensUpward = spaceAbove >= 220.0 || spaceAbove >= spaceBelow;

    final double? mainMenuTop = effectiveOpensUpward
        ? null
        : (targetOffset.dy + targetSize.height + 8.0).clamp(
            topSafe,
            (screenSize.height - bottomSafe - 80.0).clamp(topSafe, screenSize.height),
          );
    final double? mainMenuBottom = effectiveOpensUpward
        ? (screenSize.height - targetOffset.dy + 8.0).clamp(
            bottomSafe,
            (screenSize.height - topSafe - 80.0).clamp(bottomSafe, screenSize.height),
          )
        : null;
    final double maxMenuHeight = effectiveOpensUpward
        ? (screenSize.height - mainMenuBottom! - topSafe).clamp(120.0, screenSize.height * 0.65)
        : (screenSize.height - mainMenuTop! - bottomSafe).clamp(120.0, screenSize.height * 0.65);

    final spaceToRight = screenSize.width - mainMenuRight;
    final openToRight = spaceToRight >= (submenuWidth + 12.0);
    final double submenuLeft = openToRight ? (mainMenuRight + gap) : (mainMenuLeft - gap - submenuWidth);

    double? resolvedSubmenuBottom = mainMenuBottom;
    double? resolvedSubmenuTop = mainMenuTop;
    final triggerBox = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (triggerBox != null && triggerBox.attached) {
      final triggerOffset = triggerBox.localToGlobal(Offset.zero);
      resolvedSubmenuBottom = screenSize.height - (triggerOffset.dy + triggerBox.size.height);
      resolvedSubmenuTop = null;
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_isThinkingSubmenuOpen) {
          setState(() => _isThinkingSubmenuOpen = false);
          return;
        }
        widget.onClose();
      },
      child: Stack(
          children: [
            // 1. Barrier
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onClose,
              ),
            ),

            // 2. Main Menu Card
            Positioned(
              left: mainMenuLeft,
              top: mainMenuTop,
              bottom: mainMenuBottom,
              width: mainMenuWidth,
              child: Material(
                color: Colors.transparent,
                child: _AnimatedPopoverCard(
                  opensUpward: effectiveOpensUpward,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxMenuHeight),
                    child: SingleChildScrollView(
                      child: isDesktop
                          ? _buildDesktopMainMenu()
                          : (_isThinkingSubmenuOpen ? _buildMobileSubmenu() : _buildMobileMainMenu()),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Hover bridge between menus on desktop
            if (isDesktop && _isThinkingSubmenuOpen)
              Positioned(
                left: openToRight ? mainMenuRight : (submenuLeft + submenuWidth),
                top: resolvedSubmenuTop,
                bottom: resolvedSubmenuBottom,
                width: gap + 2.0,
                height: 220.0,
                child: MouseRegion(
                  hitTestBehavior: HitTestBehavior.translucent,
                  onEnter: (_) => _closeGraceTimer?.cancel(),
                ),
              ),

            // 4. Desktop Submenu Card
            if (isDesktop && _isThinkingSubmenuOpen)
              Positioned(
                left: submenuLeft,
                top: resolvedSubmenuTop,
                bottom: resolvedSubmenuBottom,
                width: submenuWidth,
                child: Material(
                  color: Colors.transparent,
                  child: _AnimatedSubmenuCard(
                    openToRight: openToRight,
                    child: _buildSubmenuCard(isMobile: false),
                  ),
                ),
              ),
          ],
        ),
    );
  }

  Widget _buildDesktopMainMenu() {
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: SamanChatTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16.0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeItems(minTouchTarget: false),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingTriggerRow(isDesktop: true),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMainMenu() {
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: SamanChatTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16.0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeItems(minTouchTarget: true),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingTriggerRow(isDesktop: false),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSubmenu() {
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: SamanChatTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16.0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: 'Quay lại menu chế độ AI',
              child: InkWell(
                canRequestFocus: false,
                onTap: () {
                  setState(() => _isThinkingSubmenuOpen = false);
                },
                hoverColor: SamanChatTokens.actionRowHoverBg,
                focusColor: SamanChatTokens.actionRowFocusBg,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chevron_left_rounded,
                        size: 22.0,
                        color: SamanChatTokens.textWhite,
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        context.tr('thinking_level_title'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: SamanChatTokens.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingMenuItem(
              title: 'Low',
              subtitle: context.tr('thinking_low_sub'),
              isActive: false,
              isLocked: true,
              badgeText: context.tr('badge_coming_soon'),
              onTap: () => widget.onLockedThinkingLevelTapped('Low'),
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingMenuItem(
              title: 'Medium',
              subtitle: context.tr('thinking_med_sub'),
              isActive: true,
              isLocked: false,
              onTap: widget.onSelectMedium,
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingMenuItem(
              title: 'High',
              subtitle: context.tr('thinking_high_sub'),
              isActive: false,
              isLocked: true,
              badgeText: context.tr('badge_coming_soon'),
              onTap: () => widget.onLockedThinkingLevelTapped('High'),
              minTouchTarget: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmenuCard({required bool isMobile}) {
    return MouseRegion(
      onEnter: (_) {
        _closeGraceTimer?.cancel();
        _isHoveringSubmenu = true;
      },
      onExit: (_) {
        _isHoveringSubmenu = false;
        _closeGraceTimer?.cancel();
        _closeGraceTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted && !_isHoveringSubmenu && !_isHoveringTrigger) {
            setState(() => _isThinkingSubmenuOpen = false);
          }
        });
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            setState(() => _isThinkingSubmenuOpen = false);
            _triggerFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 240.0,
          decoration: BoxDecoration(
            color: SamanChatTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(14.0),
            border: Border.all(
              color: SamanChatTokens.borderSubtle,
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 16.0,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThinkingMenuItem(
                  title: 'Low',
                  subtitle: context.tr('thinking_low_sub'),
                  isActive: false,
                  isLocked: true,
                  badgeText: context.tr('badge_coming_soon'),
                  onTap: () => widget.onLockedThinkingLevelTapped('Low'),
                  minTouchTarget: isMobile,
                ),
                const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
                _buildThinkingMenuItem(
                  title: 'Medium',
                  subtitle: context.tr('thinking_med_sub'),
                  isActive: true,
                  isLocked: false,
                  onTap: widget.onSelectMedium,
                  minTouchTarget: isMobile,
                ),
                const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
                _buildThinkingMenuItem(
                  title: 'High',
                  subtitle: context.tr('thinking_high_sub'),
                  isActive: false,
                  isLocked: true,
                  badgeText: context.tr('badge_coming_soon'),
                  onTap: () => widget.onLockedThinkingLevelTapped('High'),
                  minTouchTarget: isMobile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingTriggerRow({required bool isDesktop}) {
    final isHighlighted = _isHoveringTrigger || _isThinkingSubmenuOpen;
    return Semantics(
      button: true,
      label:
          '${context.tr('thinking_level_title')}. ${_isThinkingSubmenuOpen ? "Open" : "Closed"}',
      child: MouseRegion(
        onEnter: isDesktop
            ? (_) {
                _closeGraceTimer?.cancel();
                _isHoveringTrigger = true;
                _openDebounceTimer?.cancel();
                _openDebounceTimer = Timer(const Duration(milliseconds: 150), () {
                  if (mounted && _isHoveringTrigger) {
                    setState(() => _isThinkingSubmenuOpen = true);
                  }
                });
              }
            : null,
        onExit: isDesktop
            ? (_) {
                _isHoveringTrigger = false;
                _openDebounceTimer?.cancel();
                _closeGraceTimer?.cancel();
                _closeGraceTimer = Timer(const Duration(milliseconds: 200), () {
                  if (mounted && !_isHoveringSubmenu && !_isHoveringTrigger) {
                    setState(() => _isThinkingSubmenuOpen = false);
                  }
                });
              }
            : null,
        child: Focus(
          focusNode: _triggerFocusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                setState(() => _isThinkingSubmenuOpen = true);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            key: _triggerKey,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: InkWell(
              canRequestFocus: false,
              onTap: () {
                setState(() => _isThinkingSubmenuOpen = !_isThinkingSubmenuOpen);
              },
              borderRadius: BorderRadius.circular(10.0),
              hoverColor: Colors.transparent,
              focusColor: SamanChatTokens.actionRowFocusBg,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: BoxConstraints(minHeight: isDesktop ? 36.0 : 48.0),
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: isHighlighted ? const Color(0x1FFFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: isHighlighted ? const Color(0x33FFFFFF) : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      context.tr('thinking_level_title'),
                      style: const TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: SamanChatTokens.textWhite,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18.0,
                      color: isHighlighted
                          ? SamanChatTokens.textWhite
                          : const Color(0xFFD5D8E0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingMenuItem({
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isLocked,
    String? badgeText,
    required VoidCallback onTap,
    bool minTouchTarget = false,
  }) {
    return Semantics(
      button: true,
      label: isActive
          ? '$title: $subtitle. ${context.tr('badge_active_using')}'
          : '$title: $subtitle. ${badgeText ?? "Đang khóa"} (giữ nguyên mức hiện tại)',
      selected: isActive,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        hoverColor: SamanChatTokens.actionRowHoverBg,
        focusColor: SamanChatTokens.actionRowFocusBg,
        highlightColor: SamanChatTokens.actionRowPressedBg,
        child: Container(
          constraints: BoxConstraints(
            minHeight: minTouchTarget ? 48.0 : 42.0,
          ),
          color: isActive ? const Color(0x0FFFFFFF) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              if (isActive)
                const Icon(
                  Icons.check_rounded,
                  size: 18.0,
                  color: SamanChatTokens.greenAccent,
                )
              else
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16.0,
                  color: SamanChatTokens.textMuted,
                ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.0,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(
                      color: const Color(0x33FFFFFF),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD5D8E0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeItems({required bool minTouchTarget}) {
    final entries = <(AIMode, String, String, IconData)>[
      (AIMode.swift3, 'model_swift_3_title', 'model_swift_3_sub', Icons.bolt_rounded),
      (AIMode.core3, 'model_core_3_title', 'model_core_3_sub', Icons.balance_outlined),
      (AIMode.pro3, 'model_pro_3_title', 'model_pro_3_sub', Icons.auto_awesome_rounded),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
          Builder(builder: (context) {
            final (mode, titleKey, subKey, icon) = entries[i];
            final isActive = mode == widget.activeMode;
            return _buildModeItem(
              title: context.tr(titleKey),
              subtitle: context.tr(subKey),
              isActive: isActive,
              badgeText: isActive ? context.tr('badge_active_using') : 'FREE',
              icon: isActive ? Icons.check_rounded : icon,
              iconColor: isActive ? const Color(0xFF10B981) : SamanChatTokens.textMuted,
              onTap: () {
                widget.onModeSelected?.call(mode);
                widget.onClose();
              },
              minTouchTarget: minTouchTarget,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildModeItem({    required String title,
    required String subtitle,
    required bool isActive,
    required String badgeText,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool minTouchTarget = false,
  }) {
    return Semantics(
      button: true,
      label: isActive
          ? '$title: $subtitle. ${context.tr('badge_active_using')}'
          : '$title: $subtitle. $badgeText',
      selected: isActive,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        hoverColor: SamanChatTokens.actionRowHoverBg,
        focusColor: SamanChatTokens.actionRowFocusBg,
        highlightColor: SamanChatTokens.actionRowPressedBg,
        child: Container(
          constraints: BoxConstraints(minHeight: minTouchTarget ? 48.0 : 42.0),
          color: isActive ? const Color(0x0FFFFFFF) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(icon, size: 18.0, color: iconColor),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? SamanChatTokens.textWhite : SamanChatTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.0,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0x2610B981) : const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: isActive ? const Color(0x6610B981) : const Color(0x33FFFFFF),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isActive ? SamanChatTokens.greenAccent : const Color(0xFFD5D8E0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedSubmenuCard extends StatefulWidget {
  final Widget child;
  final bool openToRight;

  const _AnimatedSubmenuCard({
    required this.child,
    required this.openToRight,
  });

  @override
  State<_AnimatedSubmenuCard> createState() => _AnimatedSubmenuCardState();
}

class _AnimatedSubmenuCardState extends State<_AnimatedSubmenuCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    final beginOffset = widget.openToRight ? const Offset(-5.0, 0.0) : const Offset(5.0, 0.0);
    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

