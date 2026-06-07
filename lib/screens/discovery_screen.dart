import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/services/discovery_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/providers/settings_provider.dart';

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
  final DiscoveryService _discovery = DiscoveryService();
  final List<Device> _devices = [];
  String _myIp = '';
  bool _scanning = false;
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _getMyIp();
  }

  Future<void> _getMyIp() async {
    final ip = await NetworkInfo().getWifiIP();
    setState(() => _myIp = ip ?? 'desconocida');
  }

  Future<bool> _requestPermissions() async {
    final location = await Permission.locationWhenInUse.request();
    return !location.isDenied && !location.isPermanentlyDenied;
  }

  Future<void> _startScan() async {
    final granted = await _requestPermissions();
    if (!granted) return;

    setState(() {
      _scanning = true;
      _devices.clear();
    });
    _radarController.repeat();

    _discovery.onDeviceFound = (device) {
      setState(() => _devices.add(device));
    };

    final info = await DeviceInfoPlugin().androidInfo;
    final settings = ref.read(settingsProvider).value;
    final name = settings?.deviceName ?? 'Android-${_myIp.split('.').last}';
    await _discovery.start(name);
  }

  void _stopScan() {
    _discovery.stop();
    _radarController.stop();
    setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _radarController.dispose();
    _discovery.stop();
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
          onPressed: () => Navigator.pop(context),
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
            _StatusCard(scanning: _scanning, myIp: _myIp),
            const SizedBox(height: 12),
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
                    onPressed: _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar dispositivos'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 24,
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            if (_scanning && _devices.isEmpty) ...[
              const SizedBox(height: 8),
              _RadarWidget(controller: _radarController),
              const SizedBox(height: 16),
              const Text(
                'Esperando dispositivos...',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DeviceItem(device: _devices[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool scanning;
  final String myIp;
  const _StatusCard({required this.scanning, required this.myIp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scanning ? _cyan.withOpacity(0.5) : _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scanning ? _cyan.withOpacity(0.1) : _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scanning ? _cyan.withOpacity(0.5) : _border,
              ),
            ),
            child: Icon(
              scanning ? Icons.radar : Icons.search,
              color: scanning ? _cyan : _muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scanning ? 'Buscando...' : 'Listo para buscar',
                  style: TextStyle(
                    color: scanning ? _cyan : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  scanning ? 'Tu IP: $myIp' : 'Presiona buscar',
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
              color: scanning ? _cyan : _muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarWidget extends StatelessWidget {
  final AnimationController controller;
  const _RadarWidget({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SizedBox(
          width: 120,
          height: 120,
          child: CustomPaint(painter: _RadarPainter(controller.value)),
        );
      },
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

    final sweepPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final angle = progress * 2 * 3.14159;
    canvas.drawLine(
      center,
      Offset(
            center.dx +
                size.width /
                    2 *
                    0.9 *
                    (1 * 1.0) *
                    (angle.toString().isNotEmpty ? 1 : 1),
            center.dy,
          ) +
          Offset(
            (size.width / 2 * 0.9 * (1.0)) *
                    (angle.toString().length > 0 ? 1 : 1) -
                size.width / 2 * 0.9,
            0,
          ),
      sweepPaint,
    );

    final dotPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4, dotPaint);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

class _DeviceItem extends StatelessWidget {
  final Device device;
  const _DeviceItem({required this.device});

  @override
  Widget build(BuildContext context) {
    final initials = device.name.length >= 2
        ? device.name.substring(0, 2).toUpperCase()
        : device.name.toUpperCase();

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
                  device.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.ip,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, device),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Llamar'),
          ),
        ],
      ),
    );
  }
}
