import 'package:intercom_app/models/device.dart';

enum RoomStatus { idle, hosting, joined }

class RoomState {
  final RoomStatus status;
  final String? roomCode;
  final List<Device> members;
  final bool isHost;

  const RoomState({
    this.status = RoomStatus.idle,
    this.roomCode,
    this.members = const [],
    this.isHost = false,
  });

  RoomState copyWith({
    RoomStatus? status,
    String? roomCode,
    List<Device>? members,
    bool? isHost,
  }) {
    return RoomState(
      status: status ?? this.status,
      roomCode: roomCode ?? this.roomCode,
      members: members ?? this.members,
      isHost: isHost ?? this.isHost,
    );
  }
}
