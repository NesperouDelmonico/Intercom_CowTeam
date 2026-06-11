import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:intercom_app/models/device.dart';
import 'package:network_info_plus/network_info_plus.dart';

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

  Device toDevice() => Device(name: name, ip: ip, port: RoomService.audioPort);
}

class RoomService {
  static const int audioPort = 5560;
  static const int signalPort = 5561;
  static const int announcePort = 5562;
  static const int maxMembers = 10;

  static const Duration _memberTimeout = Duration(seconds: 10);
  static const Duration _heartbeatInterval = Duration(seconds: 3);
  static const Duration _heartbeatLowPower = Duration(seconds: 8);
  static const Duration _reconnectInterval = Duration(seconds: 5);

  RawDatagramSocket? _audioSocket;
  RawDatagramSocket? _signalSocket;
  RawDatagramSocket? _announceSocket;

  final Map<String, RoomMember> _members = {};
  bool _isHost = false;
  String? _hostIp;
  String _myIp = '';
  String _myName = '';
  String? _myAvatarBase64;
  String? _roomCode;

  Timer? _heartbeatTimer;
  Timer? _announceTimer;
  Timer? _timeoutTimer;
  Timer? _reconnectTimer;

  bool _lowPowerMode = false;
  bool _running = false;

  void Function(Map<String, RoomMember> members)? onMembersChanged;
  void Function(Uint8List audio, String fromIp)? onAudioReceived;
  void Function(String code, String fromIp)? onRoomQuery;
  void Function(String memberName, bool joined)? onMemberEvent;

  Map<String, RoomMember> get members => Map.unmodifiable(_members);
  bool get isHost => _isHost;

  String generateRoomCode() => (1000 + Random().nextInt(9000)).toString();

  Future<void> createRoom(
    String myName,
    String myIp, {
    String? avatarBase64,
  }) async {
    _isHost = true;
    _myIp = myIp;
    _myName = myName;
    _myAvatarBase64 = avatarBase64;
    _running = true;

    _members[myIp] = RoomMember(
      name: myName,
      ip: myIp,
      avatarBase64: avatarBase64,
    );

    await _bindSockets();
    _listenSignals();
    _listenAudio();
    _startTimeoutChecker();
    _startAnnounce();
  }

