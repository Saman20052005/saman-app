import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/datasources/community_dm_ws_service.dart';
import '../../domain/models/community_dm.dart';

enum CallLifecyclePhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  connected,
  ended,
}

class RtcSdp {
  final String sdp;
  final String type; // 'offer' | 'answer'

  const RtcSdp({
    required this.sdp,
    required this.type,
  });
}

class RtcIceCandidateData {
  final String candidate;
  final String? sdpMid;
  final int? sdpMlineIndex;

  const RtcIceCandidateData({
    required this.candidate,
    this.sdpMid,
    this.sdpMlineIndex,
  });
}

/// Abstract WebRTC bridge so unit and widget tests can verify the full
/// 1-1 call state machine and ICE candidate queue without native plugins.
abstract class CommunityRtcBridge {
  Object? get localRenderer;
  Object? get remoteRenderer;

  Future<void> initialize({
    required bool isVideo,
    required void Function(RtcIceCandidateData candidate) onIceCandidate,
    required void Function() onConnected,
    required void Function() onDisconnected,
    void Function(bool hasRemoteVideo)? onRemoteVideoStateChanged,
  });

  Future<RtcSdp> createOffer({required bool isVideo});

  Future<RtcSdp> createAnswer({required bool isVideo});

  Future<void> setRemoteDescription(RtcSdp description);

  Future<void> addIceCandidate(RtcIceCandidateData candidate);

  Future<void> setMicrophoneMuted(bool muted);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> setSpeakerphoneOn(bool enabled);

  Future<void> switchCamera();

  Future<void> dispose();
}

typedef RtcPeerBridge = CommunityRtcBridge;
typedef CommunityRtcBridgeFactory = CommunityRtcBridge Function();
typedef CallPermissionChecker = Future<bool> Function({required bool isVideo});

/// Production implementation of [CommunityRtcBridge] backed by `flutter_webrtc`.
class FlutterWebRtcBridge implements CommunityRtcBridge {
  static const Map<String, dynamic> defaultRtcConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  @override
  Object? get localRenderer => _localRenderer;

  @override
  Object? get remoteRenderer => _remoteRenderer;

  @override
  Future<void> initialize({
    required bool isVideo,
    required void Function(RtcIceCandidateData candidate) onIceCandidate,
    required void Function() onConnected,
    required void Function() onDisconnected,
    void Function(bool hasRemoteVideo)? onRemoteVideoStateChanged,
  }) async {
    await dispose();

    final localR = RTCVideoRenderer();
    final remoteR = RTCVideoRenderer();
    await localR.initialize();
    await remoteR.initialize();
    _localRenderer = localR;
    _remoteRenderer = remoteR;

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = stream;
    localR.srcObject = stream;

    final pc = await createPeerConnection(defaultRtcConfiguration);
    _peerConnection = pc;

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final raw = candidate.candidate;
      if (raw == null || raw.isEmpty) return;
      onIceCandidate(
        RtcIceCandidateData(
          candidate: raw,
          sdpMid: candidate.sdpMid,
          sdpMlineIndex: candidate.sdpMLineIndex,
        ),
      );
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        final remote = event.streams.first;
        _remoteStream = remote;
        _remoteRenderer?.srcObject = remote;
        final hasVideo = remote.getVideoTracks().any((t) => t.enabled);
        onRemoteVideoStateChanged?.call(hasVideo);
      }
    };

    pc.onAddStream = (MediaStream stream) {
      _remoteStream = stream;
      _remoteRenderer?.srcObject = stream;
      final hasVideo = stream.getVideoTracks().any((t) => t.enabled);
      onRemoteVideoStateChanged?.call(hasVideo);
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onDisconnected();
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        onDisconnected();
      }
    };
  }

  @override
  Future<RtcSdp> createOffer({required bool isVideo}) async {
    final pc = _peerConnection;
    if (pc == null) {
      throw StateError('PeerConnection is not initialized');
    }
    final desc = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    });
    await pc.setLocalDescription(desc);
    return RtcSdp(
      sdp: desc.sdp ?? '',
      type: desc.type ?? 'offer',
    );
  }

  @override
  Future<RtcSdp> createAnswer({required bool isVideo}) async {
    final pc = _peerConnection;
    if (pc == null) {
      throw StateError('PeerConnection is not initialized');
    }
    final desc = await pc.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    });
    await pc.setLocalDescription(desc);
    return RtcSdp(
      sdp: desc.sdp ?? '',
      type: desc.type ?? 'answer',
    );
  }

  @override
  Future<void> setRemoteDescription(RtcSdp description) async {
    final pc = _peerConnection;
    if (pc == null) {
      throw StateError('PeerConnection is not initialized');
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> addIceCandidate(RtcIceCandidateData candidate) async {
    final pc = _peerConnection;
    if (pc == null) return;
    await pc.addCandidate(
      RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMlineIndex,
      ),
    );
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (_) {}
  }

  @override
  Future<void> switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    try {
      await Helper.switchCamera(videoTracks.first);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    final local = _localStream;
    _localStream = null;
    if (local != null) {
      for (final track in local.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await local.dispose();
      } catch (_) {}
    }

    final remote = _remoteStream;
    _remoteStream = null;
    if (remote != null) {
      try {
        await remote.dispose();
      } catch (_) {}
    }

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    final localR = _localRenderer;
    _localRenderer = null;
    if (localR != null) {
      try {
        localR.srcObject = null;
        await localR.dispose();
      } catch (_) {}
    }

    final remoteR = _remoteRenderer;
    _remoteRenderer = null;
    if (remoteR != null) {
      try {
        remoteR.srcObject = null;
        await remoteR.dispose();
      } catch (_) {}
    }
  }
}

