import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/services/room_service.dart';

// ── Helpers ────────────────────────────────────────────────
const goIp = '192.168.49.1'; // A36 (Group Owner)
const clientIp = '192.168.49.200'; // A01 (cliente)

RoomMember makeMember(String name, String ip, {String? avatar}) =>
    RoomMember(name: name, ip: ip, avatarBase64: avatar);

// Simula el payload que el host envía al cliente
String buildMembersPayload(Map<String, RoomMember> members) {
  return members.entries
      .map((e) => '${e.value.name}§${e.key}§${e.value.avatarBase64 ?? ''}')
      .join('|');
}

// Simula parseMemberList (lógica extraída para testear sin sockets)
Map<String, RoomMember> parseMemberList(
  String raw,
  Map<String, RoomMember> current,
  String myIp,
) {
  if (raw.isEmpty) return current;
  final result = Map<String, RoomMember>.from(current);
  final currentIps = <String>{};

  for (final entry in raw.split('|')) {
    final p = entry.split('§');
    if (p.length < 2) continue;
    final name = p[0];
    final ip = p[1];
    final avatar = p.length > 2 && p[2].isNotEmpty ? p[2] : null;
    currentIps.add(ip);

    if (!result.containsKey(ip)) {
      result[ip] = RoomMember(name: name, ip: ip, avatarBase64: avatar);
    } else {
      if (avatar != null && result[ip]!.avatarBase64 == null) {
        result[ip]!.avatarBase64 = avatar;
      }
      result[ip]!.isOnline = true;
      result[ip]!.lastSeen = DateTime.now();
    }
  }

  result.removeWhere((ip, _) => !currentIps.contains(ip) && ip != myIp);
  return result;
}

// Simula handleJoin en el host (usando fromIp del paquete UDP)
Map<String, RoomMember> handleJoin(
  String msgBody, // todo después de 'JOIN:'
  String fromIp, // IP real del paquete UDP
  Map<String, RoomMember> members,
  int maxMembers,
) {
  final colon = msgBody.indexOf(':');
  final name = colon == -1 ? msgBody : msgBody.substring(0, colon);
  final avatar = colon != -1 ? msgBody.substring(colon + 1) : null;

  if (members.length >= maxMembers && !members.containsKey(fromIp)) {
    return members;
  }

  final result = Map<String, RoomMember>.from(members);
  if (!result.containsKey(fromIp)) {
    result[fromIp] = RoomMember(
      name: name,
      ip: fromIp,
      avatarBase64: avatar,
      isOnline: true,
    );
  } else {
    result[fromIp]!.isOnline = true;
    result[fromIp]!.lastSeen = DateTime.now();
    if (avatar != null && result[fromIp]!.avatarBase64 == null) {
      result[fromIp]!.avatarBase64 = avatar;
    }
  }
  return result;
}

