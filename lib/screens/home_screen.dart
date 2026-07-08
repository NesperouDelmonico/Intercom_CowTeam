import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/room_provider.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/screens/discovery_screen.dart';
import 'package:intercom_app/screens/group_screen.dart';
import 'package:intercom_app/screens/settings_screen.dart';
import 'package:intercom_app/services/permission_helper.dart';
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

  @override
  void initState() {
    super.initState();
    _wifiDirect.startListening();
    _wifiDirect.onConnectedCountChanged = (_) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _goToDiscovery() async {
    final granted = await PermissionHelper.requestWifiDirectPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Se necesitan permisos de ubicación para buscar dispositivos',
            ),
            backgroundColor: _card,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoveryScreen(wifiDirect: _wifiDirect),
      ),
    );
    if (mounted) setState(() {});
  }

  void _goToRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final deviceName = settings.value?.deviceName ?? 'Mi dispositivo';
    final avatarPath = settings.value?.avatarPath;
    final connectedCount = _wifiDirect.connectedAddresses.length;
    final room = ref.watch(roomProvider);
    final isCallActive = room.status != RoomStatus.idle;

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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _ProfileCard(deviceName: deviceName, avatarPath: avatarPath),
                const SizedBox(height: 12),
                _ConnectButton(
                  connectedCount: connectedCount,
                  onConnect: _goToDiscovery,
                ),
                const SizedBox(height: 12),
                _RoomButton(onTap: _goToRoom),
              ],
            ),
          ),

          // ── Burbuja de llamada activa ──────────────────
          // Visible solo cuando hay una sala activa y el usuario
          // volvió a home_screen sin cerrar la llamada.
          if (isCallActive)
            Positioned(
              right: 0,
              top: MediaQuery.of(context).size.height * 0.35,
              child: GestureDetector(
                onTap: _goToRoom,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: room.isReconnecting
                            ? const Color(0xFFCC8800)
                            : _cyan,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: room.isReconnecting
                                ? const Color(0xFFCC8800).withOpacity(0.4)
                                : _cyan.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            room.isReconnecting
                                ? Icons.wifi_off
                                : Icons.phone_in_talk,
                            color: const Color(0xFF001830),
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            room.roomCode ?? '',
                            style: const TextStyle(
                              color: Color(0xFF001830),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Badge contador de miembros
                    Positioned(
                      top: -6,
                      left: -6,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        decoration: BoxDecoration(
                          color: _bg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: room.isReconnecting
                                ? const Color(0xFFCC8800)
                                : _cyan,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${room.members.values.where((m) => m.isOnline).length}',
                            style: TextStyle(
                              color: room.isReconnecting
                                  ? const Color(0xFFCC8800)
                                  : _cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
  final int connectedCount;
  final VoidCallback onConnect;

  const _ConnectButton({required this.connectedCount, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final hasConnections = connectedCount > 0;
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
                        ? 'Dispositivos conectados: $connectedCount'
                        : 'Buscar via WiFi Direct',
                    style: TextStyle(
                      color: hasConnections ? _green.withOpacity(0.8) : _muted,
                      fontSize: 11,
                    ),
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
