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

  RoomMember({
    required this.name,
    required this.ip,
    this.isMuted = false,
    this.volume = 1.0,
    this.speakingLevel = 0.0,
    this.avatarBase64,
  });
}

class RoomService {
  static const int audioPort = 5560;
  static const int signalPort = 5561;
  static const int announcePort = 5562;
  static const int maxMembers = 10;

  RawDatagramSocket? _audioSocket;
  RawDatagramSocket? _signalSocket;
  RawDatagramSocket? _announceSocket;

  final Map<String, RoomMember> _members = {};
  bool _isHost = false;
  String? _hostIp;
  String _myIp = '';
  String _myName = '';
  Timer? _heartbeatTimer;
  Timer? _announceTimer;

  void Function(Map<String, RoomMember> members)? onMembersChanged;
  void Function(Uint8List audio, String fromIp)? onAudioReceived;

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
    _members[myIp] = RoomMember(
      name: myName,
      ip: myIp,
      avatarBase64: avatarBase64,
    );
    await _bindSockets();
    _listenSignals();
    _listenAudio();
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
    _hostIp = hostIp;

    await _bindSockets();
    _listenSignals();
    _listenAudio();

    // Anunciarse al host con avatar incluido
    final avatarPart = avatarBase64 != null ? ':$avatarBase64' : '';
    _sendSignal('JOIN:$myName:$myIp$avatarPart', hostIp);

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendSignal('HEARTBEAT:$myName:$myIp', hostIp);
    });
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
        // Calcular nivel de voz del remitente
        _updateSpeakingLevel(fromIp, dg.data);
        onAudioReceived?.call(dg.data, fromIp);
      }
    });
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
    onMembersChanged?.call(_members);
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
      // Formato: JOIN:name:ip o JOIN:name:ip:avatarBase64
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

      if (_members.length < maxMembers && !_members.containsKey(ip)) {
        _members[ip] = RoomMember(
          name: name,
          ip: ip,
          avatarBase64: avatarBase64,
        );
        onMembersChanged?.call(_members);
        _broadcastMemberList();
        _sendMemberListTo(ip);
      }
    } else if (msg.startsWith('LEAVE:')) {
      final ip = msg.split(':')[1];
      _members.remove(ip);
      onMembersChanged?.call(_members);
      if (_isHost) _broadcastMemberList();
    } else if (msg.startsWith('MEMBERS:')) {
      // Solo clientes reciben esto
      if (_isHost) return;
      _parseMemberList(msg.substring(8));
    } else if (msg.startsWith('MUTE:')) {
      final parts = msg.split(':');
      if (parts.length < 3) return;
      final ip = parts[1];
      final muted = parts[2] == '1';
      if (_members.containsKey(ip)) {
        _members[ip]!.isMuted = muted;
        onMembersChanged?.call(_members);
      }
    } else if (msg.startsWith('ROOM_QUERY:')) {
      final queryCode = msg.split(':')[1];
      // El host responde con su código de sala
      // El código se guarda en room_provider, así que necesitamos
      // una forma de accederlo — lo enviamos via el announce socket
      onRoomQuery?.call(queryCode, fromIp);
    }
  }

  void Function(String code, String fromIp)? onRoomQuery;

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
      } else if (avatarBase64 != null) {
        _members[ip]!.avatarBase64 = avatarBase64;
      }
    }
    _members.removeWhere((ip, _) => !currentIps.contains(ip));
    onMembersChanged?.call(_members);
  }

  void _broadcastMemberList() {
    final payload = _members.entries
        .map((e) => '${e.value.name}§${e.key}§${e.value.avatarBase64 ?? ''}')
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

  void _startAnnounce() {
    _announceSocket = null;
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      _announceSocket = socket;
      socket.broadcastEnabled = true;
    });
  }

  void announceRoom(String code) {
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final msg = 'ROOM:$code:$_myIp';
      try {
        // Broadcast WiFi normal
        _announceSocket?.send(
          msg.codeUnits,
          InternetAddress('255.255.255.255'),
          announcePort,
        );
        // Broadcast subred WiFi Direct
        _announceSocket?.send(
          msg.codeUnits,
          InternetAddress('192.168.49.255'),
          announcePort,
        );
      } catch (_) {}
    });
  }

  static Future<String?> findRoomHost(String code) async {
    // Estrategia 1: escuchar broadcast
    final broadcastResult = await _findByBroadcast(code);
    if (broadcastResult != null) return broadcastResult;

    // Estrategia 2: escaneo directo de subred
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

      // Estrategia 1: IP fija del Group Owner WiFi Direct
      final wifiDirectGoIp = '192.168.49.1';
      socket.send(
        'ROOM_QUERY:$code'.codeUnits,
        InternetAddress(wifiDirectGoIp),
        signalPort,
      );

      // Estrategia 2: subred WiFi normal si hay IP
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

      // Estrategia 3: subred WiFi Direct (192.168.49.x)
      if (!completer.isCompleted) {
        for (int i = 1; i <= 10; i++) {
          if (completer.isCompleted) break;
          final targetIp = '192.168.49.$i';
          try {
            socket.send(
              'ROOM_QUERY:$code'.codeUnits,
              InternetAddress(targetIp),
              signalPort,
            );
          } catch (_) {}
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

  // MESH P2P: enviar audio directamente a todos
  void sendAudio(Uint8List data) {
    for (final entry in _members.entries) {
      if (entry.key == _myIp) continue;
      if (entry.value.isMuted) continue;
      try {
        _audioSocket?.send(data, InternetAddress(entry.key), audioPort);
      } catch (_) {}
    }
  }

  void setMemberMuted(String ip, bool muted) {
    if (!_members.containsKey(ip)) return;
    _members[ip]!.isMuted = muted;
    // Notificar a todos
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

  void leaveRoom() {
    if (_hostIp != null) {
      _sendSignal('LEAVE:$_myIp', _hostIp!);
    } else if (_isHost) {
      // Notificar a todos que el host se va
      for (final ip in _members.keys) {
        if (ip != _myIp) _sendSignal('LEAVE:$_myIp', ip);
      }
    }
    close();
  }

  void close() {
    _heartbeatTimer?.cancel();
    _announceTimer?.cancel();
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

  void respondToQuery(String toIp, String code) {
    try {
      _announceSocket?.send(
        'ROOM:$code:$_myIp'.codeUnits,
        InternetAddress(toIp),
        announcePort,
      );
    } catch (_) {}
  }
}
