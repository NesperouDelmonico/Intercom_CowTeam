import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/call_state.dart';
import 'package:intercom_app/models/device.dart';
import 'package:intercom_app/providers/call_provider.dart';
import 'package:intercom_app/screens/call_screen.dart';
import 'package:intercom_app/screens/discovery_screen.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider);

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
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Intercom'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _cyan),
            onPressed: () {},
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
      body: call.status == CallStatus.incoming
          ? _IncomingCallScreen(
              device: call.remoteDevice!,
              onAccept: () => ref.read(callProvider.notifier).acceptCall(),
              onReject: () => ref.read(callProvider.notifier).endCall(),
            )
          : _IdleScreen(
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
    );
  }
}

class _IdleScreen extends StatelessWidget {
  final bool isConnecting;
  final VoidCallback onSearch;

  const _IdleScreen({required this.isConnecting, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(isConnecting: isConnecting),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: isConnecting ? null : onSearch,
            icon: const Icon(Icons.search),
            label: Text(isConnecting ? 'Llamando...' : 'Buscar dispositivos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          _AdvancedCard(),
          const SizedBox(height: 12),
          _GroupCard(),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool isConnecting;
  const _StatusCard({required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Icon(
              isConnecting ? Icons.wifi_calling : Icons.link_off,
              color: isConnecting ? _cyan : _muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnecting ? 'Conectando...' : 'Desconectado',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnecting ? 'Esperando respuesta...' : 'Toca para buscar',
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
              color: isConnecting ? _cyan : _muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedCard extends StatefulWidget {
  @override
  State<_AdvancedCard> createState() => _AdvancedCardState();
}

class _AdvancedCardState extends State<_AdvancedCard> {
  bool _expanded = false;
  final _ipController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: _cyan, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conexión avanzada',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'IP manual o código de sala',
                          style: TextStyle(color: _muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _muted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '192.168.1.x',
                        hintStyle: const TextStyle(color: _muted),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Conectar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, color: _cyan, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sala grupal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Conectar varios dispositivos',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: const Text(
              'Próximamente',
              style: TextStyle(color: _muted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingCallScreen extends StatelessWidget {
  final Device device;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallScreen({
    required this.device,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _card,
              border: Border.all(color: const Color(0xFF00CC66), width: 2),
            ),
            child: const Icon(
              Icons.phone_in_talk,
              color: Color(0xFF00CC66),
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            device.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(device.ip, style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 8),
          const Text(
            'Llamada entrante',
            style: TextStyle(color: _cyan, fontSize: 13),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  GestureDetector(
                    onTap: onReject,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFCC2222),
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rechazar',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 60),
              Column(
                children: [
                  GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00CC44),
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aceptar',
                    style: TextStyle(color: Color(0xFF00CC44), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
