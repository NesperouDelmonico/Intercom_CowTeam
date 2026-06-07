import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:intercom_app/models/device.dart';

class RoomService {
  static const int roomPort = 5560;
  static const int signalPort = 5561;
  static const int maxMembers = 10;

  RawDatagramSocket? _audioSocket;
  RawDatagramSocket? _signalSocket;

  final List<Device> _members = [];
  bool _isHost = false;
  String? _hostIp;
  Timer? _heartbeatTimer;

  void Function(List<Device> members)? onMembersChanged;
  void Function(Uint8List audio)? onAudioReceived;

  List<Device> get members => List.unmodifiable(_members);
  bool get isHost => _isHost;

  // Genera código de sala de 4 dígitos
  String generateRoomCode() {
    return (1000 + Random().nextInt(9000)).toString();
  }

  // HOST: crear sala
  Future<void> createRoom(String myName, String myIp) async {
    _isHost = true;
    _members.clear();
    _members.add(Device(name: myName, ip: myIp, port: roomPort));

    _audioSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      roomPort,
      reuseAddress: true,
    );

    _signalSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      signalPort,
      reuseAddress: true,
    );

    // Escuchar audio de clientes y mezclarlo
    _audioSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _audioSocket!.receive();
        if (dg == null) return;
        _mixAndRedistribute(dg.data, dg.address.address);
      }
    });

    // Escuchar señales de join/leave
    _signalSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _signalSocket!.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        final ip = dg.address.address;
        _handleSignal(msg, ip);
      }
    });
  }

  // CLIENTE: unirse a sala
  Future<void> joinRoom(String myName, String myIp, String hostIp) async {
    _isHost = false;
    _hostIp = hostIp;

    _audioSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      roomPort,
      reuseAddress: true,
    );

    _signalSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      signalPort,
      reuseAddress: true,
    );

    // Recibir audio mezclado del host
    _audioSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _audioSocket!.receive();
        if (dg != null) onAudioReceived?.call(dg.data);
      }
    });

    // Escuchar actualizaciones de miembros del host
    _signalSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _signalSocket!.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        _handleClientSignal(msg);
      }
    });

    // Anunciarse al host
    _sendSignal('JOIN:$myName:$myIp', hostIp);

    // Heartbeat cada 3 segundos para mantenerse en la sala
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendSignal('HEARTBEAT:$myName:$myIp', hostIp);
    });
  }

  void _handleSignal(String msg, String fromIp) {
    if (msg.startsWith('JOIN:')) {
      final parts = msg.split(':');
      if (parts.length < 3) return;
      final name = parts[1];
      final ip = parts[2];
      if (_members.length < maxMembers && !_members.any((m) => m.ip == ip)) {
        _members.add(Device(name: name, ip: ip, port: roomPort));
        onMembersChanged?.call(_members);
        _broadcastMembers();
      }
    } else if (msg.startsWith('LEAVE:')) {
      final ip = msg.split(':')[1];
      _members.removeWhere((m) => m.ip == ip);
      onMembersChanged?.call(_members);
      _broadcastMembers();
    } else if (msg.startsWith('HEARTBEAT:')) {
      // mantener vivo — no hace nada más
    }
  }

  void _handleClientSignal(String msg) {
    if (msg.startsWith('MEMBERS:')) {
      final raw = msg.substring(8);
      if (raw.isEmpty) return;
      final entries = raw.split(',');
      _members.clear();
      for (final e in entries) {
        final p = e.split(':');
        if (p.length >= 2) {
          _members.add(Device(name: p[0], ip: p[1], port: roomPort));
        }
      }
      onMembersChanged?.call(_members);
    }
  }

  void _broadcastMembers() {
    final payload = _members.map((m) => '${m.name}:${m.ip}').join(',');
    final msg = 'MEMBERS:$payload';
    for (final m in _members) {
      _sendSignal(msg, m.ip);
    }
  }

  // Mixer: suma PCM de todos y redistribuye
  void _mixAndRedistribute(Uint8List incoming, String fromIp) {
    // Reproducir localmente en el host
    onAudioReceived?.call(incoming);

    // Reenviar a todos los demás miembros
    for (final member in _members) {
      if (member.ip != fromIp) {
        try {
          _audioSocket?.send(incoming, InternetAddress(member.ip), roomPort);
        } catch (_) {}
      }
    }
  }

  void sendAudio(Uint8List data) {
    if (_isHost) {
      // Host reproduce directo y redistribuye
      _mixAndRedistribute(data, 'self');
    } else if (_hostIp != null) {
      try {
        _audioSocket?.send(data, InternetAddress(_hostIp!), roomPort);
      } catch (_) {}
    }
  }

  void _sendSignal(String msg, String ip) {
    try {
      _signalSocket?.send(msg.codeUnits, InternetAddress(ip), signalPort);
    } catch (_) {}
  }

  void leaveRoom(String myIp) {
    if (_hostIp != null) {
      _sendSignal('LEAVE:$myIp', _hostIp!);
    }
    close();
  }

  void close() {
    _heartbeatTimer?.cancel();
    _audioSocket?.close();
    _signalSocket?.close();
    _audioSocket = null;
    _signalSocket = null;
    _members.clear();
    _isHost = false;
    _hostIp = null;
  }
}
