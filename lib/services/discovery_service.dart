import 'dart:io';
import 'dart:async';
import 'package:intercom_app/models/device.dart';

class DiscoveryService {
  static const int discoveryPort = 5556;
  static const String broadcastAddress = '255.255.255.255';

  RawDatagramSocket? _socket;
  final List<Device> _foundDevices = [];
  void Function(Device device)? onDeviceFound;

  List<Device> get devices => List.unmodifiable(_foundDevices);

  Future<void> start(String myName) async {
    _foundDevices.clear();
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
        final message = String.fromCharCodes(datagram.data);
        if (message.startsWith('INTERCOM:')) {
          final name = message.substring(9);
          final ip = datagram.address.address;
          final device = Device(name: name, ip: ip, port: 5555);
          if (!_foundDevices.any((d) => d.ip == ip)) {
            _foundDevices.add(device);
            onDeviceFound?.call(device);
          }
        }
      }
    });

    // Anunciar nuestra presencia cada 2 segundos
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_socket == null) {
        timer.cancel();
        return;
      }
      final message = 'INTERCOM:$myName';
      _socket!.send(
        message.codeUnits,
        InternetAddress(broadcastAddress),
        discoveryPort,
      );
    });
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _foundDevices.clear();
  }
}
