import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/services/room_service.dart';

void main() {
  group('RoomState — estado inicial', () {
    test('estado inicial es idle', () {
      const state = RoomState();
      expect(state.status, RoomStatus.idle);
      expect(state.roomCode, isNull);
      expect(state.members, isEmpty);
      expect(state.isHost, false);
      expect(state.globalMuted, false);
    });
  });

  group('RoomState — copyWith', () {
    test('copyWith cambia solo el campo indicado', () {
      const state = RoomState();
      final updated = state.copyWith(
        status: RoomStatus.hosting,
        roomCode: '1234',
        isHost: true,
      );
      expect(updated.status, RoomStatus.hosting);
      expect(updated.roomCode, '1234');
      expect(updated.isHost, true);
      expect(updated.globalMuted, false); // no cambió
      expect(updated.members, isEmpty); // no cambió
    });

    test('copyWith con globalMuted', () {
      const state = RoomState();
      final muted = state.copyWith(globalMuted: true);
      expect(muted.globalMuted, true);
      expect(muted.status, RoomStatus.idle); // no cambió
    });

    test('copyWith con members', () {
      const state = RoomState();
      final members = {
        '192.168.49.2': RoomMember(name: 'Nesp', ip: '192.168.49.2'),
        '192.168.49.3': RoomMember(name: 'Marietta', ip: '192.168.49.3'),
      };
      final updated = state.copyWith(members: members);
      expect(updated.members.length, 2);
      expect(updated.members['192.168.49.2']?.name, 'Nesp');
    });

    test('copyWith sin parámetros no cambia nada', () {
      final state = RoomState(
        status: RoomStatus.joined,
        roomCode: '5678',
        isHost: false,
        globalMuted: true,
      );
      final same = state.copyWith();
      expect(same.status, state.status);
      expect(same.roomCode, state.roomCode);
      expect(same.isHost, state.isHost);
      expect(same.globalMuted, state.globalMuted);
    });
  });

  group('RoomStatus — valores', () {
    test('existen los tres estados necesarios', () {
      expect(RoomStatus.values, contains(RoomStatus.idle));
      expect(RoomStatus.values, contains(RoomStatus.hosting));
      expect(RoomStatus.values, contains(RoomStatus.joined));
    });
  });
}
