import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/services/room_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intercom_app/services/audio_service.dart';
import 'package:intercom_app/services/wifi_direct_service.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intercom_app/models/room_info.dart';

final _wifiDirect = WifiDirectService();

class RoomNotifier extends Notifier<RoomState> {
  final RoomService _room = RoomService();
  static const _ch = MethodChannel('com.example.intercom_app/audio');
  final AudioService _audio = AudioService();
  String _myIp = '';
  String _myName = '';

  @override
  RoomState build() {
    _init();
    return const RoomState();
  }

  Future<void> _init() async {
    final info = await DeviceInfoPlugin().androidInfo;
    _myName = info.model;
    _myIp = await _getActiveIp();
  }

  Future<String> _getActiveIp() async {
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        // Preferir IP WiFi Direct
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback &&
                addr.address != '0.0.0.0' &&
                addr.address.startsWith('192.168.49.')) {
              return addr.address;
            }
          }
        }
        // Usar primera IP válida
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.address != '0.0.0.0') {
              return addr.address;
            }
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return await NetworkInfo().getWifiIP() ?? '';
  }

  Future<bool> hasNetworkConnection() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      return ip != null && ip.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> createRoom() async {
    await _init();
    final code = _room.generateRoomCode();
    await _ch.invokeMethod('startPlayback');

    _room.onAudioReceived = (data, fromIp) {
      final member = _room.members[fromIp];
      if (member == null || member.isMuted) return;
      final adjusted = _applyVolume(data, member.volume);
      _ch.invokeMethod('playChunk', {'data': adjusted});
    };

    _room.onMembersChanged = (members) {
      state = state.copyWith(members: Map.from(members));
    };

    final avatarBase64 = await _loadAvatarBase64();

    _wifiDirect.startListening();
    try {
      await _wifiDirect.createGroup();
    } catch (_) {}

    await _room.createRoom(_myName, _myIp, avatarBase64: avatarBase64);
    _room.announceRoom(code);

    _room.onRoomQuery = (queryCode, fromIp) {
      if (queryCode == code) {
        _room.respondToQuery(fromIp, code);
      }
    };

    await _startAudioCapture();
    _room.startAutoReconnect();

    state = state.copyWith(
      status: RoomStatus.hosting,
      roomCode: code,
      isHost: true,
      members: Map.from(_room.members),
    );
  }

  Future<void> joinRoom(String hostIp) async {
    await _init();

    // Esperar que la interfaz de red esté lista
    await Future.delayed(const Duration(seconds: 2));

    // Re-obtener IP por si cambió
    _myIp = await _getActiveIp();

    await _ch.invokeMethod('startPlayback');

    _room.onAudioReceived = (data, fromIp) {
      final member = _room.members[fromIp];
      if (member == null || member.isMuted) return;
      final adjusted = _applyVolume(data, member.volume);
      _ch.invokeMethod('playChunk', {'data': adjusted});
    };

    _room.onMembersChanged = (members) {
      state = state.copyWith(members: Map.from(members));
    };

    final avatarBase64 = await _loadAvatarBase64();
    await _room.joinRoom(_myName, _myIp, hostIp, avatarBase64: avatarBase64);
    await _startAudioCapture();
    _room.startAutoReconnect();

    state = state.copyWith(
      status: RoomStatus.joined,
      isHost: false,
      members: Map.from(_room.members),
    );
  }

  Future<void> joinRoomByCode(String code) async {
    // Estrategia 1: red WiFi normal
    var hostIp = await RoomService.findRoomHost(code);
    if (hostIp != null) {
      await joinRoom(hostIp);
      return;
    }
    // Estrategia 2: subred WiFi Direct
    await searchAndJoinViaWifiDirect(code);
  }

  Future<bool> searchAndJoinViaWifiDirect(String code) async {
    final completer = Completer<String?>();
    try {
      final receiveSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        RoomService.announcePort,
        reuseAddress: true,
      );

      receiveSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = receiveSocket.receive();
          if (dg == null) return;
          final msg = String.fromCharCodes(dg.data);
          if (msg.startsWith('ROOM:$code:') && !completer.isCompleted) {
            completer.complete(msg.split(':')[2]);
          }
        }
      });

      final querySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      for (int i = 1; i <= 10; i++) {
        querySocket.send(
          'ROOM_QUERY:$code'.codeUnits,
          InternetAddress('192.168.49.$i'),
          RoomService.signalPort,
        );
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final hostIp = await completer.future;
      querySocket.close();
      receiveSocket.close();

      if (hostIp == null) return false;
      await joinRoom(hostIp);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startAudioCapture() async {
    final hasPermission = await _audio.recorder.hasPermission();
    if (!hasPermission) return;

    final stream = await _audio.recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    stream.listen((chunk) {
      if (state.globalMuted) return;
      final gained = _audio.applyGain(chunk, _audio.micGain);
      if (!_audio.shouldTransmit(gained)) return;
      _room.sendAudio(Uint8List.fromList(gained));
    });
  }

  Uint8List _applyVolume(Uint8List data, double volume) {
    if (volume == 1.0) return data;
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length - 1; i += 2) {
      final s = data[i] | (data[i + 1] << 8);
      final signed = s > 32767 ? s - 65536 : s;
      final adjusted = (signed * volume).round().clamp(-32768, 32767);
      result[i] = adjusted & 0xFF;
      result[i + 1] = (adjusted >> 8) & 0xFF;
    }
    return result;
  }

  Future<String?> _loadAvatarBase64() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/avatar.jpg');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // Solo enviar si es menor a 30KB — si es mayor, no enviar avatar
      if (bytes.length > 30000) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  void setMemberMuted(String ip, bool muted) {
    _room.setMemberMuted(ip, muted);
  }

  void setMemberVolume(String ip, double volume) {
    _room.setMemberVolume(ip, volume);
    state = state.copyWith(members: Map.from(_room.members));
  }

  void toggleGlobalMute() {
    state = state.copyWith(globalMuted: !state.globalMuted);
  }

  Future<void> leaveRoom() async {
    _room.leaveRoom();
    await _audio.stopCall();
    await _ch.invokeMethod('stopPlayback');
    state = const RoomState();
  }

  void setMicGain(double gain) {
    _audio.setMicGain(gain);
  }

  void setVox({required bool enabled, required double threshold}) {
    _audio.setVox(enabled: enabled, threshold: threshold);
  }

  Future<void> setNoiseLevel(int level) async {
    await _audio.recorder.stop();
    final stream = await _audio.recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: level > 0,
        autoGain: level > 1,
      ),
    );
    stream.listen((chunk) {
      if (state.globalMuted) return;
      final gained = _audio.applyGain(chunk, _audio.micGain);
      if (!_audio.shouldTransmit(gained)) return;
      _room.sendAudio(Uint8List.fromList(gained));
    });
  }

  void setLowPowerMode(bool enabled) {
    _room.setLowPowerMode(enabled);
  }

  void startAutoReconnect() {
    _room.startAutoReconnect();
  }

  void setMemberEventCallback(void Function(String name, bool joined) cb) {
    _room.onMemberEvent = cb;
  }

  Future<List<RoomInfo>> discoverRooms() async {
    final raw = await RoomService.discoverRooms();
    return raw
        .map(
          (r) => RoomInfo(
            code: r['code']!,
            hostIp: r['ip']!,
            hostName: r['name']!.isNotEmpty ? r['name'] : null,
            hostAvatarBase64: r['avatar']!.isNotEmpty ? r['avatar'] : null,
          ),
        )
        .toList();
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(
  RoomNotifier.new,
);
