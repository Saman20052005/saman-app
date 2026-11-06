import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (_isToolsMenuOpen || _isModeMenuOpen) {
      _closeAllPopovers();
    }
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
    final renderBox = _toolsKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final spaceBelow = screenHeight - keyboardHeight - (offset.dy + (renderBox?.size.height ?? 36.0));
    final opensUpward = spaceBelow < 180.0 || keyboardHeight > 0;

    _activeOverlay = OverlayEntry(
      builder: (context) {
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
                targetAnchor: opensUpward ? Alignment.topLeft : Alignment.bottomLeft,
                followerAnchor: opensUpward ? Alignment.bottomLeft : Alignment.topLeft,
                offset: Offset(0, opensUpward ? -8.0 : 8.0),
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
                      opensUpward: opensUpward,
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
    final renderBox = _modeKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final spaceBelow = screenHeight - keyboardHeight - (offset.dy + (renderBox?.size.height ?? 36.0));
    final opensUpward = spaceBelow < 220.0 || keyboardHeight > 0;

    _activeOverlay = OverlayEntry(
      builder: (context) {
        return _ModeMenuOverlay(
          targetOffset: offset,
          targetSize: renderBox?.size ?? const Size(72.0, 36.0),
          opensUpward: opensUpward,
          onClose: _closeAllPopovers,
          onSelectMedium: () {
            _closeAllPopovers();
            _effectiveFocusNode.requestFocus();
          },
          onSwift3Tapped: () {
            _closeAllPopovers();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onPro3Tapped: () {
            _closeAllPopovers();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chế độ Pro 3 sẽ ra mắt trong bản cập nhật tới.'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onLockedThinkingLevelTapped: (level) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mức suy luận này chưa được mở'),
                duration: Duration(seconds: 2),
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

  Widget _buildModeButton({required bool disableAnimations}) {
    return CompositedTransformTarget(
      link: _modeLayerLink,
      child: Semantics(
        button: true,
        label: 'Chế độ AI: Core 3. ',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: _modeKey,
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
                  Text(
                    'Core 3',
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
                      ? Colors.white
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
        hintText: widget.hintText ?? 'Hỏi Saman về dinh dưỡng, bài tập, phục hồi...',
        hintStyle: SamanChatTokens.composerHint,
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
  final Offset targetOffset;
  final Size targetSize;
  final bool opensUpward;
  final VoidCallback onClose;
  final VoidCallback onSelectMedium;
  final VoidCallback onSwift3Tapped;
  final VoidCallback onPro3Tapped;
  final ValueChanged<String> onLockedThinkingLevelTapped;
  final VoidCallback onRequestFocusComposer;

  const _ModeMenuOverlay({
    required this.targetOffset,
    required this.targetSize,
    required this.opensUpward,
    required this.onClose,
    required this.onSelectMedium,
    required this.onSwift3Tapped,
    required this.onPro3Tapped,
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
  late final FocusScopeNode _overlayFocusScopeNode;
  final GlobalKey _triggerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _triggerFocusNode = FocusNode();
    _overlayFocusScopeNode = FocusScopeNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _triggerFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _openDebounceTimer?.cancel();
    _closeGraceTimer?.cancel();
    _triggerFocusNode.dispose();
    _overlayFocusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 600.0;
    const mainMenuWidth = 270.0;
    const submenuWidth = 240.0;
    const gap = 6.0;

    final modeRight = widget.targetOffset.dx + widget.targetSize.width;
    double mainMenuLeft = modeRight - mainMenuWidth;
    mainMenuLeft = mainMenuLeft.clamp(12.0, screenSize.width - mainMenuWidth - 12.0);
    final mainMenuRight = mainMenuLeft + mainMenuWidth;

    final opensUpward = widget.opensUpward;
    final double? mainMenuTop = opensUpward ? null : widget.targetOffset.dy + widget.targetSize.height + 8.0;
    final double? mainMenuBottom = opensUpward ? (screenSize.height - widget.targetOffset.dy + 8.0) : null;

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

    return FocusScope(
      node: _overlayFocusScopeNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          if (_isThinkingSubmenuOpen) {
            setState(() => _isThinkingSubmenuOpen = false);
            _triggerFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          widget.onClose();
          widget.onRequestFocusComposer();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          if (_isThinkingSubmenuOpen) {
            setState(() => _isThinkingSubmenuOpen = false);
            return;
          }
          widget.onClose();
          widget.onRequestFocusComposer();
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
                  opensUpward: opensUpward,
                  child: isDesktop
                      ? _buildDesktopMainMenu()
                      : (_isThinkingSubmenuOpen ? _buildMobileSubmenu() : _buildMobileMainMenu()),
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
            _buildModeItem(
              title: 'Core 3',
              subtitle: 'Mặc định toàn diện',
              isActive: true,
              badgeText: 'Đang dùng',
              icon: Icons.check_rounded,
              iconColor: SamanChatTokens.greenAccent,
              onTap: widget.onClose,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildModeItem(
              title: 'Swift 3',
              subtitle: 'Phản hồi nhanh, câu hỏi ngắn',
              isActive: false,
              badgeText: 'Sắp ra mắt',
              icon: Icons.lock_outline_rounded,
              iconColor: SamanChatTokens.textMuted,
              onTap: widget.onSwift3Tapped,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildModeItem(
              title: 'Pro 3',
              subtitle: 'Suy luận chuyên sâu & kế hoạch dài hạn',
              isActive: false,
              badgeText: 'Sắp ra mắt',
              icon: Icons.lock_outline_rounded,
              iconColor: SamanChatTokens.textMuted,
              onTap: widget.onPro3Tapped,
            ),
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
            _buildModeItem(
              title: 'Core 3',
              subtitle: 'Mặc định toàn diện',
              isActive: true,
              badgeText: 'Đang dùng',
              icon: Icons.check_rounded,
              iconColor: SamanChatTokens.greenAccent,
              onTap: widget.onClose,
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildModeItem(
              title: 'Swift 3',
              subtitle: 'Phản hồi nhanh, câu hỏi ngắn',
              isActive: false,
              badgeText: 'Sắp ra mắt',
              icon: Icons.lock_outline_rounded,
              iconColor: SamanChatTokens.textMuted,
              onTap: widget.onSwift3Tapped,
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildModeItem(
              title: 'Pro 3',
              subtitle: 'Suy luận chuyên sâu & kế hoạch dài hạn',
              isActive: false,
              badgeText: 'Sắp ra mắt',
              icon: Icons.lock_outline_rounded,
              iconColor: SamanChatTokens.textMuted,
              onTap: widget.onPro3Tapped,
              minTouchTarget: true,
            ),
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
                onTap: () {
                  setState(() => _isThinkingSubmenuOpen = false);
                },
                hoverColor: SamanChatTokens.actionRowHoverBg,
                focusColor: SamanChatTokens.actionRowFocusBg,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 22.0,
                        color: SamanChatTokens.textWhite,
                      ),
                      SizedBox(width: 8.0),
                      Text(
                        'Mức độ suy luận',
                        style: TextStyle(
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
              subtitle: 'Nhanh và gọn',
              isActive: false,
              isLocked: true,
              badgeText: 'Sắp ra mắt',
              onTap: () => widget.onLockedThinkingLevelTapped('Low'),
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingMenuItem(
              title: 'Medium',
              subtitle: 'Cân bằng độ sâu',
              isActive: true,
              isLocked: false,
              onTap: widget.onSelectMedium,
              minTouchTarget: true,
            ),
            const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
            _buildThinkingMenuItem(
              title: 'High',
              subtitle: 'Phân tích kỹ hơn',
              isActive: false,
              isLocked: true,
              badgeText: 'Sắp ra mắt',
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
                  subtitle: 'Nhanh và gọn',
                  isActive: false,
                  isLocked: true,
                  badgeText: 'Sắp ra mắt',
                  onTap: () => widget.onLockedThinkingLevelTapped('Low'),
                  minTouchTarget: isMobile,
                ),
                const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
                _buildThinkingMenuItem(
                  title: 'Medium',
                  subtitle: 'Cân bằng độ sâu',
                  isActive: true,
                  isLocked: false,
                  onTap: widget.onSelectMedium,
                  minTouchTarget: isMobile,
                ),
                const Divider(height: 1.0, thickness: 1.0, color: SamanChatTokens.borderSubtle),
                _buildThinkingMenuItem(
                  title: 'High',
                  subtitle: 'Phân tích kỹ hơn',
                  isActive: false,
                  isLocked: true,
                  badgeText: 'Sắp ra mắt',
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
          'Mức độ suy luận. ${_isThinkingSubmenuOpen ? "Đang mở menu mức suy luận" : "Bấm để mở menu mức suy luận"}',
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
          autofocus: true,
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
                    const Text(
                      'Mức độ suy luận',
                      style: TextStyle(
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
          ? '$title: $subtitle. Đang dùng'
          : '$title: $subtitle. ${badgeText ?? "Đang khóa"} (giữ nguyên mức hiện tại)',
      selected: isActive,
      child: InkWell(
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
    return Semantics(
      button: true,
      label: isActive
          ? '$title: $subtitle. Đang dùng'
          : '$title: $subtitle. $badgeText (đang khóa, giữ nguyên chế độ hiện tại)',
      selected: isActive,
      child: InkWell(
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

