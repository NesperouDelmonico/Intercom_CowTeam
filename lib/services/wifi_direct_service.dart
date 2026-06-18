import 'dart:async';
import 'package:flutter/services.dart';

class WifiDirectPeer {
  final String name;
  final String address;
  final int status;

  const WifiDirectPeer({
    required this.name,
    required this.address,
    required this.status,
  });
}

class WifiDirectConnectionInfo {
  final bool isGroupOwner;
  final String groupOwnerAddress;

  const WifiDirectConnectionInfo({
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });
}

class WifiDirectService {
  static const _method = MethodChannel('com.example.intercom_app/wifidirect');
  static const _events = EventChannel(
    'com.example.intercom_app/wifidirect_events',
  );

  StreamSubscription? _eventSub;

  // Callbacks
  void Function(List<WifiDirectPeer> peers)? onPeersChanged;
  void Function(WifiDirectConnectionInfo info)? onConnected;
  void Function()? onDisconnected;

  void startListening() {
    _eventSub = _events.receiveBroadcastStream().listen((event) {
      final type = event['type'] as String;
      final data = event['data'];

      switch (type) {
        case 'peersChanged':
          final peers = (data as List).map((p) {
            return WifiDirectPeer(
              name: p['name'] as String,
              address: p['address'] as String,
              status: p['status'] as int,
            );
          }).toList();
          onPeersChanged?.call(peers);
          break;
        case 'connected':
          onConnected?.call(
            WifiDirectConnectionInfo(
              isGroupOwner: data['isGroupOwner'] as bool,
              groupOwnerAddress: data['groupOwnerAddress'] as String,
            ),
          );
          break;
        case 'disconnected':
          onDisconnected?.call();
          break;
      }
    });
  }

  Future<void> discoverPeers() async {
    await _method.invokeMethod('discoverPeers');
  }

  Future<void> stopDiscovery() async {
    await _method.invokeMethod('stopDiscovery');
  }

  Future<void> connect(String deviceAddress) async {
    await _method.invokeMethod('connect', {'address': deviceAddress});
  }

  Future<void> disconnect() async {
    await _method.invokeMethod('disconnect');
  }

  void dispose() {
    _eventSub?.cancel();
  }

  Future<void> createGroup() async {
    await _method.invokeMethod('createGroup');
  }

  Future<void> removeGroup() async {
    await _method.invokeMethod('removeGroup');
  }

  Future<Map?> requestGroupInfo() async {
    return await _method.invokeMethod<Map>('requestGroupInfo');
  }

  Future<List<WifiDirectPeer>> requestConnectedPeers() async {
    final result = await _method.invokeMethod<List>('requestConnectedPeers');
    if (result == null) return [];
    return result
        .map(
          (p) => WifiDirectPeer(
            name: p['name'] as String,
            address: p['address'] as String,
            status: 0,
          ),
        )
        .toList();
  }

  Future<String?> createGroupAndWait() async {
    try {
      final result = await _method.invokeMethod<String>('createGroupAndWait');
      return result;
    } catch (e) {
      return null;
    }
  }
}
