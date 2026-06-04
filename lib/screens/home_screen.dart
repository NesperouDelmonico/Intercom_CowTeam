import 'package:flutter/material.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/screens/discovery_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Device? _connectedDevice;

  Future<void> _openDiscovery() async {
    final device = await Navigator.push<Device>(
      context,
      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
    );
    if (device != null) {
      setState(() => _connectedDevice = device);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Intercom')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _connectedDevice != null ? Icons.wifi_calling : Icons.wifi_off,
              size: 80,
              color: _connectedDevice != null ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _connectedDevice != null
                  ? 'Conectado a: ${_connectedDevice!.name}'
                  : 'Sin conexión',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _openDiscovery,
              icon: const Icon(Icons.search),
              label: const Text('Buscar dispositivos'),
            ),
          ],
        ),
      ),
    );
  }
}
