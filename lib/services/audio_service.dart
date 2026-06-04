import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  RawDatagramSocket? _sendSocket;
  RawDatagramSocket? _receiveSocket;
  StreamSubscription? _audioSubscription;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Future<void> startCall({
    required String remoteIp,
    required int remotePort,
  }) async {
    if (_isRunning) return;
    _isRunning = true;

    // Inicializar reproducción PCM
    await FlutterPcmSound.setup(sampleRate: 16000, channelCount: 1);
    FlutterPcmSound.start();

    // Socket para enviar audio al otro teléfono
    _sendSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    // Socket para recibir audio del otro teléfono
    _receiveSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      remotePort,
      reuseAddress: true,
    );

    // Reproducir audio que llega
    _receiveSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _receiveSocket!.receive();
        if (datagram != null && _isRunning) {
          FlutterPcmSound.feed(
            PcmArrayInt16.fromList(_bytesToInt16(datagram.data)),
          );
        }
      }
    });

    // Capturar micrófono y enviar
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _audioSubscription = stream.listen((chunk) {
      if (_sendSocket != null && _isRunning) {
        try {
          _sendSocket!.send(
            Uint8List.fromList(chunk),
            InternetAddress(remoteIp),
            remotePort,
          );
        } catch (_) {}
      }
    });
  }

  List<int> _bytesToInt16(Uint8List bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final value = bytes[i] | (bytes[i + 1] << 8);
      result.add(value > 32767 ? value - 65536 : value);
    }
    return result;
  }

  Future<void> stopCall() async {
    _isRunning = false;
    _audioSubscription?.cancel();
    await _recorder.stop();
    await FlutterPcmSound.stop();
    _sendSocket?.close();
    _receiveSocket?.close();
    _sendSocket = null;
    _receiveSocket = null;
  }
}