class CommunityCallState {
  final CallLifecyclePhase phase;
  final String? callId;
  final String? conversationId;
  final String callType; // 'audio' | 'video'
  final bool isIncoming;
  final DmParticipant? peer;
  final int durationSec;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final bool isRemoteVideoEnabled;
  final String? endReason;
  final String? errorMessage;
  final Object? localRenderer;
  final Object? remoteRenderer;

  const CommunityCallState({
    this.phase = CallLifecyclePhase.idle,
    this.callId,
    this.conversationId,
    this.callType = 'audio',
    this.isIncoming = false,
    this.peer,
    this.durationSec = 0,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isSpeakerOn = false,
    this.isRemoteVideoEnabled = true,
    this.endReason,
    this.errorMessage,
    this.localRenderer,
    this.remoteRenderer,
  });

  bool get isVideo => callType.toLowerCase() == 'video';

  bool get isActive =>
      phase != CallLifecyclePhase.idle && phase != CallLifecyclePhase.ended;

  CommunityCallState copyWith({
    CallLifecyclePhase? phase,
    String? callId,
    bool clearCallId = false,
    String? conversationId,
    bool clearConversationId = false,
    String? callType,
    bool? isIncoming,
    DmParticipant? peer,
    bool clearPeer = false,
    int? durationSec,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeakerOn,
    bool? isRemoteVideoEnabled,
    String? endReason,
    bool clearEndReason = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    Object? localRenderer,
    bool clearLocalRenderer = false,
    Object? remoteRenderer,
    bool clearRemoteRenderer = false,
  }) {
    return CommunityCallState(
      phase: phase ?? this.phase,
      callId: clearCallId ? null : (callId ?? this.callId),
      conversationId: clearConversationId
          ? null
          : (conversationId ?? this.conversationId),
      callType: callType ?? this.callType,
      isIncoming: isIncoming ?? this.isIncoming,
      peer: clearPeer ? null : (peer ?? this.peer),
      durationSec: durationSec ?? this.durationSec,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      endReason: clearEndReason ? null : (endReason ?? this.endReason),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      localRenderer:
          clearLocalRenderer ? null : (localRenderer ?? this.localRenderer),
      remoteRenderer:
          clearRemoteRenderer ? null : (remoteRenderer ?? this.remoteRenderer),
    );
  }
}

