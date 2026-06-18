import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/screens/group_screen.dart';
import 'package:intercom_app/screens/settings_screen.dart';
import 'package:intercom_app/services/wifi_direct_service.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);
const _green = Color(0xFF00CC44);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final WifiDirectService _wifiDirect = WifiDirectService();
  final List<WifiDirectPeer> _connectedPeers = [];
  Timer? _peersTimer;

  @override
  void initState() {
    super.initState();
    _wifiDirect.startListening();

    // Escuchar eventos de conexión/desconexión
    _wifiDirect.onConnected = (info) {
      _refreshPeers();
    };
    _wifiDirect.onDisconnected = () {
      setState(() => _connectedPeers.clear());
    };
    _wifiDirect.onPeersChanged = (_) {
      _refreshPeers();
    };

    // Refrescar lista de peers cada 3 segundos
    _peersTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshPeers(),
    );
  }

  Future<void> _refreshPeers() async {
    try {
      final peers = await _wifiDirect.requestConnectedPeers();
      if (mounted) {
        setState(() {
          _connectedPeers.clear();
          _connectedPeers.addAll(peers);
        });
      }
    } catch (_) {}
  }

  Future<void> _disconnectPeer(WifiDirectPeer peer) async {
    await _wifiDirect.disconnect();
    setState(() => _connectedPeers.remove(peer));
  }

  Future<void> _disconnectAll() async {
    await _wifiDirect.disconnect();
    setState(() => _connectedPeers.clear());
  }

  void _showConnectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ConnectSheet(wifiDirect: _wifiDirect),
    );
  }

  @override
  void dispose() {
    _peersTimer?.cancel();
    _wifiDirect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final deviceName = settings.value?.deviceName ?? 'Mi dispositivo';
    final avatarPath = settings.value?.avatarPath;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text(
          'Intercom by CowTeam',
          style: TextStyle(
            color: _cyan,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _cyan),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: _cyan),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // Tarjeta de perfil
            _ProfileCard(deviceName: deviceName, avatarPath: avatarPath),
            const SizedBox(height: 12),

            // Botón conectar
            _ConnectButton(
              hasConnections: _connectedPeers.isNotEmpty,
              onConnect: () => _showConnectSheet(context),
            ),
            // Lista de dispositivos conectados
            if (_connectedPeers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._connectedPeers.map(
                (peer) => _PeerCard(
                  peer: peer,
                  onDisconnect: () => _disconnectPeer(peer),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Botón sala
            _RoomButton(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de perfil ──────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String deviceName;
  final String? avatarPath;

  const _ProfileCard({required this.deviceName, this.avatarPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _bg,
              border: Border.all(color: _cyan, width: 2),
              image: avatarPath != null
                  ? DecorationImage(
                      image: FileImage(File(avatarPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarPath == null
                ? const Icon(Icons.person, color: _cyan, size: 40)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            deviceName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tu dispositivo',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Botón conectar ─────────────────────────────────────────
class _ConnectButton extends StatelessWidget {
  final bool hasConnections;
  final VoidCallback onConnect;

  const _ConnectButton({required this.hasConnections, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onConnect,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasConnections ? _green.withOpacity(0.1) : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasConnections ? _green.withOpacity(0.5) : _border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasConnections ? _green.withOpacity(0.15) : _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasConnections ? _green.withOpacity(0.5) : _border,
                ),
              ),
              child: Icon(
                hasConnections
                    ? Icons.wifi_tethering
                    : Icons.wifi_tethering_off,
                color: hasConnections ? _green : _muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasConnections
                        ? 'WiFi Direct activo'
                        : 'Conectar dispositivo',
                    style: TextStyle(
                      color: hasConnections ? _green : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasConnections
                        ? 'Toca para buscar más dispositivos'
                        : 'Buscar via WiFi Direct',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: hasConnections ? _green : _muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de peer conectado ──────────────────────────────
class _PeerCard extends StatelessWidget {
  final WifiDirectPeer peer;
  final VoidCallback onDisconnect;

  const _PeerCard({required this.peer, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final initials = peer.name.length >= 2
        ? peer.name.substring(0, 2).toUpperCase()
        : peer.name.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          // Avatar con iniciales
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _bg,
              border: Border.all(color: _green, width: 1.5),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: _green,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                      'Conectado via WiFi Direct',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botón desconectar
          GestureDetector(
            onTap: onDisconnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFCC2222).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCC2222).withOpacity(0.5),
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
          ),
        ],
      ),
    );
  }
}

// ── Botón sala grupal ──────────────────────────────────────
class _RoomButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RoomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cyan.withOpacity(0.4)),
              ),
              child: const Icon(Icons.group_outlined, color: _cyan, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sala de comunicación',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Crear o unirse a una sala',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: _muted, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ConnectSheet extends StatefulWidget {
  final WifiDirectService wifiDirect;
  const _ConnectSheet({required this.wifiDirect});

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  List<WifiDirectPeer> _peers = [];
  bool _scanning = false;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    widget.wifiDirect.onPeersChanged = (peers) {
      if (mounted) setState(() => _peers = peers);
    };
    _scan();
  }

  @override
  void dispose() {
    widget.wifiDirect.onPeersChanged = null;
    widget.wifiDirect.stopDiscovery();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _peers = [];
    });
    try {
      await widget.wifiDirect.discoverPeers();
    } catch (e) {
      print('DEBUG discoverPeers error: $e');
    }
    await Future.delayed(const Duration(seconds: 8));
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(WifiDirectPeer peer) async {
    setState(() => _connecting = peer.address);
    try {
      await widget.wifiDirect.connect(peer.address);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _connecting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Conectar dispositivo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_scanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: _cyan,
                    strokeWidth: 2,
                  ),
                )
              else
                GestureDetector(
                  onTap: _scan,
                  child: const Icon(Icons.refresh, color: _cyan, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _scanning
                    ? 'Buscando dispositivos cercanos...'
                    : 'No se encontraron dispositivos',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            )
          else
            ...(_peers.map((peer) {
              final isConnecting = _connecting == peer.address;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android, color: _cyan, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        peer.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: _cyan,
                              strokeWidth: 2,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () => _connect(peer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _cyan,
                              foregroundColor: const Color(0xFF001830),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            child: const Text(
                              'Conectar',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                  ],
                ),
              );
            })),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
