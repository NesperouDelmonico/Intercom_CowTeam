import 'package:intercom_app/services/room_service.dart';

enum RoomStatus { idle, hosting, joined }

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
