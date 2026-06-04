import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/call_state.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/services/audio_service.dart';
import 'package:intercom_app/services/network_service.dart';

class CallNotifier extends Notifier<CallState> {
  final AudioService _audio = AudioService();
  final NetworkService _network = NetworkService();

  @override
  CallState build() {
    _initNetwork();
    return const CallState();
  }

  Future<void> _initNetwork() async {
    await _network.start();

    _network.onIncomingCall = (fromIp) {
      if (state.status == CallStatus.idle) {
        state = state.copyWith(
          status: CallStatus.incoming,
          remoteDevice: Device(
            name: 'Android-${fromIp.split('.').last}',
            ip: fromIp,
            port: 5555,
          ),
        );
      }
    };

    _network.onCallAccepted = () async {
      if (state.status == CallStatus.connecting) {
        await _audio.startCall(
          remoteIp: state.remoteDevice!.ip,
          remotePort: 5555,
        );
        state = state.copyWith(status: CallStatus.active);
      }
    };
  }

  Future<void> startCall(Device device) async {
    state = state.copyWith(status: CallStatus.connecting, remoteDevice: device);
    await _network.sendCallSignal(device.ip);
  }

  Future<void> acceptCall() async {
    if (state.remoteDevice == null) return;
    await _network.sendAcceptSignal(state.remoteDevice!.ip);
    await _audio.startCall(remoteIp: state.remoteDevice!.ip, remotePort: 5555);
    state = state.copyWith(status: CallStatus.active);
  }

  Future<void> endCall() async {
    await _audio.stopCall();
    state = const CallState();
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
