import 'package:flutter/material.dart';
import 'package:intercom_app/services/wifi_direct_service.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);
const _green = Color(0xFF00CC44);

class DiscoveryScreen extends StatefulWidget {
  final WifiDirectService wifiDirect;
  const DiscoveryScreen({super.key, required this.wifiDirect});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  // peersByAddress combina lo último escaneado + lo ya conectado,
  // para que la lista nunca "olvide" un dispositivo conectado
  // aunque salga del rango de escaneo.
  final Map<String, WifiDirectPeer> _peersByAddress = {};
  bool _scanning = false;
  String? _connecting;

  @override
  void initState() {
    super.initState();

    // Pre-poblar SOLO con direcciones que aún no tengan un peer real
    // en caché (evita duplicados con nombre genérico).
    for (final addr in widget.wifiDirect.connectedAddresses) {
      final cachedName = widget.wifiDirect.nameFor(addr);
      if (cachedName != null) {
        _peersByAddress[addr] = WifiDirectPeer(
          name: cachedName,
          address: addr,
          status: 0,
        );
      }
    }

    widget.wifiDirect.onPeersChanged = (peers) {
      if (!mounted) return;
      setState(() {
        for (final p in peers) {
          // Un mismo dispositivo nunca debe tener dos entradas:
          // si ya existe por address, simplemente se actualiza.
          _peersByAddress[p.address] = p;
        }
      });
    };

    widget.wifiDirect.onConnected = (info) {
      if (!mounted) return;
      if (_connecting != null) {
        widget.wifiDirect.markConnected(_connecting!);
        setState(() {});
        _connecting = null;
      }
      // Refrescar siempre — remoteAddresses puede traer conexiones
      // entrantes que no iniciamos nosotros (ya marcadas en el service).
      setState(() {});
    };

    _scan();
  }

  @override
  void dispose() {
    widget.wifiDirect.onPeersChanged = null;
    widget.wifiDirect.onConnected = null;
    widget.wifiDirect.stopDiscovery();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      await widget.wifiDirect.discoverPeers();
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 8));
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(WifiDirectPeer peer) async {
    setState(() => _connecting = peer.address);
    try {
      await widget.wifiDirect.connect(peer.address);
    } catch (_) {
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _disconnect(WifiDirectPeer peer) async {
    await widget.wifiDirect.disconnect();
    widget.wifiDirect.markDisconnected(peer.address);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final peersList = _peersByAddress.values.toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text(
          'Conectar dispositivo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _cyan),
          onPressed: () => Navigator.pop(
            context,
            widget.wifiDirect.connectedAddresses.isNotEmpty,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: _muted, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Asegúrate de que el otro dispositivo también tenga la app abierta y el WiFi activo.',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Barra de búsqueda — siempre visible, grande y táctil
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: GestureDetector(
              onTap: _scanning ? null : _scan,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _scanning ? _cyan.withOpacity(0.1) : _cyan,
                  borderRadius: BorderRadius.circular(16),
                  border: _scanning
                      ? Border.all(color: _cyan.withOpacity(0.5))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_scanning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: _cyan,
                          strokeWidth: 2.5,
                        ),
                      )
                    else
                      const Icon(
                        Icons.search,
                        color: Color(0xFF001830),
                        size: 22,
                      ),
                    const SizedBox(width: 10),
                    Text(
                      _scanning
                          ? 'Buscando dispositivos...'
                          : 'Buscar dispositivos',
                      style: TextStyle(
                        color: _scanning ? _cyan : const Color(0xFF001830),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Lista de dispositivos — persiste estado conectado
          Expanded(
            child: peersList.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          _scanning
                              ? Icons.wifi_tethering
                              : Icons.wifi_tethering_off,
                          color: _muted,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _scanning
                              ? 'Buscando dispositivos cercanos...'
                              : 'No se encontraron dispositivos',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: peersList.map((peer) {
                      final isConnecting = _connecting == peer.address;
                      final isConnected = widget.wifiDirect.connectedAddresses
                          .contains(peer.address);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isConnected ? _green.withOpacity(0.08) : _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isConnected
                                ? _green.withOpacity(0.4)
                                : _border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _bg,
                                border: Border.all(
                                  color: isConnected
                                      ? _green
                                      : _cyan.withOpacity(0.4),
                                  width: isConnected ? 1.5 : 1,
                                ),
                              ),
                              child: Icon(
                                Icons.phone_android,
                                color: isConnected ? _green : _cyan,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    peer.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isConnected) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _green,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Conectado',
                                          style: TextStyle(
                                            color: _green,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isConnected)
                              GestureDetector(
                                onTap: () => _disconnect(peer),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFCC2222,
                                    ).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFCC2222,
                                      ).withOpacity(0.5),
                                    ),
                                  ),
                                  child: const Text(
                                    'Desconectar',
                                    style: TextStyle(
                                      color: Color(0xFFCC4444),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                            else if (isConnecting)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: _cyan,
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              ElevatedButton(
                                onPressed: () => _connect(peer),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _cyan,
                                  foregroundColor: const Color(0xFF001830),
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                                child: const Text('Conectar'),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
