import 'dart:io';
import 'dart:typed_data';

class NetworkService {
  static const int port = 5555;
  static const int signalingPort = 5557;

  RawDatagramSocket? _socket;
  RawDatagramSocket? _signalingSocket;

  void Function(Uint8List data, String fromIp)? onDataReceived;
  void Function(String fromIp)? onIncomingCall;
  void Function()? onCallAccepted;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null && onDataReceived != null) {
          onDataReceived!(datagram.data, datagram.address.address);
        }
      }
    });

    // Socket de señalización
    _signalingSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      signalingPort,
      reuseAddress: true,
    );
    _signalingSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _signalingSocket!.receive();
        if (datagram == null) return;
        final msg = String.fromCharCodes(datagram.data);
        final ip = datagram.address.address;
        if (msg == 'CALL') onIncomingCall?.call(ip);
        if (msg == 'ACCEPT') onCallAccepted?.call();
      }
    });
  }

  Future<void> sendCallSignal(String ip) async {
    _signalingSocket?.send(
      'CALL'.codeUnits,
      InternetAddress(ip),
      signalingPort,
    );
  }

  Future<void> sendAcceptSignal(String ip) async {
    _signalingSocket?.send(
      'ACCEPT'.codeUnits,
      InternetAddress(ip),
      signalingPort,
    );
  }

  Future<void> send(Uint8List data, String ip) async {
    _socket?.send(data, InternetAddress(ip), port);
  }

  void stop() {
    _socket?.close();
    _signalingSocket?.close();
    _socket = null;
    _signalingSocket = null;
  }
}
