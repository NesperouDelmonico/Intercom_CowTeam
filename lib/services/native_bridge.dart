// Puente temporal — se reescribirá con la nueva arquitectura
import 'dart:async';
import 'package:flutter/services.dart';

class NativeBridge {
  static const _method = MethodChannel('com.example.intercom_app/call_service');
  static const _events = EventChannel('com.example.intercom_app/call_events');

  static StreamSubscription? _sub;

  static void Function(List<Map<String, dynamic>>)? onMembersChanged;
  static void Function(String, String)? onMemberJoined;
  static void Function(String, String)? onMemberLeft;
  static void Function()? onCallStopped;
  static void Function(String ip, double level)? onSpeakingLevel;

  static void startListening() {
    _sub?.cancel();
    _sub = _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['type'] as String?;
      final data = event['data'];
      switch (type) {
        case 'membersChanged':
          final list = (data as List)
              .map((m) => Map<String, dynamic>.from(m as Map))
              .toList();
          onMembersChanged?.call(list);
          break;
        case 'callStarted':
          final m = Map<String, dynamic>.from(data as Map);
          print('DEBUG callStarted recibido: roomCode=${m['roomCode']}');
          onCallStarted?.call(m['roomCode'] as String?);
          break;
        case 'speakingLevel':
          final m = Map<String, dynamic>.from(data as Map);
          onSpeakingLevel?.call(
            m['ip'] as String,
            (m['level'] as num).toDouble(),
          );
          break;
        case 'memberJoined':
          final m = Map<String, dynamic>.from(data as Map);
          onMemberJoined?.call(m['name'] as String, m['ip'] as String);
          break;
        case 'memberLeft':
          final m = Map<String, dynamic>.from(data as Map);
          onMemberLeft?.call(m['name'] as String, m['ip'] as String);
          break;
        case 'callStopped':
          onCallStopped?.call();
          break;
      }
    });
  }

  static void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> startCallWithService({
    required String deviceName,
    required String myIp,
    required String myName,
    required String myAvatar,
    required String roomCode,
  }) async {
    await _method.invokeMethod('startCallWithService', {
      'deviceName': deviceName,
      'myIp': myIp,
      'myName': myName,
      'myAvatar': myAvatar,
      'roomCode': roomCode,
    });
  }

  static Future<void> stopCall() async {
    await _method.invokeMethod('stopCall');
  }

  static Future<void> setMuted(bool muted) async {
    await _method.invokeMethod('setMuted', {'muted': muted});
  }

  static Future<void> setMemberMuted(String ip, bool muted) async {
    await _method.invokeMethod('setMemberMuted', {'ip': ip, 'muted': muted});
  }

  static Future<void> setMemberVolume(String ip, double volume) async {
    await _method.invokeMethod('setMemberVolume', {'ip': ip, 'volume': volume});
  }

  static Future<void> setGain(double gain) async {
    await _method.invokeMethod('setGain', {'gain': gain});
  }

  static Future<void> setVox({
    required bool enabled,
    required double threshold,
  }) async {
    await _method.invokeMethod('setVox', {
      'enabled': enabled,
      'threshold': threshold,
    });
  }

  static void Function(String?)? onCallStarted;

  static Future<void> stopForegroundService() async {
    await _method.invokeMethod('stopForegroundService');
  }
}
