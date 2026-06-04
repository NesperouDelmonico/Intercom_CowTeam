import 'dart:io';
import 'dart:typed_data';

class NetworkService {
  static const int port = 5555;

  RawDatagramSocket? _socket;
  void Function(Uint8List data, String fromIp)? onDataReceived;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null && onDataReceived != null) {
          onDataReceived!(datagram.data, datagram.address.address);
        }
      }
    });
  }

  Future<void> send(Uint8List data, String ip) async {
    _socket?.send(data, InternetAddress(ip), port);
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }
}
