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
  final List<String> remoteAddresses;

  const WifiDirectConnectionInfo({
    required this.isGroupOwner,
    required this.groupOwnerAddress,
    this.remoteAddresses = const [],
  });
}

/// Singleton — el estado de conexión persiste sin importar
/// cuántas veces se navegue entre pantallas.
class WifiDirectService {
  static final WifiDirectService _instance = WifiDirectService._internal();
  factory WifiDirectService() => _instance;
  WifiDirectService._internal();

  static const _method = MethodChannel('com.example.intercom_app/wifidirect');
  static const _events = EventChannel(
    'com.example.intercom_app/wifidirect_events',
  );

  StreamSubscription? _eventSub;
  bool _listening = false;

  // Estado persistente — direcciones de dispositivos conectados
  final Set<String> connectedAddresses = {};
  // Caché de nombres por address, para mostrar en discovery aunque
  // ya no aparezcan en el último escaneo de peers
  final Map<String, String> _nameCache = {};

  // Callbacks (se sobrescriben por pantalla, pero el estado persiste)
  void Function(List<WifiDirectPeer> peers)? onPeersChanged;
  void Function(WifiDirectConnectionInfo info)? onConnected;
  void Function()? onDisconnected;
  // Notifica cualquier cambio en connectedAddresses, útil para
  // refrescar contadores en otras pantallas (ej. home_screen)
  void Function(int count)? onConnectedCountChanged;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _eventSub = _events.receiveBroadcastStream().listen((event) {
      final type = event['type'] as String;
      final data = event['data'];

      switch (type) {
        case 'peersChanged':
          final peers = (data as List).map((p) {
            final peer = WifiDirectPeer(
              name: p['name'] as String,
              address: p['address'] as String,
              status: p['status'] as int,
            );
            _nameCache[peer.address] = peer.name;
            return peer;
          }).toList();
          onPeersChanged?.call(peers);
          break;
        case 'connected':
          final remoteRaw = data['remoteAddresses'] as List? ?? [];
          final remoteAddresses = remoteRaw.map((e) => e as String).toList();

          final info = WifiDirectConnectionInfo(
            isGroupOwner: data['isGroupOwner'] as bool,
            groupOwnerAddress: data['groupOwnerAddress'] as String,
            remoteAddresses: remoteAddresses,
          );

          // Marcar TODAS las direcciones remotas reales como conectadas.
          // Esto resuelve el caso del receptor: aunque él no inició
          // connect(), ahora sabe exactamente con qué MAC se conectó.
          var changed = false;
          for (final addr in remoteAddresses) {
            if (!connectedAddresses.contains(addr)) {
              connectedAddresses.add(addr);
              changed = true;
            }
          }
          if (changed) {
            onConnectedCountChanged?.call(connectedAddresses.length);
          }
          onConnected?.call(info);
          break;
        case 'disconnected':
          connectedAddresses.clear();
          onConnectedCountChanged?.call(connectedAddresses.length);
          onDisconnected?.call();
          break;
      }
    });
  }

  /// Marca una dirección como conectada (llamar tras connect() exitoso,
  /// o tras detectar un peer con status conectado).
  void markConnected(String address) {
    if (connectedAddresses.add(address)) {
      onConnectedCountChanged?.call(connectedAddresses.length);
    }
  }

  void markDisconnected(String address) {
    if (connectedAddresses.remove(address)) {
      onConnectedCountChanged?.call(connectedAddresses.length);
    }
  }

  String? nameFor(String address) => _nameCache[address];

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
    connectedAddresses.clear();
    onConnectedCountChanged?.call(connectedAddresses.length);
  }

  void dispose() {
    _eventSub?.cancel();
    _listening = false;
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
