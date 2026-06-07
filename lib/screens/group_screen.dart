import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/room_provider.dart';
import 'package:intercom_app/screens/discovery_screen.dart';
import 'package:intercom_app/models/device.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key});

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider);
    final isActive = room.status != RoomStatus.idle;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Sala grupal'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _cyan),
          onPressed: () async {
            if (isActive) {
              await ref.read(roomProvider.notifier).leaveRoom();
            }
            if (context.mounted) Navigator.pop(context);
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado de la sala
            _RoomStatusCard(room: room, elapsed: _elapsed, fmt: _fmt),
            const SizedBox(height: 12),

            if (room.status == RoomStatus.idle) ...[
              // Crear sala
              ElevatedButton.icon(
                onPressed: () => ref.read(roomProvider.notifier).createRoom(),
                icon: const Icon(Icons.add),
                label: const Text('Crear sala'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              // Unirse buscando
              OutlinedButton.icon(
                onPressed: () async {
                  final device = await Navigator.push<Device>(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                  );
                  if (device != null && context.mounted) {
                    ref.read(roomProvider.notifier).joinRoom(device.ip);
                  }
                },
                icon: const Icon(Icons.search, color: _cyan),
                label: const Text(
                  'Unirse a sala',
                  style: TextStyle(color: _cyan),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _cyan),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],

            if (isActive) ...[
              const SizedBox(height: 4),
              // Lista de miembros
              const Text(
                'Miembros',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: room.members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = room.members[i];
                    final isFirst = i == 0 && room.isHost;
                    return _MemberTile(device: m, isHost: isFirst);
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Colgar
              ElevatedButton.icon(
                onPressed: () => ref.read(roomProvider.notifier).leaveRoom(),
                icon: const Icon(Icons.call_end),
                label: const Text('Salir de la sala'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC2222),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomStatusCard extends StatelessWidget {
  final RoomState room;
  final Duration elapsed;
  final String Function(Duration) fmt;

  const _RoomStatusCard({
    required this.room,
    required this.elapsed,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = room.status != RoomStatus.idle;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? _cyan.withOpacity(0.5) : _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? _cyan.withOpacity(0.1) : _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? _cyan.withOpacity(0.5) : _border,
              ),
            ),
            child: Icon(
              isActive ? Icons.group : Icons.group_outlined,
              color: isActive ? _cyan : _muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.status == RoomStatus.idle
                      ? 'Sin sala activa'
                      : room.status == RoomStatus.hosting
                      ? 'Sala activa · Código: ${room.roomCode}'
                      : 'Sala activa · Invitado',
                  style: TextStyle(
                    color: isActive ? _cyan : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? '${room.members.length} miembro(s) · ${fmt(elapsed)}'
                      : 'Crea o únete a una sala',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan,
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Device device;
  final bool isHost;

  const _MemberTile({required this.device, required this.isHost});

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
              border: Border.all(color: isHost ? _cyan : _border, width: 1.5),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: isHost ? _cyan : _muted,
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
                Row(
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _cyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _cyan.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'Host',
                          style: TextStyle(color: _cyan, fontSize: 9),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  device.ip,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(Icons.mic, color: _muted, size: 16),
        ],
      ),
    );
  }
}
