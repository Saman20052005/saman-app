import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../../config/app_translations.dart';
import '../../../domain/models/community_dm.dart';
import '../../providers/community_call_provider.dart';
import '../../tokens/saman_ig_tokens.dart';

/// Instagram-styled 1-on-1 Audio & Video Call screen for Saman Community.
///
/// Strictly uses `SamanIgTokens.dark` (or `SamanIgTokens.of(context)`) with
/// `'Manrope'` typography and zero green hues:
/// - Accept call button: `ig.primaryAction` (`#0095F6`)
/// - Reject / End call button: `ig.likeHeart` (`#FF3040`)
class CommunityCallScreen extends ConsumerStatefulWidget {
  static bool isPresented = false;

  const CommunityCallScreen({super.key});

  @override
  ConsumerState<CommunityCallScreen> createState() =>
      _CommunityCallScreenState();
}

class _CommunityCallScreenState extends ConsumerState<CommunityCallScreen> {
  Timer? _autoDismissTimer;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    CommunityCallScreen.isPresented = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(communityCallProvider);
      if (current.phase == CallLifecyclePhase.ended) {
        _scheduleEndedDismiss(current.endReason);
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    CommunityCallScreen.isPresented = false;
    super.dispose();
  }

  void _scheduleEndedDismiss(String? endReason) {
    if (_autoDismissTimer != null || _isClosing) return;
    final delay = endReason == 'handled_elsewhere'
        ? const Duration(milliseconds: 250)
        : const Duration(milliseconds: 1200);
    _autoDismissTimer = Timer(delay, () {
      if (!mounted) return;
      _closeEndedCallScreen();
    });
  }

  void _closeEndedCallScreen() {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    ref.read(communityCallProvider.notifier).dismissEndedState();
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
  }

