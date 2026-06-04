import 'dart:io';
import 'dart:async';
import 'package:intercom_app/models/device.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DiscoveryService {
  static const int discoveryPort = 5556;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  bool _running = false;
  final List<Device> _foundDevices = [];
  void Function(Device device)? onDeviceFound;
  String _myIp = '';

  List<Device> get devices => List.unmodifiable(_foundDevices);

  Future<void> start(String myName) async {
    _foundDevices.clear();
    _running = true;

    final info = NetworkInfo();
    _myIp = await info.getWifiIP() ?? '';

    // Escuchar anuncios entrantes
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram == null) return;
        final senderIp = datagram.address.address;
        if (senderIp == _myIp) return;
        final message = String.fromCharCodes(datagram.data);
        if (message.startsWith('INTERCOM:')) {
          final name = message.substring(9);
          final device = Device(name: name, ip: senderIp, port: 5555);
          if (!_foundDevices.any((d) => d.ip == senderIp)) {
            _foundDevices.add(device);
            onDeviceFound?.call(device);
          }
        }
      }
    });

    // Anunciarse por broadcast cada 2s
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_socket == null || !_running) return;
      final message = 'INTERCOM:$myName';
      try {
        _socket!.send(
          message.codeUnits,
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      } catch (_) {}
    });

    // Escaneo directo de subred en paralelo
    _scanSubnet(myName);
  }

  Future<void> _scanSubnet(String myName) async {
    if (_myIp.isEmpty) return;
    final prefix = _myIp.substring(0, _myIp.lastIndexOf('.'));

    // Enviar mensaje directo a cada IP de la subred
    for (int i = 1; i <= 254; i++) {
      if (!_running) break;
      final targetIp = '$prefix.$i';
      if (targetIp == _myIp) continue;
      try {
        _socket?.send(
          'INTERCOM:Scan'.codeUnits,
          InternetAddress(targetIp),
          discoveryPort,
        );
      } catch (_) {}
      // Pequeña pausa para no saturar la red
      if (i % 10 == 0) await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  void stop() {
    _running = false;
    _announceTimer?.cancel();
    _socket?.close();
    _socket = null;
    _foundDevices.clear();
  }
}
