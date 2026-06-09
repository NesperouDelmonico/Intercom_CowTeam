import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

class AudioService {
  static const channel = MethodChannel('com.example.intercom_app/audio');
  final recorder = AudioRecorder();
  RawDatagramSocket? _sendSocket;
  RawDatagramSocket? _receiveSocket;
  StreamSubscription? _audioSubscription;

  bool _isRunning = false;
  bool _isMuted = false;
  bool get isRunning => _isRunning;

  // VOX
  bool _voxEnabled = false;
  double _voxThreshold = 500.0;

  void setMuted(bool muted) => _isMuted = muted;

  void Function(List<int> chunk)? onAudioChunk;

  Future<void> setVox({
    required bool enabled,
    required double threshold,
  }) async {
    _voxEnabled = enabled;
    _voxThreshold = threshold;
    await channel.invokeMethod('setVox', {
      'enabled': enabled,
      'threshold': threshold,
    });
  }

  Future<void> setVolume(double volume) async {
    await channel.invokeMethod('setVolume', {'volume': volume});
  }

  bool shouldTransmit(List<int> chunk) {
    if (!_voxEnabled) return true;
    double sum = 0;
    for (int i = 0; i < chunk.length - 1; i += 2) {
      final sample = chunk[i] | (chunk[i + 1] << 8);
      final signed = sample > 32767 ? sample - 65536 : sample;
      sum += signed * signed;
    }
    final rms = chunk.length > 1 ? (sum / (chunk.length / 2)) : 0.0;
    return rms > (_voxThreshold * _voxThreshold);
  }

  Future<void> startCall({
    required String remoteIp,
    required int remotePort,
  }) async {
    if (_isRunning) return;
    _isRunning = true;

    await channel.invokeMethod('startPlayback');

    await channel.invokeMethod('startForegroundService', {
      'deviceName': remoteIp,
    });

    _sendSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _receiveSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      remotePort,
      reuseAddress: true,
    );

    _receiveSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _receiveSocket!.receive();
        if (datagram != null && _isRunning) {
          channel.invokeMethod('playChunk', {'data': datagram.data});
        }
      }
    });

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) return;

    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    _audioSubscription = stream.listen((chunk) {
      if (_sendSocket != null && _isRunning && !_isMuted) {
        final processed = applyGain(chunk, micGain);
        if (shouldTransmit(processed)) {
          try {
            _sendSocket!.send(
              Uint8List.fromList(processed),
              InternetAddress(remoteIp),
              remotePort,
            );
          } catch (_) {}
        }
        onAudioChunk?.call(processed);
      }
    });
  }

  Future<void> stopCall() async {
    _isRunning = false;
    _isMuted = false;
    _audioSubscription?.cancel();
    await recorder.stop();
    await channel.invokeMethod('stopForegroundService');
    await channel.invokeMethod('stopPlayback');
    _sendSocket?.close();
    _receiveSocket?.close();
    _sendSocket = null;
    _receiveSocket = null;
  }

  double micGain = 1.0;

  void setMicGain(double gain) => micGain = gain;

  // Cambia _applyGain por applyGain (público):
  List<int> applyGain(List<int> chunk, double gain) {
    if (gain == 1.0) return chunk;
    final result = List<int>.filled(chunk.length, 0);
    for (int i = 0; i < chunk.length - 1; i += 2) {
      final s = chunk[i] | (chunk[i + 1] << 8);
      final signed = s > 32767 ? s - 65536 : s;
      final amplified = (signed * gain).round().clamp(-32768, 32767);
      result[i] = amplified & 0xFF;
      result[i + 1] = (amplified >> 8) & 0xFF;
    }
    return result;
  }
}
