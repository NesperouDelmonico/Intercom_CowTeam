import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:intercom_app/services/audio_service.dart';

class AudioService {
  static const channel = MethodChannel('com.example.intercom_app/audio');
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

    // Iniciar AudioTrack nativo
    await channel.invokeMethod('startPlayback');

    // Socket para enviar
    _sendSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    // Socket para recibir
    _receiveSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      remotePort,
      reuseAddress: true,
    );

    // Reproducir audio entrante via AudioTrack nativo
    _receiveSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _receiveSocket!.receive();
        if (datagram != null && _isRunning) {
          channel.invokeMethod('playChunk', {'data': datagram.data});
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
      if (_sendSocket != null && _isRunning && !_isMuted) {
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

  Future<void> stopCall() async {
    _isRunning = false;
    _audioSubscription?.cancel();
    await _recorder.stop();
    await channel.invokeMethod('stopPlayback');
    _sendSocket?.close();
    _receiveSocket?.close();
    _sendSocket = null;
    _receiveSocket = null;
  }

  void setMuted(bool muted) {
    _isMuted = muted;
  }

  bool _isMuted = false;
}
