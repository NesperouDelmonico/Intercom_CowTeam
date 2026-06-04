import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/call_state.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/providers/call_provider.dart';
import 'package:intercom_app/screens/call_screen.dart';
import 'package:intercom_app/screens/discovery_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider);

    // Navegar a CallScreen cuando la llamada se activa
    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.active &&
          prev?.status != CallStatus.active) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CallScreen()),
          (route) => route.isFirst,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Intercom')),
      body: Center(
        child: call.status == CallStatus.incoming
            ? _IncomingCallWidget(
                device: call.remoteDevice!,
                onAccept: () => ref.read(callProvider.notifier).acceptCall(),
                onReject: () => ref.read(callProvider.notifier).endCall(),
              )
            : _IdleWidget(
                isConnecting: call.status == CallStatus.connecting,
                onSearch: () async {
                  final device = await Navigator.push<Device>(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                  );
                  if (device != null && context.mounted) {
                    ref.read(callProvider.notifier).startCall(device);
                  }
                },
              ),
      ),
    );
  }
}

class _IdleWidget extends StatelessWidget {
  final bool isConnecting;
  final VoidCallback onSearch;

  const _IdleWidget({required this.isConnecting, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isConnecting ? Icons.wifi_calling : Icons.wifi_off,
          size: 80,
          color: isConnecting ? Colors.amber : Colors.grey,
        ),
        const SizedBox(height: 16),
        Text(
          isConnecting ? 'Llamando...' : 'Sin conexión',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: isConnecting ? null : onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Buscar dispositivos'),
        ),
      ],
    );
  }
}

class _IncomingCallWidget extends StatelessWidget {
  final Device device;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallWidget({
    required this.device,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.phone_in_talk, size: 80, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Llamada de ${device.name}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(device.ip, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FloatingActionButton(
              heroTag: 'reject',
              backgroundColor: Colors.red,
              onPressed: onReject,
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
            const SizedBox(width: 48),
            FloatingActionButton(
              heroTag: 'accept',
              backgroundColor: Colors.green,
              onPressed: onAccept,
              child: const Icon(Icons.call, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}
