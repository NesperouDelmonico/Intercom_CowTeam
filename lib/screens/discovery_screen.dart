import 'package:flutter/material.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/services/discovery_service.dart';
import 'package:network_info_plus/network_info_plus.dart';

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

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
    });

    _discovery.onDeviceFound = (device) {
      setState(() => _devices.add(device));
    };

    await _discovery.start('Mi teléfono');
  }

  void _stopScan() {
    _discovery.stop();
    setState(() => _scanning = false);
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
            const SizedBox(height: 24),
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
