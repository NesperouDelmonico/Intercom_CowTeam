import 'package:flutter/material.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/services/discovery_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final DiscoveryService _discovery = DiscoveryService();
  final List<Device> _devices = [];
  String _myIp = '';
  bool _scanning = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _getMyIp();
  }

  Future<void> _getMyIp() async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    setState(() => _myIp = ip ?? 'desconocida');
  }

  Future<bool> _requestPermissions() async {
    // Solo pedir ubicación — funciona en todas las versiones de Android
    final location = await Permission.locationWhenInUse.request();
    if (location.isDenied || location.isPermanentlyDenied) {
      return false;
    }
    return true;
  }

  Future<void> _startScan() async {
    final granted = await _requestPermissions();

    if (!granted) {
      setState(
        () => _status = 'Permisos necesarios. Ve a Ajustes y actívalos.',
      );
      return;
    }

    setState(() {
      _scanning = true;
      _devices.clear();
      _status = 'Buscando...';
    });

    _discovery.onDeviceFound = (device) {
      setState(() => _devices.add(device));
    };

    final deviceName = 'Android-${_myIp.split('.').last}';
    await _discovery.start(deviceName);
  }

  void _stopScan() {
    _discovery.stop();
    setState(() {
      _scanning = false;
      _status = '';
    });
  }

  @override
  void dispose() {
    _discovery.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar dispositivos')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Tu IP: $_myIp', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _scanning ? _stopScan : _startScan,
              icon: Icon(_scanning ? Icons.stop : Icons.search),
              label: Text(_scanning ? 'Detener' : 'Buscar dispositivos'),
            ),
            const SizedBox(height: 8),
            if (_status.isNotEmpty)
              Text(_status, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            if (_scanning && _devices.isEmpty)
              const CircularProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(device.name),
                    subtitle: Text(device.ip),
                    trailing: ElevatedButton(
                      onPressed: () => Navigator.pop(context, device),
                      child: const Text('Conectar'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
