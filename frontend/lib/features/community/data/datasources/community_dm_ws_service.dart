import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../config/api_config.dart';
import '../../../../utils/auth_helper.dart';
import '../../domain/models/community_dm.dart';

typedef DmWsChannelFactory = WebSocketChannel Function(Uri uri);
typedef DmWsTokenProvider = Future<String?> Function();

class CommunityDmWsService {
  final String baseUrl;
  final DmWsChannelFactory _channelFactory;
  final DmWsTokenProvider _tokenProvider;
  final Duration pingInterval;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;

  final StreamController<DmWsEvent> _eventsController =
      StreamController<DmWsEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _manualDisconnect = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempt = 0;
  String? _activeToken;

  CommunityDmWsService({
    String? baseUrl,
    DmWsChannelFactory? channelFactory,
    DmWsTokenProvider? tokenProvider,
    this.pingInterval = const Duration(seconds: 25),
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _tokenProvider = tokenProvider ?? AuthHelper.getToken;

  Stream<DmWsEvent> get events => _eventsController.stream;
  bool get isConnected => _isConnected;

  static Uri buildWsUri(String baseUrl, String token) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final wsBase = normalized.startsWith('https://')
        ? 'wss://${normalized.substring('https://'.length)}'
        : normalized.startsWith('http://')
            ? 'ws://${normalized.substring('http://'.length)}'
            : normalized;
    return Uri.parse('$wsBase/api/community/ws/chat').replace(
      queryParameters: {'token': token},
    );
  }

  String? _resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '$baseUrl$url';
    }
    if (url.startsWith('static/')) {
      return '$baseUrl/$url';
    }
    return url;
  }

  Future<void> connect({String? token}) async {
    if (_isConnected || _isConnecting) return;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final resolvedToken = (token ?? await _tokenProvider())?.trim();
    if (resolvedToken == null || resolvedToken.isEmpty) {
      return;
    }

    _activeToken = resolvedToken;
    _openSocket(resolvedToken);
  }

  void _openSocket(String token) {
    if (_manualDisconnect || _eventsController.isClosed) return;
    _isConnecting = true;
    try {
      final uri = buildWsUri(baseUrl, token);
      final channel = _channelFactory(uri);
      _channel = channel;
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempt = 0;

      _startPingTimer();

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (_) => _handleDisconnect(),
        onDone: () {
          final closeCode = channel.closeCode;
          if (closeCode == 4401) {
            _manualDisconnect = true;
          }
          _handleDisconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _isConnecting = false;
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final event = DmWsEvent.fromJson(
        map,
        resolveMediaUrl: _resolveMediaUrl,
      );
      if (!_eventsController.isClosed) {
        _eventsController.add(event);
      }
    } catch (_) {
      // Ignore malformed frames
    }
  }

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _isConnected = false;
    _isConnecting = false;

    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _eventsController.isClosed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    final multiplier = 1 << (_reconnectAttempt.clamp(0, 5));
    final rawMs = initialReconnectDelay.inMilliseconds * multiplier;
    final clampedMs = rawMs > maxReconnectDelay.inMilliseconds
        ? maxReconnectDelay.inMilliseconds
        : rawMs;
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(milliseconds: clampedMs), () async {
      if (_manualDisconnect || _eventsController.isClosed) return;
      final token = (_activeToken ?? await _tokenProvider())?.trim();
      if (token == null || token.isEmpty) return;
      _openSocket(token);
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      if (!_isConnected || _channel == null) return;
      _sendRaw({'event': 'ping'});
    });
  }

  void sendTyping(String conversationId, bool isTyping) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'typing',
      'conversation_id': conversationId,
      'is_typing': isTyping,
    });
  }

  void sendCallInvite({
    required String callId,
    required String conversationId,
    required String callType,
  }) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.invite',
      'call_id': callId,
      'conversation_id': conversationId,
      'call_type': callType,
    });
  }

  void sendCallAccept({required String callId}) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.accept',
      'call_id': callId,
    });
  }

  void sendCallReject({required String callId}) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.reject',
      'call_id': callId,
    });
  }

  void sendCallCancel({required String callId}) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.cancel',
      'call_id': callId,
    });
  }

  void sendCallHangup({required String callId}) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.hangup',
      'call_id': callId,
    });
  }

  void sendCallBusy({required String callId}) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'call.busy',
      'call_id': callId,
    });
  }

  void sendWebRtcOffer({
    required String callId,
    required String sdp,
    String sdpType = 'offer',
  }) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'webrtc.offer',
      'call_id': callId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  void sendWebRtcAnswer({
    required String callId,
    required String sdp,
    String sdpType = 'answer',
  }) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'webrtc.answer',
      'call_id': callId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  void sendWebRtcIce({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMlineIndex,
  }) {
    if (!_isConnected || _channel == null) return;
    _sendRaw({
      'event': 'webrtc.ice',
      'call_id': callId,
      'candidate': candidate,
      'sdp_mid': sdpMid,
      'sdp_mline_index': sdpMlineIndex,
    });
  }

  void _sendRaw(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {
      // Ignore sink errors; onDone/onError will trigger reconnect
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _activeToken = null;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
  }

  Future<void> dispose() async {
    await disconnect();
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }
}
