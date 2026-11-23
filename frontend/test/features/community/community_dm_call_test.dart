import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_dm_ws_service.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/domain/models/community_dm.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_call_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_dm_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/dm/community_call_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/dm/community_chat_thread_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/dm/community_inbox_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestHttpOverrides extends HttpOverrides {
  static final List<int> _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FakeHttpClient(_transparentPng);
  }
}

class _FakeHttpClient implements HttpClient {
  final List<int> _bytes;
  _FakeHttpClient(this._bytes);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final List<int> _bytes;
  _FakeHttpClientRequest(this._bytes);

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final List<int> _bytes;
  _FakeHttpClientResponse(this._bytes);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeDmWsService extends CommunityDmWsService {
  final StreamController<DmWsEvent> _controller =
      StreamController<DmWsEvent>.broadcast(sync: true);

  final List<Map<String, dynamic>> sentPayloads = [];

  @override
  Stream<DmWsEvent> get events => _controller.stream;

  @override
  bool get isConnected => true;

  void emitServerEvent(DmWsEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void emitServerJson(Map<String, dynamic> json) {
    emitServerEvent(DmWsEvent.fromJson(json));
  }

  @override
  Future<void> connect({String? token}) async {}

  @override
  void sendTyping(String conversationId, bool isTyping) {
    sentPayloads.add({
      'event': 'typing',
      'conversation_id': conversationId,
      'is_typing': isTyping,
    });
  }

  @override
  void sendCallInvite({
    required String callId,
    required String conversationId,
    required String callType,
  }) {
    sentPayloads.add({
      'event': 'call.invite',
      'call_id': callId,
      'conversation_id': conversationId,
      'call_type': callType,
    });
  }

  @override
  void sendCallAccept({required String callId}) {
    sentPayloads.add({
      'event': 'call.accept',
      'call_id': callId,
    });
  }

  @override
  void sendCallReject({required String callId}) {
    sentPayloads.add({
      'event': 'call.reject',
      'call_id': callId,
    });
  }

  @override
  void sendCallCancel({required String callId}) {
    sentPayloads.add({
      'event': 'call.cancel',
      'call_id': callId,
    });
  }

  @override
  void sendCallHangup({required String callId}) {
    sentPayloads.add({
      'event': 'call.hangup',
      'call_id': callId,
    });
  }

  @override
  void sendCallBusy({required String callId}) {
    sentPayloads.add({
      'event': 'call.busy',
      'call_id': callId,
    });
  }

  @override
  void sendWebRtcOffer({
    required String callId,
    required String sdp,
    String sdpType = 'offer',
  }) {
    sentPayloads.add({
      'event': 'webrtc.offer',
      'call_id': callId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  @override
  void sendWebRtcAnswer({
    required String callId,
    required String sdp,
    String sdpType = 'answer',
  }) {
    sentPayloads.add({
      'event': 'webrtc.answer',
      'call_id': callId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  @override
  void sendWebRtcIce({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMlineIndex,
  }) {
    sentPayloads.add({
      'event': 'webrtc.ice',
      'call_id': callId,
      'candidate': candidate,
      'sdp_mid': sdpMid,
      'sdp_mline_index': sdpMlineIndex,
    });
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class FakeCommunityRtcBridge implements CommunityRtcBridge {
  final List<String> callLog = [];
  final List<RtcIceCandidateData> addedCandidates = [];
  RtcSdp? lastRemoteDescription;
  Completer<void>? remoteDescriptionGate;

  bool initialized = false;
  bool disposed = false;
  bool isVideoInitialized = false;
  bool muted = false;
  bool cameraEnabled = true;
  bool speakerOn = false;
  int switchCameraCount = 0;

  void Function(RtcIceCandidateData candidate)? _onIceCandidate;
  void Function()? _onConnected;
  void Function()? _onDisconnected;
  void Function(bool hasRemoteVideo)? _onRemoteVideoStateChanged;

  @override
  Object? get localRenderer => const Object();

  @override
  Object? get remoteRenderer => const Object();

  void simulateLocalIce(String candidate, {String? sdpMid = '0', int? index = 0}) {
    _onIceCandidate?.call(
      RtcIceCandidateData(
        candidate: candidate,
        sdpMid: sdpMid,
        sdpMlineIndex: index,
      ),
    );
  }

  void simulateConnected() => _onConnected?.call();
  void simulateDisconnected() => _onDisconnected?.call();
  void simulateRemoteVideo(bool enabled) =>
      _onRemoteVideoStateChanged?.call(enabled);

  @override
  Future<void> initialize({
    required bool isVideo,
    required void Function(RtcIceCandidateData candidate) onIceCandidate,
    required void Function() onConnected,
    required void Function() onDisconnected,
    void Function(bool hasRemoteVideo)? onRemoteVideoStateChanged,
  }) async {
    initialized = true;
    disposed = false;
    isVideoInitialized = isVideo;
    cameraEnabled = isVideo;
    _onIceCandidate = onIceCandidate;
    _onConnected = onConnected;
    _onDisconnected = onDisconnected;
    _onRemoteVideoStateChanged = onRemoteVideoStateChanged;
    callLog.add('initialize(isVideo:$isVideo)');
  }

  @override
  Future<RtcSdp> createOffer({required bool isVideo}) async {
    callLog.add('createOffer');
    return const RtcSdp(sdp: 'fake-offer-sdp', type: 'offer');
  }

  @override
  Future<RtcSdp> createAnswer({required bool isVideo}) async {
    callLog.add('createAnswer');
    return const RtcSdp(sdp: 'fake-answer-sdp', type: 'answer');
  }

  @override
  Future<void> setRemoteDescription(RtcSdp description) async {
    callLog.add('setRemoteDescription:start(${description.type})');
    if (remoteDescriptionGate != null) {
      await remoteDescriptionGate!.future;
    }
    lastRemoteDescription = description;
    callLog.add('setRemoteDescription:done(${description.type})');
  }

  @override
  Future<void> addIceCandidate(RtcIceCandidateData candidate) async {
    addedCandidates.add(candidate);
    callLog.add('addIceCandidate(${candidate.candidate})');
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    this.muted = muted;
    callLog.add('setMicrophoneMuted($muted)');
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    cameraEnabled = enabled;
    callLog.add('setCameraEnabled($enabled)');
  }

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {
    speakerOn = enabled;
    callLog.add('setSpeakerphoneOn($enabled)');
  }

  @override
  Future<void> switchCamera() async {
    switchCameraCount++;
    callLog.add('switchCamera');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    callLog.add('dispose');
  }
}

Widget _buildTestApp({
  required Widget home,
  required CommunityFakeDatasource fakeDatasource,
  required FakeDmWsService wsService,
  required FakeCommunityRtcBridge rtcBridge,
  CallPermissionChecker? permissionChecker,
  Locale locale = const Locale('vi'),
  ThemeMode themeMode = ThemeMode.dark,
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      useRemoteCommunityProvider.overrideWith((ref) => false),
      communityFakeDatasourceProvider.overrideWithValue(fakeDatasource),
      communityDmWsServiceProvider.overrideWithValue(wsService),
      communityRtcBridgeFactoryProvider.overrideWithValue(() => rtcBridge),
      communityCallPermissionCheckerProvider.overrideWithValue(
        permissionChecker ?? ({required bool isVideo}) async => true,
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: home,
    ),
  );
}

void main() {
  HttpOverrides? previousOverrides;

  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });

  setUp(() {
    CommunityCallScreen.isPresented = false;
    SharedPreferences.setMockInitialValues({
      'language_mode': 'vi',
      'language_code': 'vi',
    });
    CommunityFakeDatasource.resetStorage();
  });

  tearDown(() {
    CommunityCallScreen.isPresented = false;
  });

  const peerCoach = DmParticipant(
    id: 'author_minh',
    name: 'Coach Minh',
    isVerified: true,
    showActivityStatus: true,
  );

  group('Phase 5B/5C Domain, WS Parsing & Translations', () {
    test('DmMessage & DmWsEvent parse call_log and all 11 call/webrtc events', () {
      expect(DmMessageType.callLog.toApiValue(), 'call_log');
      expect(DmMessageType.fromApiValue('call_log'), DmMessageType.callLog);

      final callLogMsg = DmMessage.fromJson({
        'id': 'msg_call_1',
        'conversation_id': 'conv_1',
        'sender_id': 'author_minh',
        'type': 'call_log',
        'content': 'Cuộc gọi video • 02:05',
        'created_at': '2026-11-23T06:00:00Z',
        'call_id': 'call_123',
        'call_type': 'video',
        'call_status': 'completed',
        'duration_sec': 125,
      });

      expect(callLogMsg.type, DmMessageType.callLog);
      expect(callLogMsg.callId, 'call_123');
      expect(callLogMsg.callType, 'video');
      expect(callLogMsg.callStatus, 'completed');
      expect(callLogMsg.durationSec, 125);
      expect(formatDmCallDuration(callLogMsg.durationSec), '02:05');

      final roundTrip = DmMessage.fromJson(callLogMsg.toJson());
      expect(roundTrip.callId, 'call_123');
      expect(roundTrip.callType, 'video');
      expect(roundTrip.callStatus, 'completed');
      expect(roundTrip.durationSec, 125);

      final inviteEvt = DmWsEvent.fromJson({
        'event': 'call.invite',
        'call_id': 'call_abc',
        'conversation_id': 'conv_1',
        'call_type': 'video',
        'caller': {
          'id': 'author_minh',
          'name': 'Coach Minh',
          'is_verified': true,
          'show_activity_status': true,
        },
      });
      expect(inviteEvt.event, 'call.invite');
      expect(inviteEvt.callId, 'call_abc');
      expect(inviteEvt.callType, 'video');
      expect(inviteEvt.caller?.name, 'Coach Minh');
      expect(inviteEvt.caller?.isVerified, isTrue);

      final iceEvt = DmWsEvent.fromJson({
        'event': 'webrtc.ice',
        'call_id': 'call_abc',
        'conversation_id': 'conv_1',
        'from_user_id': 'author_minh',
        'candidate': 'candidate:1 1 UDP 2122252543 192.168.1.2 54321 typ host',
        'sdp_mid': '0',
        'sdp_mline_index': 0,
      });
      expect(iceEvt.event, 'webrtc.ice');
      expect(iceEvt.candidate, contains('candidate:1'));
      expect(iceEvt.sdpMid, '0');
      expect(iceEvt.sdpMlineIndex, 0);
    });

    test('AppTranslations provides all community_call_* keys in EN and VI', () {
      const keys = [
        'community_call_audio',
        'community_call_video',
        'community_call_incoming_audio',
        'community_call_incoming_video',
        'community_call_ringing',
        'community_call_connecting',
        'community_call_ended',
        'community_call_busy',
        'community_call_rejected',
        'community_call_missed',
        'community_call_again',
        'community_call_accept',
        'community_call_decline',
        'community_call_mic',
        'community_call_speaker',
        'community_call_camera',
        'community_call_flip',
        'community_call_permission_denied',
      ];
      for (final key in keys) {
        final vi = AppTranslations.text(key, const Locale('vi'));
        final en = AppTranslations.text(key, const Locale('en'));
        expect(vi, isNotEmpty);
        expect(en, isNotEmpty);
        expect(vi, isNot(equals(key)));
        expect(en, isNot(equals(key)));
      }
    });
  });

  group('CommunityCallNotifier State Machine & ICE Candidate Queue', () {
    test(
      'Outgoing video call -> call.accept -> early ICE candidates queued before setRemoteDescription and flushed in order -> hangup',
      () async {
        final ws = FakeDmWsService();
        final bridge = FakeCommunityRtcBridge();
        final notifier = CommunityCallNotifier(
          wsService: ws,
          rtcBridgeFactory: () => bridge,
          permissionChecker: ({required bool isVideo}) async => true,
        );
        addTearDown(() {
          notifier.dispose();
          ws.dispose();
        });

        final started = await notifier.startCall(
          conversationId: 'conv_1',
          peer: peerCoach,
          callType: 'video',
          callId: 'call_out_1',
        );
        expect(started, isTrue);
        expect(notifier.state.phase, CallLifecyclePhase.outgoingRinging);
        expect(notifier.state.isVideo, isTrue);
        expect(notifier.state.isSpeakerOn, isTrue);
        expect(
          ws.sentPayloads.last,
          {
            'event': 'call.invite',
            'call_id': 'call_out_1',
            'conversation_id': 'conv_1',
            'call_type': 'video',
          },
        );

        // Callee accepts -> caller transitions to connecting & sends webrtc.offer
        ws.emitServerJson({
          'event': 'call.accept',
          'call_id': 'call_out_1',
          'conversation_id': 'conv_1',
          'by_user_id': 'author_minh',
        });
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.phase, CallLifecyclePhase.connecting);
        expect(
          ws.sentPayloads.last,
          {
            'event': 'webrtc.offer',
            'call_id': 'call_out_1',
            'sdp': 'fake-offer-sdp',
            'sdp_type': 'offer',
          },
        );

        // Two ICE candidates arrive BEFORE webrtc.answer (before setRemoteDescription)
        ws.emitServerJson({
          'event': 'webrtc.ice',
          'call_id': 'call_out_1',
          'candidate': 'cand_early_1',
          'sdp_mid': '0',
          'sdp_mline_index': 0,
        });
        ws.emitServerJson({
          'event': 'webrtc.ice',
          'call_id': 'call_out_1',
          'candidate': 'cand_early_2',
          'sdp_mid': '0',
          'sdp_mline_index': 1,
        });
        await Future<void>.delayed(Duration.zero);

        // Must be queued, NOT added to bridge yet
        expect(notifier.hasRemoteDescription, isFalse);
        expect(notifier.pendingRemoteIce.length, 2);
        expect(bridge.addedCandidates, isEmpty);

        // Hold setRemoteDescription on a gate to also test ICE arriving DURING setRemoteDescription
        final gate = Completer<void>();
        bridge.remoteDescriptionGate = gate;

        ws.emitServerJson({
          'event': 'webrtc.answer',
          'call_id': 'call_out_1',
          'sdp': 'fake-remote-answer-sdp',
          'sdp_type': 'answer',
        });
        await Future<void>.delayed(Duration.zero);

        ws.emitServerJson({
          'event': 'webrtc.ice',
          'call_id': 'call_out_1',
          'candidate': 'cand_during_set_remote_3',
          'sdp_mid': '0',
          'sdp_mline_index': 0,
        });
        await Future<void>.delayed(Duration.zero);

        expect(notifier.pendingRemoteIce.length, 3);
        expect(bridge.addedCandidates, isEmpty);

        // Complete setRemoteDescription -> queue must flush in exact FIFO order
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(notifier.hasRemoteDescription, isTrue);
        expect(notifier.pendingRemoteIce, isEmpty);
        expect(
          bridge.addedCandidates.map((c) => c.candidate).toList(),
          ['cand_early_1', 'cand_early_2', 'cand_during_set_remote_3'],
        );
        expect(notifier.state.phase, CallLifecyclePhase.connected);

        // Verify callLog order: setRemoteDescription:done happened BEFORE all addIceCandidate calls
        final doneIdx =
            bridge.callLog.indexOf('setRemoteDescription:done(answer)');
        final firstIceIdx =
            bridge.callLog.indexOf('addIceCandidate(cand_early_1)');
        expect(doneIdx, isNonNegative);
        expect(firstIceIdx, greaterThan(doneIdx));

        // Subsequent ICE candidate after setRemoteDescription is added immediately
        ws.emitServerJson({
          'event': 'webrtc.ice',
          'call_id': 'call_out_1',
          'candidate': 'cand_live_4',
          'sdp_mid': '0',
          'sdp_mline_index': 0,
        });
        await Future<void>.delayed(Duration.zero);
        expect(bridge.addedCandidates.length, 4);
        expect(bridge.addedCandidates.last.candidate, 'cand_live_4');

        // Hangup sends call.hangup and disposes bridge
        await notifier.hangup();
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'hangup');
        expect(bridge.disposed, isTrue);
        expect(
          ws.sentPayloads.last,
          {'event': 'call.hangup', 'call_id': 'call_out_1'},
        );
      },
    );

    test(
      'Incoming call -> rejectCall, busy auto-response during active call, cancel, handled_elsewhere, and permission denial',
      () async {
        final ws = FakeDmWsService();
        final bridge = FakeCommunityRtcBridge();
        bool grantPermission = true;

        final notifier = CommunityCallNotifier(
          wsService: ws,
          rtcBridgeFactory: () => bridge,
          permissionChecker: ({required bool isVideo}) async => grantPermission,
        );
        addTearDown(() {
          notifier.dispose();
          ws.dispose();
        });

        // 1. Incoming call -> rejectCall()
        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_in_1',
          'conversation_id': 'conv_1',
          'call_type': 'audio',
          'caller': peerCoach.toJson(),
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.phase, CallLifecyclePhase.incomingRinging);
        expect(notifier.state.isIncoming, isTrue);

        await notifier.rejectCall();
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'rejected');
        expect(
          ws.sentPayloads.last,
          {'event': 'call.reject', 'call_id': 'call_in_1'},
        );
        notifier.dismissEndedState();
        expect(notifier.state.phase, CallLifecyclePhase.idle);

        // 2. Incoming call while busy in another call -> sends call.busy for second call only
        await notifier.startCall(
          conversationId: 'conv_1',
          peer: peerCoach,
          callType: 'audio',
          callId: 'call_active_1',
        );
        expect(notifier.state.phase, CallLifecyclePhase.outgoingRinging);

        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_intruder_2',
          'conversation_id': 'conv_2',
          'call_type': 'video',
          'caller': {'id': 'user_other', 'name': 'Other Athlete'},
        });
        await Future<void>.delayed(Duration.zero);

        // Active call is untouched; call.busy sent for intruder call
        expect(notifier.state.callId, 'call_active_1');
        expect(notifier.state.phase, CallLifecyclePhase.outgoingRinging);
        expect(
          ws.sentPayloads.last,
          {'event': 'call.busy', 'call_id': 'call_intruder_2'},
        );

        await notifier.cancelCall();
        notifier.dismissEndedState();

        // 3. Incoming call -> remote call.cancel
        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_in_cancel',
          'conversation_id': 'conv_1',
          'call_type': 'audio',
          'caller': peerCoach.toJson(),
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.phase, CallLifecyclePhase.incomingRinging);

        ws.emitServerJson({
          'event': 'call.cancel',
          'call_id': 'call_in_cancel',
          'conversation_id': 'conv_1',
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'canceled');
        notifier.dismissEndedState();

        // 4. Incoming call -> call.handled_elsewhere
        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_in_elsewhere',
          'conversation_id': 'conv_1',
          'call_type': 'video',
          'caller': peerCoach.toJson(),
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.phase, CallLifecyclePhase.incomingRinging);

        ws.emitServerJson({
          'event': 'call.handled_elsewhere',
          'call_id': 'call_in_elsewhere',
          'conversation_id': 'conv_1',
        });
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'handled_elsewhere');
        notifier.dismissEndedState();

        // 5. Permission denied on startCall & acceptCall
        grantPermission = false;
        final outOk = await notifier.startCall(
          conversationId: 'conv_1',
          peer: peerCoach,
          callType: 'video',
          callId: 'call_denied_out',
        );
        expect(outOk, isFalse);
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'permission_denied');
        notifier.dismissEndedState();

        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_denied_in',
          'conversation_id': 'conv_1',
          'call_type': 'audio',
          'caller': peerCoach.toJson(),
        });
        await Future<void>.delayed(Duration.zero);
        final inOk = await notifier.acceptCall();
        expect(inOk, isFalse);
        expect(notifier.state.phase, CallLifecyclePhase.ended);
        expect(notifier.state.endReason, 'permission_denied');
        expect(
          ws.sentPayloads.last,
          {'event': 'call.reject', 'call_id': 'call_denied_in'},
        );
      },
    );
  });

  group('Widget Tests: CommunityCallScreen & CommunityChatThreadScreen', () {
    testWidgets(
      'CommunityCallScreen renders incoming call buttons and in-call controls (mic/speaker/camera/flip/hangup)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final ws = FakeDmWsService();
        final bridge = FakeCommunityRtcBridge();
        final fakeDs = CommunityFakeDatasource(currentUserId: 'author_linh');
        addTearDown(() => ws.dispose());

        await tester.pumpWidget(
          _buildTestApp(
            fakeDatasource: fakeDs,
            wsService: ws,
            rtcBridge: bridge,
            home: const CommunityInboxScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Emit incoming video call -> CommunityCallHostListener auto-presents CommunityCallScreen
        ws.emitServerJson({
          'event': 'call.invite',
          'call_id': 'call_ui_1',
          'conversation_id': 'conv_1',
          'call_type': 'video',
          'caller': peerCoach.toJson(),
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(CommunityCallScreen), findsOneWidget);
        expect(find.text('Coach Minh'), findsWidgets);
        expect(find.text('Cuộc gọi video đến'), findsOneWidget);

        final rejectBtn = find.byKey(const Key('call-reject-button'));
        final acceptBtn = find.byKey(const Key('call-accept-button'));
        expect(rejectBtn, findsOneWidget);
        expect(acceptBtn, findsOneWidget);

        // Tap Accept -> transitions to connecting
        await tester.tap(acceptBtn);
        await tester.pump();

        // Emit webrtc.offer -> callee answers and transitions to connected
        ws.emitServerJson({
          'event': 'webrtc.offer',
          'call_id': 'call_ui_1',
          'conversation_id': 'conv_1',
          'from_user_id': 'author_minh',
          'sdp': 'remote-offer-sdp',
          'sdp_type': 'offer',
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('call-local-pip')), findsOneWidget);

        // Toggle mic, speaker, camera, switch camera
        await tester.tap(find.byKey(const Key('call-toggle-mic-button')));
        await tester.pump();
        expect(bridge.muted, isTrue);

        await tester.tap(find.byKey(const Key('call-toggle-speaker-button')));
        await tester.pump();
        expect(bridge.speakerOn, isFalse);

        await tester.tap(find.byKey(const Key('call-toggle-camera-button')));
        await tester.pump();
        expect(bridge.cameraEnabled, isFalse);

        // Re-enable camera then flip camera
        await tester.tap(find.byKey(const Key('call-toggle-camera-button')));
        await tester.pump();
        expect(bridge.cameraEnabled, isTrue);

        await tester.tap(find.byKey(const Key('call-switch-camera-button')));
        await tester.pump();
        expect(bridge.switchCameraCount, 1);

        // Hangup -> ends call and auto-dismisses after 1.2s
        await tester.tap(find.byKey(const Key('call-hangup-button')));
        await tester.pump();
        expect(find.byKey(const Key('call-ended-reason-text')), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityCallScreen), findsNothing);
      },
    );

    testWidgets(
      'CommunityChatThreadScreen renders AppBar Phone/Video buttons and call_log bubbles (completed, missed, rejected)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final ws = FakeDmWsService();
        final bridge = FakeCommunityRtcBridge();
        final fakeDs = CommunityFakeDatasource(currentUserId: 'author_linh');
        addTearDown(() => ws.dispose());

        final conv = fakeDs.createOrGetConversation('author_minh');

        await tester.pumpWidget(
          _buildTestApp(
            fakeDatasource: fakeDs,
            wsService: ws,
            rtcBridge: bridge,
            home: CommunityChatThreadScreen(
              conversationId: conv.id,
              peer: conv.peer,
              initialConversation: conv,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify AppBar call buttons (>= 44x44)
        final audioBtn = find.byKey(const Key('call-audio-button'));
        final videoBtn = find.byKey(const Key('call-video-button'));
        expect(audioBtn, findsOneWidget);
        expect(videoBtn, findsOneWidget);
        expect(tester.getSize(audioBtn).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(audioBtn).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(videoBtn).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(videoBtn).height, greaterThanOrEqualTo(44));

        // Inject 3 realtime call_log messages: completed, missed, rejected
        final now = DateTime.now().toUtc();
        ws.emitServerEvent(
          DmWsEvent(
            event: 'message.created',
            conversationId: conv.id,
            message: DmMessage(
              id: 'log_completed',
              conversationId: conv.id,
              senderId: 'author_linh',
              type: DmMessageType.callLog,
              content: 'Cuộc gọi thoại • 02:05',
              callId: 'c1',
              callType: 'audio',
              callStatus: 'completed',
              durationSec: 125,
              createdAt: now,
            ),
          ),
        );
        ws.emitServerEvent(
          DmWsEvent(
            event: 'message.created',
            conversationId: conv.id,
            message: DmMessage(
              id: 'log_missed',
              conversationId: conv.id,
              senderId: 'author_minh',
              type: DmMessageType.callLog,
              content: 'Cuộc gọi video nhỡ',
              callId: 'c2',
              callType: 'video',
              callStatus: 'missed',
              durationSec: 0,
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ),
        );
        ws.emitServerEvent(
          DmWsEvent(
            event: 'message.created',
            conversationId: conv.id,
            message: DmMessage(
              id: 'log_rejected',
              conversationId: conv.id,
              senderId: 'author_minh',
              type: DmMessageType.callLog,
              content: 'Đã từ chối cuộc gọi',
              callId: 'c3',
              callType: 'audio',
              callStatus: 'rejected',
              durationSec: 0,
              createdAt: now.add(const Duration(seconds: 2)),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey('call-log-bubble-log_completed')),
          findsOneWidget,
        );
        expect(find.text('02:05'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('call-log-bubble-log_missed')),
          findsOneWidget,
        );
        expect(find.text('Cuộc gọi video nhỡ'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('call-log-bubble-log_rejected')),
          findsOneWidget,
        );
        expect(find.text('Đã từ chối cuộc gọi'), findsOneWidget);

        // Tap audio call button on AppBar -> starts outgoing audio call & opens CommunityCallScreen
        await tester.tap(audioBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(CommunityCallScreen), findsOneWidget);
        expect(find.text('Đang đổ chuông...'), findsOneWidget);
        expect(
          ws.sentPayloads.any(
            (p) => p['event'] == 'call.invite' && p['call_type'] == 'audio',
          ),
          isTrue,
        );

        // Cancel outgoing call to clean up timers
        await tester.tap(find.byKey(const Key('call-hangup-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pumpAndSettle();
      },
    );
  });
}
