import 'dart:io';
import 'dart:io' as io;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_info.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/services/native_bridge.dart';
import 'package:intercom_app/services/settings_service.dart';
import 'package:intercom_app/services/wifi_direct_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

final _wifiDirect = WifiDirectService();

class SpeakingLevelsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  void update(String ip, double level) {
    state = {...state, ip: level};
  }
}

final speakingLevelsProvider =
    NotifierProvider<SpeakingLevelsNotifier, Map<String, double>>(
      SpeakingLevelsNotifier.new,
    );

class RoomNotifier extends Notifier<RoomState> {
  String _myName = '';
  String _myIp = '';
  String _roomCode = '';
  bool _callActive = false; // guard contra doble llamada
  // Evita disparar múltiples intentos de reconexión forzada en
  // paralelo si el evento llega más de una vez.
  bool _forceReconnectInProgress = false;

  // El tercer parámetro (isSelf) indica si el evento es sobre el
  // propio dispositivo — en ese caso la UI no debe mostrar texto,
  // solo el sonido (ya manejado en RoomEngine nativo).
  void Function(String name, bool joined, bool isSelf)? _memberEventCallback;
  void Function()? _hostClosedCallback;

  @override
  RoomState build() {
    _initName();
    NativeBridge.startListening();
    _setupNativeCallbacks();
    return const RoomState();
  }

  void _setupNativeCallbacks() {
    NativeBridge.onMembersChanged = (membersList) {
      final members = <String, RoomMember>{};
      for (final m in membersList) {
        final ip = m['ip'] as String;
        members[ip] = RoomMember(
          name: m['name'] as String,
          ip: ip,
          isMuted: m['isMuted'] as bool? ?? false,
          volume: (m['volume'] as num?)?.toDouble() ?? 1.0,
          speakingLevel: (m['speakingLevel'] as num?)?.toDouble() ?? 0.0,
          avatarBase64: m['avatarBase64'] as String?,
          isOnline: m['isOnline'] as bool? ?? true,
        );
      }
      state = state.copyWith(members: members);

      // Historial WiFi Direct — asociamos cada miembro remoto con
      // las MACs WiFi Direct actualmente conectadas. No es un mapeo
      // perfecto 1:1, pero da candidatos válidos para forzar la
      // reconexión si la señal se pierde más adelante.
      for (final ip in members.keys) {
        if (ip == _myIp) continue;
        for (final addr in _wifiDirect.connectedAddresses) {
          NativeBridge.setMemberWifiDirectAddress(ip, addr);
        }
      }
    };

    NativeBridge.onMemberJoined = (name, ip, isSelf) {
      _memberEventCallback?.call(name, true, isSelf);
    };

    NativeBridge.onMemberLeft = (name, ip) {
      // La salida del propio dispositivo nunca llega por este
      // camino (handleLeave es para los demás), así que isSelf
      // siempre es false aquí.
      _memberEventCallback?.call(name, false, false);
    };

    NativeBridge.onCallStopped = () {
      _callActive = false;
      _hostClosedCallback?.call();
    };

    NativeBridge.onSpeakingLevel = (ip, level) {
      ref.read(speakingLevelsProvider.notifier).update(ip, level);
    };

    NativeBridge.onConnectionLost = () {
      state = state.copyWith(isReconnecting: true);
    };

    NativeBridge.onConnectionRestored = () {
      state = state.copyWith(isReconnecting: false);
      _forceReconnectInProgress = false;
    };

    // El banner "Reconectando" lleva demasiado tiempo activo —
    // intentamos forzar la reconexión WiFi Direct con alguna de
    // las MACs conocidas de la sala.
    NativeBridge.onForceReconnectWifiDirect = (addresses) async {
      if (_forceReconnectInProgress) return;
      if (addresses.isEmpty) return;
      _forceReconnectInProgress = true;

      for (final address in addresses) {
        try {
          await _wifiDirect.connect(address);
          // Si connect() no lanza excepción, asumimos éxito y
          // dejamos que el resto del flujo normal (ANNOUNCE)
          // confirme la reconexión real a la sala.
          break;
        } catch (_) {
          // Intentar con la siguiente MAC conocida.
          continue;
        }
      }

      _forceReconnectInProgress = false;
    };
  }

  void setMemberEventCallback(
    void Function(String name, bool joined, bool isSelf) cb,
  ) => _memberEventCallback = cb;