  Future<void> joinRoom(
    String myName,
    String myIp,
    String hostIp, {
    String? avatarBase64,
  }) async {
    _isHost = false;
    _myIp = myIp;
    _myName = myName;
    _myAvatarBase64 = avatarBase64;
    _hostIp = hostIp;
    _running = true;

    await _bindSockets();
    _listenSignals();
    _listenAudio();

    final avatarPart = avatarBase64 != null ? ':$avatarBase64' : '';
    for (int i = 0; i < 5; i++) {
      _sendSignal('JOIN:$myName:$myIp$avatarPart', hostIp);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _startHeartbeat();
  }

  Future<void> _bindSockets() async {
    _audioSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      audioPort,
      reuseAddress: true,
    );
    _signalSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      signalPort,
      reuseAddress: true,
    );
  }

  void _listenAudio() {
    _audioSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _audioSocket!.receive();
        if (dg == null) return;
        final fromIp = dg.address.address;
        _updateSpeakingLevel(fromIp, dg.data);
        onAudioReceived?.call(dg.data, fromIp);
      }
    });
  }

  void _listenSignals() {
    _signalSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _signalSocket!.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        final fromIp = dg.address.address;
        _handleSignal(msg, fromIp);
      }
    });
  }

  void _handleSignal(String msg, String fromIp) {
    if (msg.startsWith('JOIN:')) {
      _handleJoin(msg, fromIp);
    } else if (msg.startsWith('LEAVE:')) {
      _handleLeave(msg.split(':')[1]);
    } else if (msg.startsWith('MEMBERS:')) {
      if (!_isHost) _parseMemberList(msg.substring(8));
    } else if (msg.startsWith('MUTE:')) {
      _handleMute(msg);
    } else if (msg.startsWith('HEARTBEAT:')) {
      _handleHeartbeat(msg, fromIp);
    } else if (msg.startsWith('ROOM_QUERY:')) {
      final queryCode = msg.split(':')[1];
      if (queryCode == '*' || queryCode == _roomCode) {
        onRoomQuery?.call(queryCode, fromIp);
      }
    } else if (msg.startsWith('RECONNECT:')) {
      _handleReconnect(msg, fromIp);
    }
  }

  void _handleJoin(String msg, String fromIp) {
    final firstColon = msg.indexOf(':');
    final secondColon = msg.indexOf(':', firstColon + 1);
    final thirdColon = msg.indexOf(':', secondColon + 1);

    if (secondColon == -1) return;
    final name = msg.substring(firstColon + 1, secondColon);
    final ip = thirdColon == -1
        ? msg.substring(secondColon + 1)
        : msg.substring(secondColon + 1, thirdColon);
    final avatarBase64 = thirdColon != -1
        ? msg.substring(thirdColon + 1)
        : null;

    if (_members.length >= maxMembers && !_members.containsKey(ip)) return;

    final isRejoin = _members.containsKey(ip);
    _members[ip] = RoomMember(
      name: name,
      ip: ip,
      avatarBase64: avatarBase64,
      isOnline: true,
    );

    if (!isRejoin) onMemberEvent?.call(name, true);

    onMembersChanged?.call(_members);
    _broadcastMemberList(includeAvatars: false);
    _sendMemberListTo(ip);
  }

  void _handleLeave(String ip) {
    final member = _members[ip];
    if (member != null) {
      onMemberEvent?.call(member.name, false);
      _members.remove(ip);
      onMembersChanged?.call(_members);
      if (_isHost) _broadcastMemberList();
    }
  }

  void _handleMute(String msg) {
    final parts = msg.split(':');
    if (parts.length < 3) return;
    final ip = parts[1];
    final muted = parts[2] == '1';
    if (_members.containsKey(ip)) {
      _members[ip]!.isMuted = muted;
      onMembersChanged?.call(_members);
    }
  }

  void _handleHeartbeat(String msg, String fromIp) {
    if (_members.containsKey(fromIp)) {
      final wasOffline = !_members[fromIp]!.isOnline;
      _members[fromIp]!.lastSeen = DateTime.now();
      _members[fromIp]!.isOnline = true;
      if (wasOffline) {
        onMemberEvent?.call(_members[fromIp]!.name, true);
        onMembersChanged?.call(_members);
        if (_isHost) _broadcastMemberList();
      }
    } else if (_isHost) {
      final parts = msg.split(':');
      if (parts.length >= 3) {
        final name = parts[1];
        final ip = parts[2];
        _members[ip] = RoomMember(name: name, ip: ip, isOnline: true);
        onMemberEvent?.call(name, true);
        onMembersChanged?.call(_members);
        _broadcastMemberList();
        _sendMemberListTo(ip);
      }
    }
  }

  void _handleReconnect(String msg, String fromIp) {
    final parts = msg.split(':');
    if (parts.length < 3) return;
    final name = parts[1];
    final ip = parts[2];
    if (_isHost) {
      _members[ip] = RoomMember(name: name, ip: ip, isOnline: true);
      onMemberEvent?.call(name, true);
      onMembersChanged?.call(_members);
      _broadcastMemberList();
      _sendMemberListTo(ip);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    final interval = _lowPowerMode ? _heartbeatLowPower : _heartbeatInterval;
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (_hostIp != null) {
        _sendSignal('HEARTBEAT:$_myName:$_myIp', _hostIp!);
      }
    });
  }

  void setLowPowerMode(bool enabled) {
    _lowPowerMode = enabled;
    if (!_isHost) _startHeartbeat();
  }

  void _startTimeoutChecker() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      bool changed = false;
      for (final member in _members.values) {
        if (member.ip == _myIp) continue;
        final elapsed = now.difference(member.lastSeen);
        if (elapsed > _memberTimeout && member.isOnline) {
          member.isOnline = false;
          onMemberEvent?.call(member.name, false);
          changed = true;
        }
      }
      if (changed) onMembersChanged?.call(_members);
    });
  }

  void startAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(_reconnectInterval, (_) async {
      if (_hostIp == null || !_running) return;
      final newIp = await _getActiveIp();
      if (newIp != _myIp && newIp.isNotEmpty) {
        _myIp = newIp;
        await _rebindSockets();
      }
      _sendSignal('RECONNECT:$_myName:$_myIp', _hostIp!);
    });
  }

  Future<void> _rebindSockets() async {
    _audioSocket?.close();
    _signalSocket?.close();
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _bindSockets();
      _listenSignals();
      _listenAudio();
    } catch (_) {}
  }

  Future<String> _getActiveIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              addr.address != '0.0.0.0' &&
              addr.address.startsWith('192.168.49.')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address != '0.0.0.0') {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  void _broadcastMemberList({bool includeAvatars = false}) {
    final payload = _members.entries
        .map((e) {
          final avatar = includeAvatars ? (e.value.avatarBase64 ?? '') : '';
          return '${e.value.name}§${e.key}§$avatar';
        })
        .join('|');
    final msg = 'MEMBERS:$payload';
    for (final ip in _members.keys) {
      if (ip != _myIp) _sendSignal(msg, ip);
    }
  }

  void _sendMemberListTo(String ip) {
    final payload = _members.entries
        .map((e) => '${e.value.name}§${e.key}§${e.value.avatarBase64 ?? ''}')
        .join('|');
    _sendSignal('MEMBERS:$payload', ip);
  }

  void _parseMemberList(String raw) {
    if (raw.isEmpty) return;
    final currentIps = <String>{};
    for (final entry in raw.split('|')) {
      final p = entry.split('§');
      if (p.length < 2) continue;
      final name = p[0];
      final ip = p[1];
      final avatarBase64 = p.length > 2 && p[2].isNotEmpty ? p[2] : null;
      currentIps.add(ip);
      if (!_members.containsKey(ip)) {
        _members[ip] = RoomMember(
          name: name,
          ip: ip,
          avatarBase64: avatarBase64,
        );
        // Solo notificar si no es uno mismo
        if (ip != _myIp) onMemberEvent?.call(name, true);
      } else {
        // Actualizar avatar solo si lo tenía vacío
        if (avatarBase64 != null && _members[ip]!.avatarBase64 == null) {
          _members[ip]!.avatarBase64 = avatarBase64;
        }
        _members[ip]!.isOnline = true;
        _members[ip]!.lastSeen = DateTime.now();
      }
    }
    _members.removeWhere((ip, m) => !currentIps.contains(ip) && ip != _myIp);
    onMembersChanged?.call(_members);
  }

  void _startAnnounce() {
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      _announceSocket = socket;
      socket.broadcastEnabled = true;
    });
  }

  void announceRoom(String code) {
    _roomCode = code;
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final msg = 'ROOM:$code:$_myIp';
      try {
        _announceSocket?.send(
          msg.codeUnits,
          InternetAddress('255.255.255.255'),
          announcePort,
        );
        _announceSocket?.send(
          msg.codeUnits,
          InternetAddress('192.168.49.255'),
          announcePort,
        );
      } catch (_) {}
    });
  }

  static Future<String?> findRoomHost(String code) async {
    final broadcastResult = await _findByBroadcast(code);
    if (broadcastResult != null) return broadcastResult;
    return await _findBySubnetScan(code);
  }

  static Future<String?> _findByBroadcast(String code) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        announcePort,
        reuseAddress: true,
      );
      final completer = Completer<String?>();
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg == null) return;
          final msg = String.fromCharCodes(dg.data);
          if (msg.startsWith('ROOM:$code:') && !completer.isCompleted) {
            completer.complete(msg.split(':')[2]);
          }
        }
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete(null);
      });
      final result = await completer.future;
      socket.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _findBySubnetScan(String code) async {
    try {
      final myIp = await NetworkInfo().getWifiIP();
      final completer = Completer<String?>();
      final receiveSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        announcePort,
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
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      socket.send(
        'ROOM_QUERY:$code'.codeUnits,
        InternetAddress('192.168.49.1'),
        signalPort,
      );

      for (int i = 1; i <= 10; i++) {
        if (completer.isCompleted) break;
        socket.send(
          'ROOM_QUERY:$code'.codeUnits,
          InternetAddress('192.168.49.$i'),
          signalPort,
        );
      }

      if (myIp != null && !myIp.startsWith('192.168.49')) {
        final prefix = myIp.substring(0, myIp.lastIndexOf('.'));
        for (int i = 1; i <= 254; i++) {
          if (completer.isCompleted) break;
          final targetIp = '$prefix.$i';
          if (targetIp == myIp) continue;
          try {
            socket.send(
              'ROOM_QUERY:$code'.codeUnits,
              InternetAddress(targetIp),
              signalPort,
            );
          } catch (_) {}
          if (i % 20 == 0) {
            await Future.delayed(const Duration(milliseconds: 30));
          }
        }
      }

      Future.delayed(const Duration(seconds: 8), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final result = await completer.future;
      socket.close();
      receiveSocket.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  void sendAudio(Uint8List data) {
    for (final entry in _members.entries) {
      if (entry.key == _myIp) continue;
      if (entry.value.isMuted) continue;
      if (!entry.value.isOnline) continue;
      try {
        _audioSocket?.send(data, InternetAddress(entry.key), audioPort);
      } catch (_) {}
    }
  }

  void _updateSpeakingLevel(String ip, Uint8List data) {
    if (!_members.containsKey(ip)) return;
    double sum = 0;
    for (int i = 0; i < data.length - 1; i += 2) {
      final s = data[i] | (data[i + 1] << 8);
      final signed = s > 32767 ? s - 65536 : s;
      sum += signed * signed;
    }
    final rms = data.length > 1 ? (sum / (data.length / 2)) : 0.0;
    _members[ip]!.speakingLevel = (rms / (8000.0 * 8000.0)).clamp(0.0, 1.0);
    _members[ip]!.lastSeen = DateTime.now();
    _members[ip]!.isOnline = true;
    onMembersChanged?.call(_members);
  }

  void setMemberMuted(String ip, bool muted) {
    if (!_members.containsKey(ip)) return;
    _members[ip]!.isMuted = muted;
    final msg = 'MUTE:$ip:${muted ? '1' : '0'}';
    for (final memberIp in _members.keys) {
      if (memberIp != _myIp) _sendSignal(msg, memberIp);
    }
    onMembersChanged?.call(_members);
  }

  void setMemberVolume(String ip, double volume) {
    if (!_members.containsKey(ip)) return;
    _members[ip]!.volume = volume;
    onMembersChanged?.call(_members);
  }

  void _sendSignal(String msg, String ip) {
    try {
      _signalSocket?.send(msg.codeUnits, InternetAddress(ip), signalPort);
    } catch (_) {}
  }

  // Responde al query con nombre y avatar del host
  void respondToQuery(String toIp, String code) {
    try {
      // Incluir nombre y avatar del host en la respuesta
      final avatar = _myAvatarBase64 ?? '';
      final msg = 'ROOM:$code:$_myIp:$_myName:$avatar';
      _announceSocket?.send(msg.codeUnits, InternetAddress(toIp), announcePort);
    } catch (_) {}
  }

  void leaveRoom() {
    if (_hostIp != null) {
      _sendSignal('LEAVE:$_myIp', _hostIp!);
    } else if (_isHost) {
      for (final ip in _members.keys) {
        if (ip != _myIp) _sendSignal('LEAVE:$_myIp', ip);
      }
    }
    close();
  }

  void close() {
    _running = false;
    _heartbeatTimer?.cancel();
    _announceTimer?.cancel();
    _timeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _audioSocket?.close();
    _signalSocket?.close();
    _announceSocket?.close();
    _audioSocket = null;
    _signalSocket = null;
    _announceSocket = null;
    _members.clear();
    _isHost = false;
    _hostIp = null;
  }

  // Descubrir salas activas en WiFi Direct
  static Future<List<Map<String, String>>> discoverRooms() async {
    final rooms = <Map<String, String>>[];
    final seen = <String>{};
    final completer = Completer<List<Map<String, String>>>();

    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        announcePort,
        reuseAddress: true,
      );

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg == null) return;
          final msg = String.fromCharCodes(dg.data);
          if (msg.startsWith('ROOM:')) {
            final firstColon = msg.indexOf(':');
            final secondColon = msg.indexOf(':', firstColon + 1);
            final thirdColon = msg.indexOf(':', secondColon + 1);
            final fourthColon = msg.indexOf(':', thirdColon + 1);

            if (secondColon == -1) return;
            final code = msg.substring(firstColon + 1, secondColon);
            final ip = thirdColon == -1
                ? msg.substring(secondColon + 1)
                : msg.substring(secondColon + 1, thirdColon);
            final name = thirdColon != -1 && fourthColon != -1
                ? msg.substring(thirdColon + 1, fourthColon)
                : null;
            final avatar = fourthColon != -1
                ? msg.substring(fourthColon + 1)
                : null;

            if (!seen.contains(ip)) {
              seen.add(ip);
              rooms.add({
                'code': code,
                'ip': ip,
                'name': name ?? '',
                'avatar': avatar ?? '',
              });
            }
          }
        }
      });

      final querySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      for (int i = 1; i <= 254; i++) {
        querySocket.send(
          'ROOM_QUERY:*'.codeUnits,
          InternetAddress('192.168.49.$i'),
          signalPort,
        );
        if (i % 30 == 0) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(rooms);
          socket.close();
          querySocket.close();
        }
      });

      return await completer.future;
    } catch (_) {
      return rooms;
    }
  }
}
