import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/providers/call_provider.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/services/wifi_direct_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as dart_math;
import 'dart:io';
import 'dart:async';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  final _wifiDirect = WifiDirectService();
  final List<WifiDirectPeer> _peers = [];
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingAddress;
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _wifiDirect.startListening();
    _wifiDirect.onPeersChanged = (peers) {
      setState(
        () => _peers
          ..clear()
          ..addAll(peers),
      );
    };

    _wifiDirect.onConnected = (info) async {
      final settings = ref.read(settingsProvider).value;
      final name = settings?.deviceName ?? 'Dispositivo';

      String remoteIp;
      if (info.isGroupOwner) {
        // Soy el Group Owner — el cliente se conectará a mí en 192.168.49.1
        // Espero que el cliente me envíe su IP por UDP
        remoteIp = await _waitForClientIp();
      } else {
        remoteIp = info.groupOwnerAddress;

        // Anunciarse al Group Owner
        final announceSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
        for (int i = 0; i < 5; i++) {
          announceSocket.send(
            'HELLO:client'.codeUnits,
            InternetAddress(remoteIp),
            5558,
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }
        announceSocket.close();
      }

      final device = Device(name: name, ip: remoteIp, port: 5555);

      if (context.mounted) Navigator.pop(context, device);
    };
  }

  Future<String> _waitForClientIp() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      5558,
      reuseAddress: true,
    );

    final completer = Completer<String>();

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) {
          final msg = String.fromCharCodes(dg.data);
          if (msg.startsWith('HELLO:')) {
            final ip = dg.address.address;
            if (!completer.isCompleted) completer.complete(ip);
          }
        }
      }
    });

    // Timeout de 10 segundos
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete('192.168.49.2');
    });

    final result = await completer.future;
    socket.close();
    return result;
  }

  Future<void> _requestPermissionsAndScan() async {
    final location = await Permission.locationWhenInUse.request();
    if (location.isDenied) return;

    setState(() {
      _scanning = true;
      _peers.clear();
    });
    _radarController.repeat();

    try {
      await _wifiDirect.discoverPeers();
    } catch (e) {
      setState(() => _scanning = false);
      _radarController.stop();
    }
  }

  void _stopScan() {
    _wifiDirect.stopDiscovery();
    _radarController.stop();
    setState(() => _scanning = false);
  }

  Future<void> _connectToPeer(WifiDirectPeer peer) async {
    setState(() {
      _connecting = true;
      _connectingAddress = peer.address;
    });
    try {
      await _wifiDirect.connect(peer.address);
    } catch (e) {
      setState(() {
        _connecting = false;
        _connectingAddress = null;
      });
    }
  }

  @override
  void dispose() {
    _radarController.dispose();
    _wifiDirect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Buscar dispositivos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _cyan),
          onPressed: () {
            _wifiDirect.stopDiscovery();
            Navigator.pop(context);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _scanning ? _cyan.withOpacity(0.5) : _border,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _scanning ? _cyan.withOpacity(0.1) : _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _scanning ? _cyan.withOpacity(0.5) : _border,
                      ),
                    ),
                    child: Icon(
                      _scanning ? Icons.wifi_tethering : Icons.wifi_off,
                      color: _scanning ? _cyan : _muted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _scanning
                              ? 'WiFi Direct activo'
                              : 'Listo para buscar',
                          style: TextStyle(
                            color: _scanning ? _cyan : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _scanning
                              ? 'Buscando dispositivos cercanos'
                              : 'Sin router necesario',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _scanning ? _cyan : _muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Botón buscar/detener
            _scanning
                ? OutlinedButton.icon(
                    onPressed: _stopScan,
                    icon: const Icon(Icons.close, color: Color(0xFFCC4444)),
                    label: const Text(
                      'Detener búsqueda',
                      style: TextStyle(color: Color(0xFFCC4444)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCC4444)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _requestPermissionsAndScan,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Buscar con WiFi Direct'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 24,
                      ),
                    ),
                  ),
            const SizedBox(height: 16),

            if (_scanning && _peers.isEmpty) ...[
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _radarController,
                builder: (context, _) => SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _RadarPainter(_radarController.value),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Buscando dispositivos cercanos...',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'Asegúrate de que el otro teléfono\ntambién esté buscando',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],

            if (_peers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _peers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final peer = _peers[i];
                    final isConnecting =
                        _connecting && _connectingAddress == peer.address;
                    final initials = peer.name.length >= 2
                        ? peer.name.substring(0, 2).toUpperCase()
                        : peer.name.toUpperCase();

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _bg,
                              border: Border.all(color: _cyan, width: 1),
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: _cyan,
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
                                Text(
                                  peer.status == 0
                                      ? 'Conectado'
                                      : peer.status == 3
                                      ? 'Disponible'
                                      : 'Visible',
                                  style: TextStyle(
                                    color: peer.status == 0 ? _cyan : _muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: _cyan,
                                    strokeWidth: 2,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: () => _connectToPeer(peer),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                  child: const Text('Conectar'),
                                ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      paint.color = const Color(0xFF00E5FF).withOpacity(0.15 * i);
      paint.strokeWidth = 0.8;
      canvas.drawCircle(center, size.width / 2 * i / 3, paint);
    }

    final angle = progress * 2 * 3.14159;
    final sweepPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      center,
      Offset(
        center.dx + size.width / 2 * 0.9 * dart_math.cos(angle),
        center.dy + size.width / 2 * 0.9 * dart_math.sin(angle),
      ),
      sweepPaint,
    );

    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF00E5FF));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