  void setHostClosedCallback(void Function() cb) => _hostClosedCallback = cb;

  Future<void> _initName() async {
    final info = await DeviceInfoPlugin().androidInfo;
    try {
      final settings = await ref.read(settingsProvider.future);
      final name = settings?.deviceName as String?;
      _myName = (name != null && name.isNotEmpty) ? name : info.model;
    } catch (_) {
      _myName = info.model;
    }
  }

  Future<String> _getMyIp() async {
    for (int attempt = 0; attempt < 10; attempt++) {
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
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return await NetworkInfo().getWifiIP() ?? '';
  }

  Future<String?> _loadAvatar() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/avatar.jpg');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length > 30000) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  String _generateRoomCode() => (1000 + Random().nextInt(9000)).toString();

  // ── CREAR SALA ─────────────────────────────────────
  Future<void> createRoom() async {
    if (_callActive) return; // evitar doble llamada
    _callActive = true;

    try {
      await _initName();
      _myIp = await _getMyIp();
      _roomCode = _generateRoomCode();
      final avatar = await _loadAvatar();

      _wifiDirect.startListening();
      try {
        final groupInfo = await _wifiDirect.requestGroupInfo();
        if (groupInfo == null || groupInfo['isGroupOwner'] != true) {
          await _wifiDirect.createGroupAndWait().timeout(
            const Duration(seconds: 8),
          );
          await Future.delayed(const Duration(seconds: 1));
          _myIp = await _getMyIp();
        }
      } catch (_) {}

      await NativeBridge.startCallWithService(
        deviceName: _myName,
        myIp: _myIp,
        myName: _myName,
        myAvatar: avatar ?? '',
        roomCode: _roomCode,
      );
      state = state.copyWith(
        status: RoomStatus.hosting,
        roomCode: _roomCode,
        isHost: true,
      );

      try {
        final settings = await ref.read(settingsProvider.future);
        await NativeBridge.setNoiseLevel(settings.noiseLevel);
        await NativeBridge.setVox(
          enabled: settings.voxEnabled,
          threshold: settings.voxThreshold,
        );
        await NativeBridge.setGain(settings.micGain); // ← también ganancia
      } catch (_) {}
    } catch (e) {
      _callActive = false; // resetear si falla
      rethrow;
    }
  }

  // ── UNIRSE A SALA ──────────────────────────────────
  Future<void> joinRoom(String coordIp) async {
    if (_callActive) return; // evitar doble llamada
    _callActive = true;

    try {
      await _initName();
      await Future.delayed(const Duration(seconds: 2));
      _myIp = await _getMyIp();
      final avatar = await _loadAvatar();

      await NativeBridge.startCallWithService(
        deviceName: _myName,
        myIp: _myIp,
        myName: _myName,
        myAvatar: avatar ?? '',
        roomCode: state.roomCode ?? _roomCode,
      );

      state = state.copyWith(status: RoomStatus.joined, isHost: false);

      try {
        final settings = await ref.read(settingsProvider.future);
        await NativeBridge.setNoiseLevel(settings.noiseLevel);
        await NativeBridge.setVox(
          enabled: settings.voxEnabled,
          threshold: settings.voxThreshold,
        );
        await NativeBridge.setGain(settings.micGain); // ← también ganancia
      } catch (_) {}
    } catch (e) {
      _callActive = false;
      rethrow;
    }
  }

  Future<void> joinRoomByCode(String code) async {
    final hostIp = await _findRoomHost(code);
    if (hostIp == null) return;
    state = state.copyWith(roomCode: code);
    _roomCode = code;
    await joinRoom(hostIp);
    state = state.copyWith(roomCode: code);
  }

  Future<bool> searchAndJoinViaWifiDirect(String code) async {
    final hostIp = await _findRoomHost(code);
    if (hostIp == null) return false;
    state = state.copyWith(roomCode: code);
    _roomCode = code;
    await joinRoom(hostIp);
    state = state.copyWith(roomCode: code);
    return true;
  }

  // ── BÚSQUEDA DE SALA ───────────────────────────────
  Future<String?> _findRoomHost(String code) async {
    final result = await _listenForAnnounce(code, seconds: 3);
    if (result != null) return result;
    return await _scanForRoom(code);
  }

  Future<String?> _listenForAnnounce(String code, {int seconds = 3}) async {
    try {
      final sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5562,
        reuseAddress: true,
      );
      final c = Completer<String?>();
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        if (msg.startsWith('ANNOUNCE:$code:') && !c.isCompleted) {
          final parts = msg.split(':');
          if (parts.length > 2) c.complete(parts[2]);
        }
      });
      Future.delayed(Duration(seconds: seconds), () {
        if (!c.isCompleted) c.complete(null);
      });
      final result = await c.future;
      sock.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _scanForRoom(String code) async {
    try {
      final recv = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5562,
        reuseAddress: true,
      );
      final send = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      send.broadcastEnabled = true;
      final c = Completer<String?>();

      recv.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = recv.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        if (msg.startsWith('ANNOUNCE:$code:') && !c.isCompleted) {
          final parts = msg.split(':');
          if (parts.length > 2) c.complete(parts[2]);
        }
      });

      for (int i = 1; i <= 254; i++) {
        if (c.isCompleted) break;
        try {
          send.send(
            'WHO:$code'.codeUnits,
            InternetAddress('192.168.49.$i'),
            5561,
          );
        } catch (_) {}
        if (i % 30 == 0) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      Future.delayed(const Duration(seconds: 6), () {
        if (!c.isCompleted) c.complete(null);
      });
      final result = await c.future;
      send.close();
      recv.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── DESCUBRIR SALAS ────────────────────────────────
  Future<List<RoomInfo>> discoverRooms() async {
    final rooms = <RoomInfo>[];
    final seen = <String>{};
    final c = Completer<List<RoomInfo>>();

    try {
      final recv = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5562,
        reuseAddress: true,
      );
      final send = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      send.broadcastEnabled = true;

      recv.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = recv.receive();
        if (dg == null) return;
        final msg = String.fromCharCodes(dg.data);
        if (!msg.startsWith('ANNOUNCE:')) return;

        final parts = msg.split(':');
        if (parts.length < 5) return;

        final code = parts[1];
        final ip = parts[2];
        final name = parts[3];
        final avatar = parts[4];

        if (!seen.contains(ip)) {
          seen.add(ip);
          rooms.add(
            RoomInfo(
              code: code,
              hostIp: ip,
              hostName: name.isNotEmpty ? name : null,
              hostAvatarBase64: avatar.isNotEmpty ? avatar : null,
            ),
          );
        }
      });

      send.send('WHO:*'.codeUnits, InternetAddress('192.168.49.255'), 5561);
      for (int i = 1; i <= 254; i++) {
        try {
          send.send('WHO:*'.codeUnits, InternetAddress('192.168.49.$i'), 5561);
        } catch (_) {}
        if (i % 30 == 0) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (!c.isCompleted) {
          c.complete(rooms);
          recv.close();
          send.close();
        }
      });

      return await c.future;
    } catch (_) {
      return rooms;
    }
  }

  // ── CONTROLES ──────────────────────────────────────
  void toggleGlobalMute() {
    final muted = !state.globalMuted;
    state = state.copyWith(globalMuted: muted);
    NativeBridge.setMuted(muted);
  }

  void setMemberMuted(String ip, bool muted) =>
      NativeBridge.setMemberMuted(ip, muted);

  void setMemberVolume(String ip, double volume) =>
      NativeBridge.setMemberVolume(ip, volume);

  void setMicGain(double gain) => NativeBridge.setGain(gain);

  void setVox({required bool enabled, required double threshold}) =>
      NativeBridge.setVox(enabled: enabled, threshold: threshold);

  Future<void> setNoiseLevel(int level) async {
    await NativeBridge.setNoiseLevel(level);
  }

  void setLowPowerMode(bool enabled) {
    NativeBridge.setLowPowerMode(enabled);
    if (!enabled) {
      // Restaurar configuraciones guardadas del usuario
      SettingsService.getVoxEnabled().then((voxEnabled) {
        SettingsService.getVoxThreshold().then((voxThreshold) {
          NativeBridge.setVox(enabled: voxEnabled, threshold: voxThreshold);
        });
      });
    }
  }

  Future<bool> hasNetworkConnection() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      return ip != null && ip.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── SALIR ──────────────────────────────────────────
  Future<void> leaveRoom() async {
    _callActive = false;
    await NativeBridge.stopCall();
    state = const RoomState();
    _roomCode = '';
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(
  RoomNotifier.new,
);
