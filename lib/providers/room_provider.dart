import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/services/room_service.dart';
import 'package:intercom_app/services/audio_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class RoomNotifier extends Notifier<RoomState> {
  final RoomService _room = RoomService();
  static const _ch = MethodChannel('com.example.intercom_app/audio');
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
    final code = _room.generateRoomCode();
    await _ch.invokeMethod('startPlayback');

    _room.onAudioReceived = (data) {
      _ch.invokeMethod('playChunk', {'data': data});
    };

    _room.onMembersChanged = (members) {
      state = state.copyWith(members: members);
    };

    await _room.createRoom(_myName, _myIp);

    // Capturar micrófono para la sala
    final audioService = AudioService();
    await audioService.startCall(remoteIp: '127.0.0.1', remotePort: 5560);
    audioService.onAudioChunk = (chunk) {
      _room.sendAudio(Uint8List.fromList(chunk));
    };

    state = state.copyWith(
      status: RoomStatus.hosting,
      roomCode: code,
      isHost: true,
      members: _room.members,
    );
  }

  Future<void> joinRoom(String hostIp) async {
    await _ch.invokeMethod('startPlayback');

    _room.onAudioReceived = (data) {
      _ch.invokeMethod('playChunk', {'data': data});
    };

    _room.onMembersChanged = (members) {
      state = state.copyWith(members: members);
    };

    await _room.joinRoom(_myName, _myIp, hostIp);

    state = state.copyWith(
      status: RoomStatus.joined,
      isHost: false,
      members: _room.members,
    );
  }

  void sendAudio(List<int> chunk) {
    _room.sendAudio(chunk is List<int> ? chunk as dynamic : chunk);
  }

  Future<void> leaveRoom() async {
    _room.leaveRoom(_myIp);
    await _ch.invokeMethod('stopPlayback');
    state = const RoomState();
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(
  RoomNotifier.new,
);
