import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WorkoutCvNativeSource {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  WorkoutCvNativeSource({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('com.example.health_ai_app/workout_cv/method'),
        _eventChannel = eventChannel ??
            const EventChannel('com.example.health_ai_app/workout_cv/events');

  Future<String> checkPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 'unsupported';
    try {
      final result = await _methodChannel.invokeMethod<String>('checkPermission');
      return result ?? 'denied';
    } catch (_) {
      return 'denied';
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startSession(String exerciseSlug) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startSession',
        {'exerciseSlug': exerciseSlug},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startVideoReplay(String videoPath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startVideoReplay',
        {'videoPath': videoPath},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> switchSource(String mode, {String? videoPath}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'switchSource',
        {'mode': mode, 'videoPath': videoPath},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restartVideoReplay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>('restartVideoReplay');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopSession');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acknowledgeReplayFrame(int sessionGen, int videoPtsMs, String phase) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('acknowledgeReplayFrame', {
        'sessionGen': sessionGen,
        'videoPtsMs': videoPtsMs,
        'phase': phase,
      }).timeout(const Duration(seconds: 2)) ?? false;
    } on PlatformException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Stream<Map<String, dynamic>> get eventStream {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    });
  }
}
