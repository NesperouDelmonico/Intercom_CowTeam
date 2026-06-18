// room_state.dart — no depende de room_service ni audio_service

enum RoomStatus { idle, hosting, joined }

class RoomMember {
  final String name;
  final String ip;
  bool isMuted;
  double volume;
  double speakingLevel;
  String? avatarBase64;
  bool isOnline;
  DateTime lastSeen;

  RoomMember({
    required this.name,
    required this.ip,
    this.isMuted = false,
    this.volume = 1.0,
    this.speakingLevel = 0.0,
    this.avatarBase64,
    this.isOnline = true,
  }) : lastSeen = DateTime.now();
}

class RoomState {
  final RoomStatus status;
  final String? roomCode;
  final Map<String, RoomMember> members;
  final bool isHost;
  final bool globalMuted;

  const RoomState({
    this.status = RoomStatus.idle,
    this.roomCode,
    this.members = const {},
    this.isHost = false,
    this.globalMuted = false,
  });

  RoomState copyWith({
    RoomStatus? status,
    String? roomCode,
    Map<String, RoomMember>? members,
    bool? isHost,
    bool? globalMuted,
  }) {
    return RoomState(
      status: status ?? this.status,
      roomCode: roomCode ?? this.roomCode,
      members: members ?? this.members,
      isHost: isHost ?? this.isHost,
      globalMuted: globalMuted ?? this.globalMuted,
    );
  }
}
