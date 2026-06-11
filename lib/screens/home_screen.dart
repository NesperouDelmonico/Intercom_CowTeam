import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/screens/discovery_screen.dart';
import 'package:intercom_app/screens/group_screen.dart';
import 'package:intercom_app/screens/settings_screen.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _connectedDeviceName;
  bool _isConnected = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final deviceName = settings.value?.deviceName ?? 'Mi dispositivo';
    final avatarPath = settings.value?.avatarPath;

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
            onPressed: () {}, // programar después
          ),
        ],
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
            const SizedBox(height: 8),

            // Tarjeta de perfil (rosado en mockup)
            _ProfileCard(deviceName: deviceName, avatarPath: avatarPath),
            const SizedBox(height: 12),

            // Botón conectar con dispositivo (azul en mockup)
            _ConnectButton(
              isConnected: _isConnected,
              connectedDeviceName: _connectedDeviceName,
              onConnect: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                );
                if (result != null && context.mounted) {
                  setState(() {
                    _isConnected = true;
                    _connectedDeviceName = result.name ?? 'Dispositivo';
                  });
                }
              },
              onDisconnect: () {
                setState(() {
                  _isConnected = false;
                  _connectedDeviceName = null;
                });
              },
            ),
            const SizedBox(height: 12),

            // Botón sala (negro en mockup)
            _RoomButton(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupScreen()),
              ),
            ),
          ],
        ),
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
          // Avatar
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
          // Nombre
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
  final bool isConnected;
  final String? connectedDeviceName;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ConnectButton({
    required this.isConnected,
    required this.onConnect,
    required this.onDisconnect,
    this.connectedDeviceName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnected ? onDisconnect : onConnect,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isConnected
              ? const Color(0xFF00CC44).withOpacity(0.15)
              : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConnected
                ? const Color(0xFF00CC44).withOpacity(0.6)
                : _border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF00CC44).withOpacity(0.2)
                    : _bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isConnected
                      ? const Color(0xFF00CC44).withOpacity(0.5)
                      : _border,
                ),
              ),
              child: Icon(
                isConnected ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                color: isConnected ? const Color(0xFF00CC44) : _muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected
                        ? 'Conectado a: $connectedDeviceName'
                        : 'Conectar dispositivo',
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF00CC44)
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConnected
                        ? 'Toca para desconectar'
                        : 'Buscar via WiFi Direct',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              isConnected
                  ? Icons.check_circle_outline
                  : Icons.arrow_forward_ios,
              color: isConnected ? const Color(0xFF00CC44) : _muted,
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