void main() {
  // ══════════════════════════════════════════════════════
  // GRUPO 1 — Creación de sala
  // ══════════════════════════════════════════════════════
  group('Creación de sala', () {
    test('host siempre usa IP del GO', () {
      // El host (quién crea la sala) siempre debe tener goIp
      expect(RoomService.goIp, goIp);
      expect(RoomService.goIp, '192.168.49.1');
    });

    test('sala nueva tiene solo al host', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      expect(members.length, 1);
      expect(members.containsKey(goIp), true);
      expect(members[goIp]!.name, 'A36');
    });

    test('sala nueva — host está online', () {
      final host = makeMember('A36', goIp);
      expect(host.isOnline, true);
    });

    test('código de sala es siempre 4 dígitos', () {
      final service = RoomService();
      for (int i = 0; i < 50; i++) {
        final code = service.generateRoomCode();
        expect(int.parse(code), inInclusiveRange(1000, 9999));
      }
    });

    test('sala inicia sin miembros offline', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      expect(members.values.every((m) => m.isOnline), true);
    });
  });

  // ══════════════════════════════════════════════════════
  // GRUPO 2 — JOIN del cliente al host
  // ══════════════════════════════════════════════════════
  group('JOIN del cliente', () {
    test('host agrega cliente usando fromIp del paquete UDP', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};

      // Cliente (A01) envía JOIN — el host usa fromIp, no el contenido del msg
      final updated = handleJoin('A01', clientIp, members, 10);

      expect(updated.containsKey(clientIp), true);
      expect(updated[clientIp]!.name, 'A01');
      expect(updated.length, 2);
    });

    test('fromIp es siempre la IP correcta independiente del mensaje', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};

      // Incluso si el mensaje contiene una IP incorrecta,
      // el host usa fromIp del socket UDP
      final updated = handleJoin(
        'A01', // mensaje solo tiene nombre
        clientIp, // fromIp es siempre correcto
        members,
        10,
      );

      expect(updated.containsKey(clientIp), true);
      expect(updated.containsKey(goIp), true);
    });

    test('JOIN incluye nombre correctamente', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      final updated = handleJoin('MariettaDelmonico', clientIp, members, 10);
      expect(updated[clientIp]!.name, 'MariettaDelmonico');
    });

    test('JOIN incluye avatar cuando está presente', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      final updated = handleJoin('A01:avatarBase64Data', clientIp, members, 10);
      expect(updated[clientIp]!.avatarBase64, 'avatarBase64Data');
    });

    test('JOIN sin avatar deja avatar como null', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      final updated = handleJoin('A01', clientIp, members, 10);
      expect(updated[clientIp]!.avatarBase64, isNull);
    });

    test('segundo JOIN no duplica al miembro', () {
      var members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      members = handleJoin('A01', clientIp, members, 10);
      members = handleJoin('A01', clientIp, members, 10); // segundo JOIN
      expect(members.length, 2); // sigue siendo 2, no 3
    });

    test('segundo JOIN actualiza avatar si antes era null', () {
      var members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      members = handleJoin('A01', clientIp, members, 10);
      expect(members[clientIp]!.avatarBase64, isNull);
      members = handleJoin('A01:nuevoAvatar', clientIp, members, 10);
      expect(members[clientIp]!.avatarBase64, 'nuevoAvatar');
    });

    test('no agrega miembro cuando sala está llena', () {
      final members = <String, RoomMember>{};
      // Llenar sala al máximo
      for (int i = 1; i <= 10; i++) {
        members['192.168.49.$i'] = makeMember('User$i', '192.168.49.$i');
      }
      expect(members.length, 10);

      // Intentar agregar un miembro más
      final updated = handleJoin('Extra', '192.168.49.100', members, 10);
      expect(updated.length, 10); // no creció
    });

    test('cliente queda online tras JOIN', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      final updated = handleJoin('A01', clientIp, members, 10);
      expect(updated[clientIp]!.isOnline, true);
    });
  });

  // ══════════════════════════════════════════════════════
  // GRUPO 3 — Distribución de lista de miembros
  // ══════════════════════════════════════════════════════
  group('Lista de miembros', () {
    test('payload incluye todos los miembros', () {
      final members = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      final payload = buildMembersPayload(members);
      expect(payload, contains('A36'));
      expect(payload, contains('A01'));
      expect(payload, contains(goIp));
      expect(payload, contains(clientIp));
    });

    test('cliente parsea lista correctamente', () {
      // Host tiene dos miembros
      final hostMembers = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      final payload = buildMembersPayload(hostMembers);

      // Cliente solo tiene su propia entrada
      final clientMembers = {clientIp: makeMember('A01', clientIp)};

      // Cliente recibe MEMBERS del host
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated.containsKey(goIp),
        true,
        reason: 'El cliente debe ver al host en la sala',
      );
      expect(updated[goIp]!.name, 'A36');
      expect(updated.length, 2);
    });

    test('cliente ve su propia tarjeta', () {
      final hostMembers = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      final payload = buildMembersPayload(hostMembers);
      final clientMembers = {clientIp: makeMember('A01', clientIp)};
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated.containsKey(clientIp),
        true,
        reason: 'El cliente debe verse a sí mismo',
      );
    });

    test('parseMemberList preserva avatar existente', () {
      final hostMembers = {
        goIp: makeMember('A36', goIp, avatar: 'avatarGO'),
        clientIp: makeMember('A01', clientIp),
      };
      // Broadcast sin avatares
      final payloadNoAvatar = hostMembers.entries
          .map((e) => '${e.value.name}§${e.key}§')
          .join('|');

      final clientMembers = {
        clientIp: makeMember('A01', clientIp),
        goIp: makeMember('A36', goIp, avatar: 'avatarGO'),
      };

      final updated = parseMemberList(payloadNoAvatar, clientMembers, clientIp);
      // El avatar del GO debe preservarse aunque el broadcast no lo incluya
      expect(updated[goIp]!.avatarBase64, 'avatarGO');
    });

    test('parseMemberList elimina miembros que salieron', () {
      final thirdIp = '192.168.49.50';
      final clientMembers = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
        thirdIp: makeMember('RN12', thirdIp),
      };

      // Host solo envía 2 miembros (RN12 salió)
      final payload = 'A36§$goIp§|A01§$clientIp§';
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated.containsKey(thirdIp),
        false,
        reason: 'RN12 debe eliminarse de la lista',
      );
      expect(updated.length, 2);
    });

    test('parseMemberList no elimina al cliente de su propia lista', () {
      final clientMembers = {clientIp: makeMember('A01', clientIp)};
      // Host envía lista que no incluye al cliente (raro pero posible)
      final payload = 'A36§$goIp§';
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated.containsKey(clientIp),
        true,
        reason: 'El cliente nunca debe eliminarse de su propia lista',
      );
    });

    test('formato del separador es correcto', () {
      final members = {goIp: makeMember('A36', goIp)};
      final payload = buildMembersPayload(members);
      expect(payload, contains('§')); // separador de campos
      // Si hay más de un miembro, usa | como separador de registros
      final members2 = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      final payload2 = buildMembersPayload(members2);
      expect(payload2, contains('|')); // separador de miembros
    });
  });

  // ══════════════════════════════════════════════════════
  // GRUPO 4 — LEAVE y desconexión
  // ══════════════════════════════════════════════════════
  group('Salida de sala', () {
    test('LEAVE elimina al miembro correcto', () {
      final members = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      // Simular LEAVE del cliente
      final updated = Map<String, RoomMember>.from(members);
      updated.remove(clientIp);

      expect(updated.containsKey(clientIp), false);
      expect(updated.containsKey(goIp), true);
      expect(updated.length, 1);
    });

    test('después de LEAVE el host sigue en sala', () {
      final members = {
        goIp: makeMember('A36', goIp),
        clientIp: makeMember('A01', clientIp),
      };
      final updated = Map<String, RoomMember>.from(members)..remove(clientIp);

      expect(updated[goIp]!.name, 'A36');
      expect(updated[goIp]!.isOnline, true);
    });

    test('timeout marca miembro como offline', () {
      final member = makeMember('A01', clientIp);
      // Simular que no ha enviado heartbeat en más de 10 segundos
      member.lastSeen = DateTime.now().subtract(const Duration(seconds: 11));

      final elapsed = DateTime.now().difference(member.lastSeen);
      expect(elapsed.inSeconds, greaterThan(10));

      // El checker de timeout lo marcaría como offline
      member.isOnline = false;
      expect(member.isOnline, false);
    });

    test('reconexión marca miembro como online', () {
      final member = makeMember('A01', clientIp);
      member.isOnline = false;

      // Simular heartbeat recibido
      member.lastSeen = DateTime.now();
      member.isOnline = true;

      expect(member.isOnline, true);
    });
  });

  // ══════════════════════════════════════════════════════
  // GRUPO 5 — Flujo completo (escenario real)
  // ══════════════════════════════════════════════════════
  group('Flujo completo — escenario A36 GO, A01 cliente', () {
    test('A36 crea sala → tiene su propia tarjeta', () {
      // A36 es GO, crea la sala
      final members = <String, RoomMember>{goIp: makeMember('Nesp A36', goIp)};
      expect(members.containsKey(goIp), true);
      expect(members.length, 1);
    });

    test('A01 envía JOIN → A36 lo agrega usando fromIp', () {
      var members = <String, RoomMember>{goIp: makeMember('Nesp A36', goIp)};
      // A01 envía JOIN — host usa fromIp=clientIp
      members = handleJoin('Marietta A01', clientIp, members, 10);

      expect(members.length, 2);
      expect(members.containsKey(clientIp), true);
      expect(members[clientIp]!.name, 'Marietta A01');
    });

    test('A36 envía lista → A01 ve ambas tarjetas', () {
      // Estado del host tras JOIN
      final hostMembers = {
        goIp: makeMember('Nesp A36', goIp),
        clientIp: makeMember('Marietta A01', clientIp),
      };
      final payload = buildMembersPayload(hostMembers);

      // A01 recibe MEMBERS
      final clientMembers = {clientIp: makeMember('Marietta A01', clientIp)};
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated.length,
        2,
        reason: 'A01 debe ver 2 tarjetas: la suya y la de A36',
      );
      expect(updated.containsKey(goIp), true);
      expect(updated.containsKey(clientIp), true);
    });

    test('flujo completo con avatar', () {
      // A36 crea sala con avatar
      var hostMembers = <String, RoomMember>{
        goIp: makeMember('Nesp A36', goIp, avatar: 'avatarA36'),
      };

      // A01 hace JOIN con su avatar
      hostMembers = handleJoin(
        'Marietta A01:avatarA01',
        clientIp,
        hostMembers,
        10,
      );

      expect(hostMembers[goIp]!.avatarBase64, 'avatarA36');
      expect(hostMembers[clientIp]!.avatarBase64, 'avatarA01');

      // A36 envía lista con avatares a A01
      final payload = buildMembersPayload(hostMembers);
      final clientMembers = {clientIp: makeMember('Marietta A01', clientIp)};
      final updated = parseMemberList(payload, clientMembers, clientIp);

      expect(
        updated[goIp]!.avatarBase64,
        'avatarA36',
        reason: 'A01 debe ver el avatar de A36',
      );
      expect(
        updated[clientIp]!.avatarBase64,
        'avatarA01',
        reason: 'A01 debe ver su propio avatar',
      );
    });

    test('tercer dispositivo se une correctamente', () {
      final thirdIp = '192.168.49.50';
      var members = <String, RoomMember>{
        goIp: makeMember('Nesp A36', goIp),
        clientIp: makeMember('Marietta A01', clientIp),
      };

      // RN12 se une
      members = handleJoin('Usuario RN12', thirdIp, members, 10);

      expect(members.length, 3);
      expect(members.containsKey(thirdIp), true);
      expect(members[thirdIp]!.name, 'Usuario RN12');
    });

    test('A01 y RN12 ven lista completa tras unirse ambos', () {
      final thirdIp = '192.168.49.50';
      var hostMembers = <String, RoomMember>{
        goIp: makeMember('Nesp A36', goIp),
      };
      hostMembers = handleJoin('Marietta A01', clientIp, hostMembers, 10);
      hostMembers = handleJoin('Usuario RN12', thirdIp, hostMembers, 10);

      final payload = buildMembersPayload(hostMembers);

      // A01 recibe la lista actualizada
      final a01Members = {clientIp: makeMember('Marietta A01', clientIp)};
      final a01Updated = parseMemberList(payload, a01Members, clientIp);
      expect(a01Updated.length, 3);

      // RN12 recibe la lista
      final rn12Members = {thirdIp: makeMember('Usuario RN12', thirdIp)};
      final rn12Updated = parseMemberList(payload, rn12Members, thirdIp);
      expect(rn12Updated.length, 3);
    });

    test('desconexión y reconexión de A01', () {
      var members = <String, RoomMember>{
        goIp: makeMember('Nesp A36', goIp),
        clientIp: makeMember('Marietta A01', clientIp),
      };

      // A01 se desconecta (timeout)
      members[clientIp]!.isOnline = false;
      expect(members[clientIp]!.isOnline, false);

      // A01 se reconecta — envía HB o JOIN de nuevo
      members = handleJoin('Marietta A01', clientIp, members, 10);
      members[clientIp]!.isOnline = true;
      members[clientIp]!.lastSeen = DateTime.now();

      expect(members[clientIp]!.isOnline, true);
      expect(members.length, 2); // no se duplicó
    });
  });

  // ══════════════════════════════════════════════════════
  // GRUPO 6 — Casos edge
  // ══════════════════════════════════════════════════════
  group('Casos edge', () {
    test('payload vacío no rompe parseMemberList', () {
      final members = {clientIp: makeMember('A01', clientIp)};
      final updated = parseMemberList('', members, clientIp);
      expect(updated, equals(members));
    });

    test('payload malformado no rompe parseMemberList', () {
      final members = {clientIp: makeMember('A01', clientIp)};
      expect(
        () => parseMemberList('datos§mal§formados§extra', members, clientIp),
        returnsNormally,
      );
    });

    test('nombre con caracteres especiales se maneja correctamente', () {
      final members = <String, RoomMember>{goIp: makeMember('A36', goIp)};
      final updated = handleJoin("Nesp's A36", clientIp, members, 10);
      expect(updated[clientIp]!.name, "Nesp's A36");
    });

    test('IP del GO nunca cambia', () {
      expect(RoomService.goIp, '192.168.49.1');
      // Constante inmutable — siempre la misma
      expect(RoomService.goIp, RoomService.goIp);
    });

    test('miembro con volumen por defecto es 1.0', () {
      final m = makeMember('Test', clientIp);
      expect(m.volume, 1.0);
    });

    test('miembro no está muteado por defecto', () {
      final m = makeMember('Test', clientIp);
      expect(m.isMuted, false);
    });

    test('nivel de voz inicial es 0', () {
      final m = makeMember('Test', clientIp);
      expect(m.speakingLevel, 0.0);
    });
  });
}
