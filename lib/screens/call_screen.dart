import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/call_state.dart';
import 'package:intercom_app/providers/call_provider.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider);

    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.idle && prev?.status != CallStatus.idle) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Llamada')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: Colors.indigo),
            const SizedBox(height: 16),
            Text(
              call.status == CallStatus.connecting
                  ? 'Conectando...'
                  : 'En llamada con ${call.remoteDevice?.name ?? ''}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 48),
            FloatingActionButton.extended(
              backgroundColor: Colors.red,
              onPressed: () {
                ref.read(callProvider.notifier).endCall();
              },
              icon: const Icon(Icons.call_end, color: Colors.white),
              label: const Text(
                'Colgar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