Future<bool> defaultCallPermissionChecker({required bool isVideo}) async {
  try {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }
    if (isVideo) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

class CommunityCallNotifier extends StateNotifier<CommunityCallState> {
  final CommunityDmWsService _wsService;
  final CommunityRtcBridgeFactory _rtcBridgeFactory;
  final CallPermissionChecker _permissionChecker;
  final Duration ringingTimeout;

  CommunityRtcBridge? _activeBridge;
  StreamSubscription<DmWsEvent>? _wsSub;
  Timer? _ringingTimeoutTimer;
  Timer? _durationTimer;

  final List<RtcIceCandidateData> _pendingRemoteIce = [];
  bool _hasRemoteDescription = false;
  bool _isSettingRemoteDescription = false;
  RtcSdp? _pendingRemoteOffer;

  CommunityCallNotifier({
    required CommunityDmWsService wsService,
    CommunityRtcBridgeFactory? rtcBridgeFactory,
    CallPermissionChecker? permissionChecker,
    this.ringingTimeout = const Duration(seconds: 45),
  })  : _wsService = wsService,
        _rtcBridgeFactory = rtcBridgeFactory ?? FlutterWebRtcBridge.new,
        _permissionChecker =
            permissionChecker ?? defaultCallPermissionChecker,
        super(const CommunityCallState()) {
    _wsSub = _wsService.events.listen(_handleWsEvent);
  }

  List<RtcIceCandidateData> get pendingRemoteIce =>
      List.unmodifiable(_pendingRemoteIce);

  bool get hasRemoteDescription => _hasRemoteDescription;

  String _generateCallId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  Future<bool> startCall({
    required String conversationId,
    required DmParticipant peer,
    String callType = 'audio',
    String? callId,
  }) async {
    if (state.isActive) {
      return false;
    }

    final normalizedType =
        callType.trim().toLowerCase() == 'video' ? 'video' : 'audio';
    final isVideo = normalizedType == 'video';
    final resolvedCallId =
        (callId != null && callId.trim().isNotEmpty) ? callId.trim() : _generateCallId();

    await _cleanupSessionResources();

    final granted = await _permissionChecker(isVideo: isVideo);
    if (!mounted) return false;
    if (!granted) {
      state = CommunityCallState(
        phase: CallLifecyclePhase.ended,
        callId: resolvedCallId,
        conversationId: conversationId,
        callType: normalizedType,
        isIncoming: false,
        peer: peer,
        endReason: 'permission_denied',
        errorMessage: isVideo
            ? 'Vui lòng cấp quyền Micro và Camera để gọi video.'
            : 'Vui lòng cấp quyền Micro để thực hiện cuộc gọi.',
      );
      return false;
    }

    final bridge = _rtcBridgeFactory();
    _activeBridge = bridge;

    try {
      await bridge.initialize(
        isVideo: isVideo,
        onIceCandidate: (candidate) {
          final currentCallId = state.callId;
          if (!mounted || currentCallId == null) return;
          _wsService.sendWebRtcIce(
            callId: currentCallId,
            candidate: candidate.candidate,
            sdpMid: candidate.sdpMid,
            sdpMlineIndex: candidate.sdpMlineIndex,
          );
        },
        onConnected: _onRtcConnected,
        onDisconnected: _onRtcDisconnected,
        onRemoteVideoStateChanged: (hasVideo) {
          if (!mounted) return;
          state = state.copyWith(isRemoteVideoEnabled: hasVideo);
        },
      );
      await bridge.setSpeakerphoneOn(isVideo);
    } catch (e) {
      await _cleanupSessionResources();
      if (!mounted) return false;
      state = CommunityCallState(
        phase: CallLifecyclePhase.ended,
        callId: resolvedCallId,
        conversationId: conversationId,
        callType: normalizedType,
        isIncoming: false,
        peer: peer,
        endReason: 'media_error',
        errorMessage: 'Không thể khởi tạo thiết bị âm thanh/hình ảnh.',
      );
      return false;
    }

    if (!mounted) return false;

    state = CommunityCallState(
      phase: CallLifecyclePhase.outgoingRinging,
      callId: resolvedCallId,
      conversationId: conversationId,
      callType: normalizedType,
      isIncoming: false,
      peer: peer,
      durationSec: 0,
      isMuted: false,
      isCameraOff: !isVideo,
      isSpeakerOn: isVideo,
      isRemoteVideoEnabled: isVideo,
      localRenderer: bridge.localRenderer,
      remoteRenderer: bridge.remoteRenderer,
    );

    unawaited(_wsService.connect());
    _wsService.sendCallInvite(
      callId: resolvedCallId,
      conversationId: conversationId,
      callType: normalizedType,
    );

    _startRingingTimeout();
    return true;
  }

  Future<bool> acceptCall() async {
    if (state.phase != CallLifecyclePhase.incomingRinging) {
      return false;
    }
    final activeCallId = state.callId;
    if (activeCallId == null || activeCallId.isEmpty) {
      return false;
    }

    final isVideo = state.isVideo;
    final granted = await _permissionChecker(isVideo: isVideo);
    if (!mounted) return false;
    if (!granted) {
      _wsService.sendCallReject(callId: activeCallId);
      await _endCallInternal(
        endReason: 'permission_denied',
        errorMessage: isVideo
            ? 'Vui lòng cấp quyền Micro và Camera để nhận cuộc gọi video.'
            : 'Vui lòng cấp quyền Micro để nhận cuộc gọi.',
      );
      return false;
    }

    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;

    final bridge = _rtcBridgeFactory();
    _activeBridge = bridge;

    try {
      await bridge.initialize(
        isVideo: isVideo,
        onIceCandidate: (candidate) {
          final currentCallId = state.callId;
          if (!mounted || currentCallId == null) return;
          _wsService.sendWebRtcIce(
            callId: currentCallId,
            candidate: candidate.candidate,
            sdpMid: candidate.sdpMid,
            sdpMlineIndex: candidate.sdpMlineIndex,
          );
        },
        onConnected: _onRtcConnected,
        onDisconnected: _onRtcDisconnected,
        onRemoteVideoStateChanged: (hasVideo) {
          if (!mounted) return;
          state = state.copyWith(isRemoteVideoEnabled: hasVideo);
        },
      );
      await bridge.setSpeakerphoneOn(isVideo);
    } catch (_) {
      _wsService.sendCallReject(callId: activeCallId);
      await _endCallInternal(
        endReason: 'media_error',
        errorMessage: 'Không thể khởi tạo thiết bị âm thanh/hình ảnh.',
      );
      return false;
    }

    if (!mounted) return false;

    state = state.copyWith(
      phase: CallLifecyclePhase.connecting,
      localRenderer: bridge.localRenderer,
      remoteRenderer: bridge.remoteRenderer,
      clearEndReason: true,
      clearErrorMessage: true,
    );

    _wsService.sendCallAccept(callId: activeCallId);

    final pendingOffer = _pendingRemoteOffer;
    _pendingRemoteOffer = null;
    if (pendingOffer != null) {
      await _applyRemoteOfferAndSendAnswer(activeCallId, pendingOffer);
    }
    return true;
  }

  Future<void> rejectCall() async {
    if (state.phase != CallLifecyclePhase.incomingRinging) return;
    final activeCallId = state.callId;
    if (activeCallId != null && activeCallId.isNotEmpty) {
      _wsService.sendCallReject(callId: activeCallId);
    }
    await _endCallInternal(endReason: 'rejected');
  }

  Future<void> cancelCall({String endReason = 'canceled'}) async {
    if (state.phase != CallLifecyclePhase.outgoingRinging &&
        state.phase != CallLifecyclePhase.connecting) {
      return;
    }
    final activeCallId = state.callId;
    if (activeCallId != null && activeCallId.isNotEmpty) {
      if (state.phase == CallLifecyclePhase.outgoingRinging) {
        _wsService.sendCallCancel(callId: activeCallId);
      } else {
        _wsService.sendCallHangup(callId: activeCallId);
      }
    }
    await _endCallInternal(endReason: endReason);
  }

  Future<void> hangup() async {
    if (!state.isActive) return;
    if (state.phase == CallLifecyclePhase.outgoingRinging) {
      await cancelCall();
      return;
    }
    if (state.phase == CallLifecyclePhase.incomingRinging) {
      await rejectCall();
      return;
    }
    final activeCallId = state.callId;
    if (activeCallId != null && activeCallId.isNotEmpty) {
      _wsService.sendCallHangup(callId: activeCallId);
    }
    await _endCallInternal(endReason: 'hangup');
  }

  Future<void> toggleMute() async {
    if (!state.isActive) return;
    final nextMuted = !state.isMuted;
    state = state.copyWith(isMuted: nextMuted);
    await _activeBridge?.setMicrophoneMuted(nextMuted);
  }

  Future<void> toggleCamera() async {
    if (!state.isActive || !state.isVideo) return;
    final nextCameraOff = !state.isCameraOff;
    state = state.copyWith(isCameraOff: nextCameraOff);
    await _activeBridge?.setCameraEnabled(!nextCameraOff);
  }

  Future<void> toggleSpeaker() async {
    if (!state.isActive) return;
    final nextSpeaker = !state.isSpeakerOn;
    state = state.copyWith(isSpeakerOn: nextSpeaker);
    await _activeBridge?.setSpeakerphoneOn(nextSpeaker);
  }

  Future<void> switchCamera() async {
    if (!state.isActive || !state.isVideo || state.isCameraOff) return;
    await _activeBridge?.switchCamera();
  }

  void dismissEndedState() {
    if (!mounted) return;
    if (state.phase == CallLifecyclePhase.ended ||
        state.phase == CallLifecyclePhase.idle) {
      state = const CommunityCallState();
    }
  }

  void _startRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = Timer(ringingTimeout, () {
      if (!mounted) return;
      if (state.phase == CallLifecyclePhase.outgoingRinging) {
        unawaited(cancelCall(endReason: 'no_answer'));
      } else if (state.phase == CallLifecyclePhase.incomingRinging) {
        unawaited(_endCallInternal(endReason: 'missed'));
      }
    });
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || state.phase != CallLifecyclePhase.connected) return;
      state = state.copyWith(durationSec: state.durationSec + 1);
    });
  }

  void _onRtcConnected() {
    if (!mounted) return;
    if (state.phase == CallLifecyclePhase.connecting ||
        state.phase == CallLifecyclePhase.connected) {
      state = state.copyWith(phase: CallLifecyclePhase.connected);
      _startDurationTimer();
    }
  }

  void _onRtcDisconnected() {
    if (!mounted) return;
    if (state.phase == CallLifecyclePhase.connected) {
      unawaited(hangup());
    }
  }

  void _handleWsEvent(DmWsEvent event) {
    if (!mounted) return;

    switch (event.event) {
      case 'call.invite':
        _handleIncomingInvite(event);
        break;
      case 'call.accept':
        _handleRemoteAccept(event);
        break;
      case 'call.reject':
        if (_matchesActiveCall(event.callId)) {
          unawaited(_endCallInternal(endReason: 'rejected'));
        }
        break;
      case 'call.cancel':
        if (_matchesActiveCall(event.callId)) {
          unawaited(_endCallInternal(endReason: 'canceled'));
        }
        break;
      case 'call.busy':
        if (_matchesActiveCall(event.callId)) {
          unawaited(_endCallInternal(endReason: 'busy'));
        }
        break;
      case 'call.hangup':
        if (_matchesActiveCall(event.callId)) {
          if (event.durationSec != null) {
            state = state.copyWith(durationSec: event.durationSec);
          }
          unawaited(_endCallInternal(endReason: 'hangup'));
        }
        break;
      case 'call.handled_elsewhere':
        if (_matchesActiveCall(event.callId) &&
            state.phase == CallLifecyclePhase.incomingRinging) {
          unawaited(_endCallInternal(endReason: 'handled_elsewhere'));
        }
        break;
      case 'call.error':
        if (_matchesActiveCall(event.callId)) {
          unawaited(
            _endCallInternal(
              endReason: event.code ?? 'error',
              errorMessage: event.detail ?? 'Lỗi kết nối cuộc gọi.',
            ),
          );
        }
        break;
      case 'webrtc.offer':
        if (_matchesActiveCall(event.callId) && event.sdp != null) {
          unawaited(
            _handleRemoteOffer(
              event.callId!,
              RtcSdp(sdp: event.sdp!, type: event.sdpType ?? 'offer'),
            ),
          );
        }
        break;
      case 'webrtc.answer':
        if (_matchesActiveCall(event.callId) && event.sdp != null) {
          unawaited(
            _handleRemoteAnswer(
              RtcSdp(sdp: event.sdp!, type: event.sdpType ?? 'answer'),
            ),
          );
        }
        break;
      case 'webrtc.ice':
        if (_matchesActiveCall(event.callId) &&
            event.candidate != null &&
            event.candidate!.isNotEmpty) {
          unawaited(
            _handleRemoteIce(
              RtcIceCandidateData(
                candidate: event.candidate!,
                sdpMid: event.sdpMid,
                sdpMlineIndex: event.sdpMlineIndex,
              ),
            ),
          );
        }
        break;
    }
  }

  bool _matchesActiveCall(String? eventCallId) {
    if (!state.isActive) return false;
    if (eventCallId == null || eventCallId.isEmpty) return false;
    return state.callId == eventCallId;
  }

  void _handleIncomingInvite(DmWsEvent event) {
    final incomingCallId = event.callId;
    if (incomingCallId == null || incomingCallId.isEmpty) return;

    // If already in an active call, automatically respond with call.busy
    // without disrupting the ongoing call.
    if (state.isActive) {
      if (incomingCallId != state.callId) {
        _wsService.sendCallBusy(callId: incomingCallId);
      }
      return;
    }

    _pendingRemoteIce.clear();
    _hasRemoteDescription = false;
    _isSettingRemoteDescription = false;
    _pendingRemoteOffer = null;

    final normalizedType =
        (event.callType ?? 'audio').trim().toLowerCase() == 'video'
            ? 'video'
            : 'audio';
    final isVideo = normalizedType == 'video';

    state = CommunityCallState(
      phase: CallLifecyclePhase.incomingRinging,
      callId: incomingCallId,
      conversationId: event.conversationId,
      callType: normalizedType,
      isIncoming: true,
      peer: event.caller ??
          const DmParticipant(
            id: '',
            name: 'Saman Athlete',
          ),
      durationSec: 0,
      isMuted: false,
      isCameraOff: !isVideo,
      isSpeakerOn: isVideo,
      isRemoteVideoEnabled: isVideo,
    );

    _startRingingTimeout();
  }

  Future<void> _handleRemoteAccept(DmWsEvent event) async {
    if (!_matchesActiveCall(event.callId)) return;
    if (state.phase != CallLifecyclePhase.outgoingRinging) return;

    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;

    state = state.copyWith(phase: CallLifecyclePhase.connecting);

    final bridge = _activeBridge;
    final activeCallId = state.callId;
    if (bridge == null || activeCallId == null) return;

    try {
      final offer = await bridge.createOffer(isVideo: state.isVideo);
      if (!mounted || state.callId != activeCallId) return;
      _wsService.sendWebRtcOffer(
        callId: activeCallId,
        sdp: offer.sdp,
        sdpType: offer.type,
      );
    } catch (_) {
      await _endCallInternal(
        endReason: 'webrtc_error',
        errorMessage: 'Không thể khởi tạo kết nối WebRTC.',
      );
    }
  }

  Future<void> _handleRemoteOffer(String callId, RtcSdp offer) async {
    final bridge = _activeBridge;
    if (bridge == null || state.phase == CallLifecyclePhase.incomingRinging) {
      _pendingRemoteOffer = offer;
      return;
    }
    await _applyRemoteOfferAndSendAnswer(callId, offer);
  }

  Future<void> _applyRemoteOfferAndSendAnswer(
    String callId,
    RtcSdp offer,
  ) async {
    final bridge = _activeBridge;
    if (bridge == null) return;

    try {
      _isSettingRemoteDescription = true;
      await bridge.setRemoteDescription(offer);
      _hasRemoteDescription = true;
      _isSettingRemoteDescription = false;

      await _flushPendingRemoteIce();

      final answer = await bridge.createAnswer(isVideo: state.isVideo);
      if (!mounted || state.callId != callId) return;

      _wsService.sendWebRtcAnswer(
        callId: callId,
        sdp: answer.sdp,
        sdpType: answer.type,
      );

      if (state.phase == CallLifecyclePhase.connecting) {
        state = state.copyWith(phase: CallLifecyclePhase.connected);
        _startDurationTimer();
      }
    } catch (_) {
      _isSettingRemoteDescription = false;
      await _endCallInternal(
        endReason: 'webrtc_error',
        errorMessage: 'Không thể thiết lập kết nối cuộc gọi.',
      );
    }
  }

  Future<void> _handleRemoteAnswer(RtcSdp answer) async {
    final bridge = _activeBridge;
    if (bridge == null) return;

    try {
      _isSettingRemoteDescription = true;
      await bridge.setRemoteDescription(answer);
      _hasRemoteDescription = true;
      _isSettingRemoteDescription = false;

      await _flushPendingRemoteIce();

      if (!mounted) return;
      if (state.phase == CallLifecyclePhase.connecting ||
          state.phase == CallLifecyclePhase.outgoingRinging) {
        state = state.copyWith(phase: CallLifecyclePhase.connected);
        _startDurationTimer();
      }
    } catch (_) {
      _isSettingRemoteDescription = false;
      await _endCallInternal(
        endReason: 'webrtc_error',
        errorMessage: 'Không thể hoàn tất kết nối cuộc gọi.',
      );
    }
  }

  Future<void> _handleRemoteIce(RtcIceCandidateData candidate) async {
    final bridge = _activeBridge;
    if (bridge == null ||
        !_hasRemoteDescription ||
        _isSettingRemoteDescription) {
      _pendingRemoteIce.add(candidate);
      return;
    }
    try {
      await bridge.addIceCandidate(candidate);
    } catch (_) {}
  }

  Future<void> _flushPendingRemoteIce() async {
    final bridge = _activeBridge;
    if (bridge == null || !_hasRemoteDescription) return;
    if (_pendingRemoteIce.isEmpty) return;

    final queued = List<RtcIceCandidateData>.from(_pendingRemoteIce);
    _pendingRemoteIce.clear();
    for (final candidate in queued) {
      try {
        await bridge.addIceCandidate(candidate);
      } catch (_) {}
    }
  }

  Future<void> _endCallInternal({
    required String endReason,
    String? errorMessage,
  }) async {
    await _cleanupSessionResources();
    if (!mounted) return;
    state = state.copyWith(
      phase: CallLifecyclePhase.ended,
      endReason: endReason,
      errorMessage: errorMessage,
      clearLocalRenderer: true,
      clearRemoteRenderer: true,
    );
  }

  Future<void> _cleanupSessionResources() async {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _pendingRemoteIce.clear();
    _hasRemoteDescription = false;
    _isSettingRemoteDescription = false;
    _pendingRemoteOffer = null;

    final bridge = _activeBridge;
    _activeBridge = null;
    if (bridge != null) {
      try {
        await bridge.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsSub = null;
    unawaited(_cleanupSessionResources());
    super.dispose();
  }
}

typedef CommunityCallManager = CommunityCallNotifier;
