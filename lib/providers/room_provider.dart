import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/services/room_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intercom_app/services/audio_service.dart';
import 'package:record/record.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
    _myIp = await NetworkInfo().getWifiIP() ?? '';
    final info = await DeviceInfoPlugin().androidInfo;
    _myName = info.model;
  }

  Future<void> createRoom() async {
    await _init();
    final code = _room.generateRoomCode();
    await _ch.invokeMethod('startPlayback');

    _room.onAudioReceived = (data, fromIp) {
      final member = _room.members[fromIp];
      if (member == null || member.isMuted) return;
      // Aplicar volumen individual
      final adjusted = _applyVolume(data, member.volume);
      _ch.invokeMethod('playChunk', {'data': adjusted});
    };

    _room.onMembersChanged = (members) {
      state = state.copyWith(members: Map.from(members));
    };

    final avatarBase64 = await _loadAvatarBase64();
    await _room.createRoom(_myName, _myIp, avatarBase64: avatarBase64);
    _room.announceRoom(code);

    _room.onRoomQuery = (queryCode, fromIp) {
      if (queryCode == code) {
        // Responder directamente al que pregunta
        _room.respondToQuery(fromIp, code);
      }
    };

    // Capturar micrófono y enviar en mesh
    await _startAudioCapture();

    state = state.copyWith(
      status: RoomStatus.hosting,
      roomCode: code,
      isHost: true,
      members: Map.from(_room.members),
    );
  }

  Future<void> joinRoom(String hostIp) async {
    await _init();
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

    state = state.copyWith(
      status: RoomStatus.joined,
      isHost: false,
      members: Map.from(_room.members),
    );
  }

  Future<void> joinRoomByCode(String code) async {
    final hostIp = await RoomService.findRoomHost(code);
    if (hostIp == null) return;
    await joinRoom(hostIp);
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

      // Aplicar ganancia
      final gained = _audio.applyGain(chunk, _audio.micGain);

      // Aplicar VOX
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
    // Reiniciar el stream con nueva configuración de ruido
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

  Future<String?> _loadAvatarBase64() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/avatar.jpg');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final limited = bytes.length > 20000 ? bytes.sublist(0, 20000) : bytes;
      return base64Encode(limited);
    } catch (_) {
      return null;
    }
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(
  RoomNotifier.new,
);
