import 'package:intercom_app/models/device.dart';

enum CallStatus { idle, connecting, active, ended }

class CallState {
  final CallStatus status;
  final Device? remoteDevice;

  const CallState({this.status = CallStatus.idle, this.remoteDevice});

  CallState copyWith({CallStatus? status, Device? remoteDevice}) {
    return CallState(
      status: status ?? this.status,
      remoteDevice: remoteDevice ?? this.remoteDevice,
    );
  }
}