  String _formatEndedReason(BuildContext context, CommunityCallState state) {
    if (state.errorMessage != null && state.errorMessage!.trim().isNotEmpty) {
      return state.errorMessage!;
    }
    switch (state.endReason) {
      case 'busy':
        return context.tr('community_call_busy');
      case 'rejected':
        return context.tr('community_call_rejected');
      case 'missed':
        return context.tr('community_call_missed');
      case 'no_answer':
        return context.tr('community_call_no_answer');
      case 'canceled':
        return context.tr('community_call_canceled');
      case 'handled_elsewhere':
        return context.tr('community_call_handled_elsewhere');
      case 'permission_denied':
        return context.tr('community_call_permission_denied');
      default:
        return context.tr('community_call_ended');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommunityCallState>(communityCallProvider, (previous, next) {
      if (next.phase == CallLifecyclePhase.ended &&
          previous?.phase != CallLifecyclePhase.ended) {
        _scheduleEndedDismiss(next.endReason);
      } else if (next.phase == CallLifecyclePhase.idle &&
          previous != null &&
          previous.phase != CallLifecyclePhase.idle) {
        _closeEndedCallScreen();
      }
    });

    final ig = SamanIgTokens.of(context);
    const darkIg = SamanIgTokens.dark;
    final callState = ref.watch(communityCallProvider);
    final notifier = ref.read(communityCallProvider.notifier);
    final peer = callState.peer ??
        const DmParticipant(
          id: '',
          name: 'Saman Athlete',
        );

    return Scaffold(
      backgroundColor: darkIg.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackgroundLayer(callState, darkIg),
          SafeArea(
            child: _buildPhaseContent(
              context: context,
              callState: callState,
              peer: peer,
              notifier: notifier,
              ig: ig,
              darkIg: darkIg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundLayer(
    CommunityCallState callState,
    SamanIgTokens darkIg,
  ) {
    if (callState.isVideo && callState.phase == CallLifecyclePhase.connected) {
      final remote = callState.remoteRenderer;
      if (remote is RTCVideoRenderer && callState.isRemoteVideoEnabled) {
        return RTCVideoView(
          remote,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
    }

    if (callState.isVideo &&
        (callState.phase == CallLifecyclePhase.outgoingRinging ||
            callState.phase == CallLifecyclePhase.connecting) &&
        !callState.isCameraOff) {
      final local = callState.localRenderer;
      if (local is RTCVideoRenderer) {
        return Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              local,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            ColoredBox(color: darkIg.scrim),
          ],
        );
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            darkIg.surface,
            darkIg.canvas,
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseContent({
    required BuildContext context,
    required CommunityCallState callState,
    required DmParticipant peer,
    required CommunityCallNotifier notifier,
    required SamanIgTokens ig,
    required SamanIgTokens darkIg,
  }) {
    switch (callState.phase) {
      case CallLifecyclePhase.incomingRinging:
        return _buildIncomingRingingLayout(
          context: context,
          callState: callState,
          peer: peer,
          notifier: notifier,
          darkIg: darkIg,
        );
      case CallLifecyclePhase.outgoingRinging:
      case CallLifecyclePhase.connecting:
        return _buildOutgoingOrConnectingLayout(
          context: context,
          callState: callState,
          peer: peer,
          notifier: notifier,
          darkIg: darkIg,
        );
      case CallLifecyclePhase.connected:
        return _buildConnectedLayout(
          context: context,
          callState: callState,
          peer: peer,
          notifier: notifier,
          darkIg: darkIg,
        );
      case CallLifecyclePhase.ended:
      case CallLifecyclePhase.idle:
        return _buildEndedLayout(
          context: context,
          callState: callState,
          peer: peer,
          darkIg: darkIg,
        );
    }
  }

  Widget _buildIncomingRingingLayout({
    required BuildContext context,
    required CommunityCallState callState,
    required DmParticipant peer,
    required CommunityCallNotifier notifier,
    required SamanIgTokens darkIg,
  }) {
    final incomingLabel = callState.isVideo
        ? context.tr('community_call_incoming_video')
        : context.tr('community_call_incoming_audio');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          const SizedBox(height: 36),
          _CallAvatarRing(
            peer: peer,
            size: 112,
            darkIg: darkIg,
            showPulseRing: true,
          ),
          const SizedBox(height: 22),
          _PeerNameBadgeRow(peer: peer, darkIg: darkIg, fontSize: 22),
          const SizedBox(height: 8),
          Text(
            incomingLabel,
            textAlign: TextAlign.center,
            style: darkIg.body(
              fontSize: 15,
              color: darkIg.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LargeCallActionButton(
                  buttonKey: const Key('call-reject-button'),
                  icon: Icons.call_end_rounded,
                  label: context.tr('community_call_decline'),
                  backgroundColor: darkIg.likeHeart,
                  iconColor: darkIg.onPrimaryAction,
                  darkIg: darkIg,
                  onTap: notifier.rejectCall,
                ),
                _LargeCallActionButton(
                  buttonKey: const Key('call-accept-button'),
                  icon: callState.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  label: context.tr('community_call_accept'),
                  backgroundColor: darkIg.primaryAction,
                  iconColor: darkIg.onPrimaryAction,
                  darkIg: darkIg,
                  onTap: notifier.acceptCall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutgoingOrConnectingLayout({
    required BuildContext context,
    required CommunityCallState callState,
    required DmParticipant peer,
    required CommunityCallNotifier notifier,
    required SamanIgTokens darkIg,
  }) {
    final statusText = callState.phase == CallLifecyclePhase.outgoingRinging
        ? context.tr('community_call_ringing')
        : context.tr('community_call_connecting');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        children: [
          const SizedBox(height: 36),
          _CallAvatarRing(
            peer: peer,
            size: 104,
            darkIg: darkIg,
            showPulseRing: true,
          ),
          const SizedBox(height: 20),
          _PeerNameBadgeRow(peer: peer, darkIg: darkIg, fontSize: 22),
          const SizedBox(height: 8),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: darkIg.body(
              fontSize: 15,
              color: darkIg.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          _buildBottomControlPill(
            context: context,
            callState: callState,
            notifier: notifier,
            darkIg: darkIg,
            onEndTap: () {
              if (callState.phase == CallLifecyclePhase.outgoingRinging) {
                notifier.cancelCall();
              } else {
                notifier.hangup();
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildConnectedLayout({
    required BuildContext context,
    required CommunityCallState callState,
    required DmParticipant peer,
    required CommunityCallNotifier notifier,
    required SamanIgTokens darkIg,
  }) {
    final durationLabel = formatDmCallDuration(callState.durationSec);
    final showRemoteVideo = callState.isVideo &&
        callState.isRemoteVideoEnabled &&
        callState.remoteRenderer is RTCVideoRenderer;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!showRemoteVideo)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CallAvatarRing(
                  peer: peer,
                  size: 112,
                  darkIg: darkIg,
                  showPulseRing: false,
                ),
                const SizedBox(height: 20),
                _PeerNameBadgeRow(peer: peer, darkIg: darkIg, fontSize: 22),
                const SizedBox(height: 8),
                Text(
                  durationLabel,
                  key: const Key('call-duration-text'),
                  style: darkIg
                      .body(
                        fontSize: 16,
                        color: darkIg.textSecondary,
                        fontWeight: FontWeight.w600,
                      )
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
        // Top Header Bar
        Positioned(
          top: 12,
          left: 16,
          right: callState.isVideo ? 136 : 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: darkIg.surface.withOpacity(0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: darkIg.onPrimaryAction.withOpacity(0.12),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  callState.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  size: 18,
                  color: darkIg.primaryAction,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    peer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: darkIg.username(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: darkIg.textPrimary,
                    ),
                  ),
                ),
                if (peer.isVerified) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.verified_rounded,
                    size: 14,
                    color: darkIg.primaryAction,
                  ),
                ],
                const SizedBox(width: 10),
                Text(
                  durationLabel,
                  style: darkIg
                      .caption(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: darkIg.textSecondary,
                      )
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
        ),
        // Local PiP Camera View (Top-Right) for Video Calls
        if (callState.isVideo)
          Positioned(
            top: 12,
            right: 16,
            child: _buildLocalPipCard(callState, darkIg),
          ),
        // Bottom Floating Pill Control Bar
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: _buildBottomControlPill(
            context: context,
            callState: callState,
            notifier: notifier,
            darkIg: darkIg,
            onEndTap: notifier.hangup,
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPipCard(
    CommunityCallState callState,
    SamanIgTokens darkIg,
  ) {
    final local = callState.localRenderer;
    final canRenderLocal =
        !callState.isCameraOff && local is RTCVideoRenderer;

    return Container(
      key: const Key('call-local-pip'),
      width: 108,
      height: 154,
      decoration: BoxDecoration(
        color: darkIg.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: darkIg.onPrimaryAction.withOpacity(0.75),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: canRenderLocal
          ? RTCVideoView(
              local,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Center(
              child: Icon(
                callState.isCameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.person_rounded,
                size: 28,
                color: darkIg.textSecondary,
              ),
            ),
    );
  }

  Widget _buildBottomControlPill({
    required BuildContext context,
    required CommunityCallState callState,
    required CommunityCallNotifier notifier,
    required SamanIgTokens darkIg,
    required VoidCallback onEndTap,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: darkIg.surfaceElevated.withOpacity(0.92),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: darkIg.onPrimaryAction.withOpacity(0.12),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ControlBarIconButton(
              buttonKey: const Key('call-toggle-speaker-button'),
              icon: callState.isSpeakerOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded,
              tooltip: context.tr('community_call_speaker'),
              isActive: callState.isSpeakerOn,
              darkIg: darkIg,
              onTap: notifier.toggleSpeaker,
            ),
            const SizedBox(width: 12),
            _ControlBarIconButton(
              buttonKey: const Key('call-toggle-mic-button'),
              icon: callState.isMuted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              tooltip: context.tr('community_call_mic'),
              isActive: !callState.isMuted,
              isWarningState: callState.isMuted,
              darkIg: darkIg,
              onTap: notifier.toggleMute,
            ),
            if (callState.isVideo) ...[
              const SizedBox(width: 12),
              _ControlBarIconButton(
                buttonKey: const Key('call-toggle-camera-button'),
                icon: callState.isCameraOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                tooltip: context.tr('community_call_camera'),
                isActive: !callState.isCameraOff,
                isWarningState: callState.isCameraOff,
                darkIg: darkIg,
                onTap: notifier.toggleCamera,
              ),
              const SizedBox(width: 12),
              _ControlBarIconButton(
                buttonKey: const Key('call-switch-camera-button'),
                icon: Icons.cameraswitch_rounded,
                tooltip: context.tr('community_call_flip'),
                isActive: false,
                darkIg: darkIg,
                onTap: notifier.switchCamera,
              ),
            ],
            const SizedBox(width: 14),
            SizedBox(
              width: 54,
              height: 54,
              child: Material(
                color: darkIg.likeHeart,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('call-hangup-button'),
                  onTap: onEndTap,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      Icons.call_end_rounded,
                      size: 24,
                      color: darkIg.onPrimaryAction,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndedLayout({
    required BuildContext context,
    required CommunityCallState callState,
    required DmParticipant peer,
    required SamanIgTokens darkIg,
  }) {
    final reasonText = _formatEndedReason(context, callState);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _CallAvatarRing(
            peer: peer,
            size: 96,
            darkIg: darkIg,
            showPulseRing: false,
          ),
          const SizedBox(height: 18),
          _PeerNameBadgeRow(peer: peer, darkIg: darkIg, fontSize: 20),
          const SizedBox(height: 10),
          Text(
            reasonText,
            key: const Key('call-ended-reason-text'),
            textAlign: TextAlign.center,
            style: darkIg.body(
              fontSize: 15,
              color: darkIg.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (callState.durationSec > 0) ...[
            const SizedBox(height: 6),
            Text(
              formatDmCallDuration(callState.durationSec),
              style: darkIg
                  .caption(
                    fontSize: 13,
                    color: darkIg.textMuted,
                    fontWeight: FontWeight.w600,
                  )
                  .copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
          const Spacer(),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              key: const Key('call-close-button'),
              onPressed: _closeEndedCallScreen,
              style: darkIg.secondaryButtonStyle(
                minHeight: 48,
                borderRadius: 24,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  context.tr('community_call_close'),
                  style: darkIg.buttonLabel(
                    fontSize: 14,
                    color: darkIg.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CallAvatarRing extends StatelessWidget {
  final DmParticipant peer;
  final double size;
  final SamanIgTokens darkIg;
  final bool showPulseRing;

  const _CallAvatarRing({
    required this.peer,
    required this.size,
    required this.darkIg,
    required this.showPulseRing,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        peer.name.trim().isNotEmpty ? peer.name.trim()[0].toUpperCase() : 'S';

    return Container(
      width: size + (showPulseRing ? 24 : 0),
      height: size + (showPulseRing ? 24 : 0),
      alignment: Alignment.center,
      decoration: showPulseRing
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: darkIg.primaryAction.withOpacity(0.28),
                width: 2,
              ),
            )
          : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: darkIg.surfaceElevated,
          border: Border.all(
            color: darkIg.border,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: peer.avatarUrl != null && peer.avatarUrl!.isNotEmpty
            ? Image.network(
                peer.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: darkIg.displayTitle(
                      fontSize: size * 0.38,
                      color: darkIg.primaryAction,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: darkIg.displayTitle(
                    fontSize: size * 0.38,
                    color: darkIg.primaryAction,
                  ),
                ),
              ),
      ),
    );
  }
}

class _PeerNameBadgeRow extends StatelessWidget {
  final DmParticipant peer;
  final SamanIgTokens darkIg;
  final double fontSize;

  const _PeerNameBadgeRow({
    required this.peer,
    required this.darkIg,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            peer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: darkIg.displayTitle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: darkIg.textPrimary,
            ),
          ),
        ),
        if (peer.isVerified) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.verified_rounded,
            size: 18,
            color: darkIg.primaryAction,
          ),
        ],
      ],
    );
  }
}

class _LargeCallActionButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color iconColor;
  final SamanIgTokens darkIg;
  final VoidCallback onTap;

  const _LargeCallActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.iconColor,
    required this.darkIg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 68,
          height: 68,
          child: Material(
            color: backgroundColor,
            shape: const CircleBorder(),
            child: InkWell(
              key: buttonKey,
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  icon,
                  size: 30,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: darkIg.caption(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: darkIg.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ControlBarIconButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final bool isWarningState;
  final SamanIgTokens darkIg;
  final VoidCallback onTap;

  const _ControlBarIconButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    this.isWarningState = false,
    required this.darkIg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isWarningState
        ? darkIg.onPrimaryAction
        : (isActive
            ? darkIg.onPrimaryAction.withOpacity(0.18)
            : darkIg.surface.withOpacity(0.55));
    final fgColor = isWarningState ? darkIg.canvas : darkIg.textPrimary;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 50,
        height: 50,
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          child: InkWell(
            key: buttonKey,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
