import 'dart:async';
import 'package:flutter/services.dart';

class NativeBridge {
  static const _method = MethodChannel('com.example.intercom_app/call_service');
  static const _events = EventChannel('com.example.intercom_app/call_events');

  static StreamSubscription? _sub;

  static void Function(List<Map<String, dynamic>>)? onMembersChanged;
  // isSelf=true cuando el evento se refiere al propio dispositivo
  // (al crear la sala en soledad, o al reconectarse). En esos casos
  // la UI debe reproducir solo el sonido, sin mostrar texto.
  static void Function(String name, String ip, bool isSelf)? onMemberJoined;
  static void Function(String, String)? onMemberLeft;
  static void Function()? onCallStopped;
  static void Function(String ip, double level)? onSpeakingLevel;
  static void Function()? onConnectionLost;
  static void Function()? onConnectionRestored;
  static void Function(String?)? onCallStarted;
  // Lista de MACs WiFi Direct conocidas de los miembros de la sala,
  // a intentar reconectar cuando el banner "Reconectando" lleva
  // demasiado tiempo activo.
  static void Function(List<String> addresses)? onForceReconnectWifiDirect;

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
          onMemberJoined?.call(
            m['name'] as String,
            m['ip'] as String,
            m['isSelf'] as bool? ?? false,
          );
          break;
        case 'memberLeft':
          final m = Map<String, dynamic>.from(data as Map);
          onMemberLeft?.call(m['name'] as String, m['ip'] as String);
          break;
        case 'connectionLost':
          onConnectionLost?.call();
          break;
        case 'connectionRestored':
          onConnectionRestored?.call();
          break;
        case 'forceReconnectWifiDirect':
          final m = Map<String, dynamic>.from(data as Map);
          final addresses = (m['addresses'] as List? ?? [])
              .map((e) => e as String)
              .toList();
          onForceReconnectWifiDirect?.call(addresses);
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

  static Future<void> stopForegroundService() async {
    await _method.invokeMethod('stopForegroundService');
  }

  static Future<void> setNoiseLevel(int level) async {
    await _method.invokeMethod('setNoiseLevel', {'level': level});
  }

  // Asocia la MAC WiFi Direct de un miembro con su IP de sala —
  // se usa para poder forzar reconexión si la señal se pierde.
  static Future<void> setMemberWifiDirectAddress(
    String ip,
    String address,
  ) async {
    await _method.invokeMethod('setMemberWifiDirectAddress', {
      'ip': ip,
      'address': address,
    });
  }

  // Activa o desactiva el modo de bajo consumo en el servicio de llamada.
  static Future<void> setLowPowerMode(bool enabled) async {
    await _method.invokeMethod('setLowPowerMode', {'enabled': enabled});
  }
}
