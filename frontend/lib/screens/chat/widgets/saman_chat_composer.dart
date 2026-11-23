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
  final VoidCallback? onAttachLatestWorkout;
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
    this.onAttachLatestWorkout,
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

        final t = SamanChatTokens.of(overlayContext);

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
                        color: t.isDark ? t.surfaceElevated : t.surface,
                        borderRadius: BorderRadius.circular(14.0),
                        border: Border.all(
                          color: t.borderSubtle,
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: t.isDark
                                ? const Color(0x66000000)
                                : const Color(0x1A0F172A),
                            blurRadius: 16.0,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPopoverItem(
                              palette: t,
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
                            Divider(
                              height: 1.0,
                              thickness: 1.0,
                              color: t.borderSubtle,
                            ),
                            _buildPopoverItem(
                              palette: t,
                              icon: Icons.insights_outlined,
                              title: 'Phân tích lịch sử',
                              subtitle: '7, 14, 30 ngày',
                              onTap: () {
                                _closeAllPopovers();
                                widget.onOpenAnalytics?.call();
                              },
                            ),
                            Divider(
                              height: 1.0,
                              thickness: 1.0,
                              color: t.borderSubtle,
                            ),
                            _buildPopoverItem(
                              palette: t,
                              icon: Icons.fitness_center_outlined,
                              title: 'Đính kèm buổi tập gần nhất',
                              subtitle: 'Gửi ngữ cảnh buổi tập vào hội thoại',
                              onTap: () {
                                _closeAllPopovers();
                                if (widget.onAttachLatestWorkout != null) {
                                  widget.onAttachLatestWorkout!();
                                } else {
                                  const prompt =
                                      'Hãy phân tích buổi tập gần nhất của tôi và gợi ý cách phục hồi / điều chỉnh tiếp theo.';
                                  widget.controller.value = const TextEditingValue(
                                    text: prompt,
                                    selection: TextSelection.collapsed(
                                      offset: prompt.length,
                                    ),
                                  );
                                  _effectiveFocusNode.requestFocus();
                                }
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
          activeMode: widget.activeMode,
          onModeSelected: widget.onModeSelected,
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
    required SamanChatPalette palette,
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
        hoverColor: palette.actionRowHoverBg,
        focusColor: palette.actionRowFocusBg,
        highlightColor: palette.actionRowPressedBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 11.0),
          child: Row(
            children: [
              Icon(icon, size: 20.0, color: palette.textWhite),
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
                        fontWeight: FontWeight.w600,
                        color: palette.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textMuted,
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
    final t = SamanChatTokens.of(context);
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
                  hoverColor: t.actionRowHoverBg,
                  focusColor: t.actionRowFocusBg,
                  highlightColor: t.actionRowPressedBg,
                  onTap: _toggleToolsMenu,
                  child: AnimatedContainer(
                    duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                    width: 36.0,
                    height: 36.0,
                    decoration: BoxDecoration(
                      color: _isToolsMenuOpen
                          ? (t.isDark ? t.surface : t.borderSubtle)
                          : t.iconContainerBg,
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
                        color: _isToolsMenuOpen ? t.textWhite : t.textSecondary,
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
    final t = SamanChatTokens.of(context);
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
            hoverColor: t.actionRowHoverBg,
            focusColor: t.actionRowFocusBg,
            highlightColor: t.actionRowPressedBg,
            onTap: _toggleModeMenu,
            child: Container(
              height: 48.0,
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              decoration: BoxDecoration(
                color: _isModeMenuOpen
                    ? (t.isDark ? const Color(0x1FFFFFFF) : t.surfaceElevated)
                    : Colors.transparent,
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
                    decoration: BoxDecoration(
                      color: t.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    _modeTitle(context, widget.activeMode),
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: _isModeMenuOpen ? t.textWhite : t.textSecondary,
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
                      color: _isModeMenuOpen ? t.textWhite : t.textSecondary,
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
    final t = SamanChatTokens.of(context);
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
              color: t.composerStopBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: t.borderSubtle,
                width: 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 16.0,
              height: 16.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: t.textSecondary,
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
    final t = SamanChatTokens.of(context);
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
              hoverColor: t.actionRowHoverBg,
              focusColor: t.actionRowFocusBg,
              highlightColor: t.actionRowPressedBg,
              onTap: canSend ? widget.onSend : null,
              child: AnimatedContainer(
                duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 140),
                width: 36.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: canSend
                      ? (t.isDark ? t.greenAccent : t.composerSendBg)
                      : t.composerSendDisabledBg,
                  shape: BoxShape.circle,
                  boxShadow: canSend
                      ? [
                          BoxShadow(
                            color: t.greenAccent.withOpacity(t.isDark ? 0.35 : 0.25),
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
                      ? (t.isDark ? const Color(0xFF052E16) : t.composerSendIcon)
                      : t.composerSendDisabledIcon,
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
    final t = SamanChatTokens.of(context);
    return TextField(
      key: _textFieldKey,
      focusNode: _effectiveFocusNode,
      controller: widget.controller,
      enabled: true,
      style: t.composerInput,
      cursorColor: t.textWhite,
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
        hintStyle: t.composerHint.copyWith(
          color: t.isDark ? const Color(0xFF9CA3AF) : t.textMuted,
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
    final t = SamanChatTokens.of(context);

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
          color: t.composerBg,
          borderRadius: BorderRadius.circular(_hasText ? 22.0 : 26.0),
          border: Border.all(
            color: t.composerBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: t.isDark
                  ? const Color(0x33000000)
                  : const Color(0x140F172A),
              offset: const Offset(0, 4),
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
  final AIMode activeMode;
  final ValueChanged<AIMode>? onModeSelected;
  final VoidCallback onRequestFocusComposer;

  const _ModeMenuOverlay({
    required this.targetKey,
    required this.targetOffset,
    required this.targetSize,
    required this.opensUpward,
    required this.onClose,
    required this.activeMode,
    this.onModeSelected,
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
    final t = SamanChatTokens.of(context);
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: t.isDark ? t.surfaceElevated : t.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: t.borderSubtle,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: t.isDark ? const Color(0x66000000) : const Color(0x1A0F172A),
            blurRadius: 16.0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeItems(minTouchTarget: false),
            Divider(height: 1.0, thickness: 1.0, color: t.borderSubtle),
            _buildThinkingTriggerRow(isDesktop: true),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMainMenu() {
    final t = SamanChatTokens.of(context);
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: t.isDark ? t.surfaceElevated : t.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: t.borderSubtle,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: t.isDark ? const Color(0x66000000) : const Color(0x1A0F172A),
            blurRadius: 16.0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeItems(minTouchTarget: true),
            Divider(height: 1.0, thickness: 1.0, color: t.borderSubtle),
            _buildThinkingTriggerRow(isDesktop: false),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSubmenu() {
    final t = SamanChatTokens.of(context);
    return Container(
      width: 270.0,
      decoration: BoxDecoration(
        color: t.isDark ? t.surfaceElevated : t.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: t.borderSubtle,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: t.isDark ? const Color(0x66000000) : const Color(0x1A0F172A),
            blurRadius: 16.0,
            offset: const Offset(0, 6),
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
                hoverColor: t.actionRowHoverBg,
                focusColor: t.actionRowFocusBg,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 22.0,
                        color: t.textWhite,
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        context.tr('thinking_level_title'),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: t.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1.0, thickness: 1.0, color: t.borderSubtle),
            _buildThinkingItems(minTouchTarget: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmenuCard({required bool isMobile}) {
    final t = SamanChatTokens.of(context);
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
            color: t.isDark ? t.surfaceElevated : t.surface,
            borderRadius: BorderRadius.circular(14.0),
            border: Border.all(
              color: t.borderSubtle,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: t.isDark ? const Color(0x66000000) : const Color(0x1A0F172A),
                blurRadius: 16.0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14.0),
            child: _buildThinkingItems(minTouchTarget: isMobile),
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingItems({required bool minTouchTarget}) {
    final t = SamanChatTokens.of(context);
    final entries = <(AIMode, String, String, IconData)>[
      (AIMode.swift3, 'Low', 'thinking_low_sub', Icons.bolt_rounded),
      (AIMode.core3, 'Medium', 'thinking_med_sub', Icons.balance_outlined),
      (AIMode.pro3, 'High', 'thinking_high_sub', Icons.auto_awesome_rounded),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Divider(height: 1.0, thickness: 1.0, color: t.borderSubtle),
          Builder(builder: (context) {
            final (mode, title, subKey, icon) = entries[i];
            final isActive = mode == widget.activeMode;
            return _buildThinkingMenuItem(
              title: title,
              subtitle: context.tr(subKey),
              isActive: isActive,
              isLocked: false,
              icon: isActive ? Icons.check_rounded : icon,
              iconColor: isActive ? t.greenAccent : t.textMuted,
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

  Widget _buildThinkingTriggerRow({required bool isDesktop}) {
    final t = SamanChatTokens.of(context);
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
              focusColor: t.actionRowFocusBg,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: BoxConstraints(minHeight: isDesktop ? 36.0 : 48.0),
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? (t.isDark ? const Color(0x1FFFFFFF) : t.surfaceElevated)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: isHighlighted
                        ? (t.isDark ? const Color(0x33FFFFFF) : t.borderSubtle)
                        : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      context.tr('thinking_level_title'),
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: t.textWhite,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18.0,
                      color: isHighlighted
                          ? t.textWhite
                          : (t.isDark ? const Color(0xFFD5D8E0) : t.textSecondary),
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
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool minTouchTarget = false,
  }) {
    final t = SamanChatTokens.of(context);
    return Semantics(
      button: true,
      label: isActive
          ? '$title: $subtitle. ${context.tr('badge_active_using')}'
          : '$title: $subtitle',
      selected: isActive,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        hoverColor: t.actionRowHoverBg,
        focusColor: t.actionRowFocusBg,
        highlightColor: t.actionRowPressedBg,
        child: Container(
          constraints: BoxConstraints(
            minHeight: minTouchTarget ? 48.0 : 42.0,
          ),
          color: isActive
              ? (t.isDark ? const Color(0x0FFFFFFF) : t.surfaceElevated)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18.0,
                color: iconColor,
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
                        color: isActive ? t.textWhite : t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.0,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: t.greenAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(
                      color: t.greenAccent.withOpacity(0.40),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    context.tr('badge_active_using'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: t.greenAccent,
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
    final t = SamanChatTokens.of(context);
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
            Divider(height: 1.0, thickness: 1.0, color: t.borderSubtle),
          Builder(builder: (context) {
            final (mode, titleKey, subKey, icon) = entries[i];
            final isActive = mode == widget.activeMode;
            return _buildModeItem(
              title: context.tr(titleKey),
              subtitle: context.tr(subKey),
              isActive: isActive,
              badgeText: isActive ? context.tr('badge_active_using') : 'FREE',
              icon: isActive ? Icons.check_rounded : icon,
              iconColor: isActive ? t.greenAccent : t.textMuted,
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

  Widget _buildModeItem({
    required String title,
    required String subtitle,
    required bool isActive,
    required String badgeText,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool minTouchTarget = false,
  }) {
    final t = SamanChatTokens.of(context);
    return Semantics(
      button: true,
      label: isActive
          ? '$title: $subtitle. ${context.tr('badge_active_using')}'
          : '$title: $subtitle. $badgeText',
      selected: isActive,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        hoverColor: t.actionRowHoverBg,
        focusColor: t.actionRowFocusBg,
        highlightColor: t.actionRowPressedBg,
        child: Container(
          constraints: BoxConstraints(minHeight: minTouchTarget ? 48.0 : 42.0),
          color: isActive
              ? (t.isDark ? const Color(0x0FFFFFFF) : t.surfaceElevated)
              : Colors.transparent,
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
                        color: isActive ? t.textWhite : t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.0,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: isActive
                      ? t.greenAccent.withOpacity(0.15)
                      : (t.isDark ? const Color(0x1FFFFFFF) : t.surfaceElevated),
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(
                    color: isActive
                        ? t.greenAccent.withOpacity(0.40)
                        : (t.isDark ? const Color(0x33FFFFFF) : t.borderSubtle),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? t.greenAccent
                        : (t.isDark ? const Color(0xFFD5D8E0) : t.textSecondary),
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

