import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/services/room_service.dart';

void main() {
  group('RoomService — generación de código', () {
    test('genera código de 4 dígitos', () {
      final service = RoomService();
      for (int i = 0; i < 100; i++) {
        final code = service.generateRoomCode();
        expect(
          code.length,
          4,
          reason: 'El código debe tener exactamente 4 dígitos',
        );
        expect(
          int.tryParse(code),
          isNotNull,
          reason: 'El código debe ser numérico',
        );
        expect(int.parse(code), greaterThanOrEqualTo(1000));
        expect(int.parse(code), lessThanOrEqualTo(9999));
      }
    });

    test('genera códigos distintos en ejecuciones consecutivas', () {
      final service = RoomService();
      final codes = List.generate(20, (_) => service.generateRoomCode());
      final unique = codes.toSet();
      expect(
        unique.length,
        greaterThan(1),
        reason: 'Los códigos no deben ser todos iguales',
      );
    });
  });

  group('RoomMember — creación y valores por defecto', () {
    test('crea miembro con valores correctos', () {
      final m = RoomMember(name: 'Nesp', ip: '192.168.49.2');
      expect(m.name, 'Nesp');
      expect(m.ip, '192.168.49.2');
      expect(m.isMuted, false);
      expect(m.volume, 1.0);
      expect(m.speakingLevel, 0.0);
      expect(m.isOnline, true);
      expect(m.avatarBase64, isNull);
    });

    test('crea miembro con avatar', () {
      final m = RoomMember(
        name: 'Marietta',
        ip: '192.168.49.3',
        avatarBase64: 'abc123',
      );
      expect(m.avatarBase64, 'abc123');
    });

    test('lastSeen se inicializa al momento de creación', () {
      final before = DateTime.now();
      final m = RoomMember(name: 'Test', ip: '192.168.49.5');
      final after = DateTime.now();
      expect(
        m.lastSeen.isAfter(before) || m.lastSeen.isAtSameMomentAs(before),
        true,
      );
      expect(
        m.lastSeen.isBefore(after) || m.lastSeen.isAtSameMomentAs(after),
        true,
      );
    });
  });

  group('RoomService — constantes', () {
    test('puertos UDP correctos', () {
      expect(RoomService.audioPort, 5560);
      expect(RoomService.signalPort, 5561);
      expect(RoomService.announcePort, 5562);
    });

    test('GO IP correcta', () {
      expect(RoomService.goIp, '192.168.49.1');
    });

    test('máximo de miembros definido', () {
      expect(RoomService.maxMembers, greaterThan(0));
      expect(RoomService.maxMembers, lessThanOrEqualTo(20));
    });
  });

  group('RoomService — estado inicial', () {
    test('no es host al crear instancia', () {
      final service = RoomService();
      expect(service.isHost, false);
    });

    test('mapa de miembros vacío al inicio', () {
      final service = RoomService();
      expect(service.members, isEmpty);
    });
  });
}
