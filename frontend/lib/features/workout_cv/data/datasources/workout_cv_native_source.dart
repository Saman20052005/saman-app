import 'dart:async';
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
    try {
      final result = await _methodChannel.invokeMethod<String>('checkPermission');
      return result ?? 'denied';
    } catch (_) {
      return 'denied';
    }
  }

  Future<bool> requestPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startSession(String exerciseSlug) async {
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

  Future<bool> stopSession() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopSession');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, dynamic>> get eventStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    });
  }
}
