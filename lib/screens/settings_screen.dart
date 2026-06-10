import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intercom_app/services/settings_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intercom_app/providers/settings_provider.dart';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);
const _ch = MethodChannel('com.example.intercom_app/audio');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  final _portController = TextEditingController();
  bool _noiseSuppress = true;
  bool _echoCancel = true;
  bool _keepScreen = true;
  String? _avatarPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final fallback = info.model;
    final name = await SettingsService.getDeviceName(fallback);
    final port = await SettingsService.getPort();
    final noise = await SettingsService.getNoiseSuppress();
    final echo = await SettingsService.getEchoCancel();
    final screen = await SettingsService.getKeepScreen();

    // Cargar avatar si existe
    final dir = await getApplicationDocumentsDirectory();
    final avatarFile = File('${dir.path}/avatar.jpg');

    setState(() {
      _nameController.text = name;
      _portController.text = port.toString();
      _noiseSuppress = noise;
      _echoCancel = echo;
      _keepScreen = screen;
      _avatarPath = avatarFile.existsSync() ? avatarFile.path : null;
      _loading = false;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 100,
      maxHeight: 100,
      imageQuality: 60,
    );
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/avatar.jpg');
    await File(picked.path).copy(dest.path);
    setState(() => _avatarPath = dest.path);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final port = int.tryParse(_portController.text) ?? 5555;

    if (name.isEmpty) {
      _showSnack('El nombre no puede estar vacío');
      return;
    }
    if (port < 1024 || port > 65535) {
      _showSnack('Puerto inválido (1024–65535)');
      return;
    }

    await SettingsService.setDeviceName(name);
    await SettingsService.setPort(port);
    await SettingsService.setNoiseSuppress(_noiseSuppress);
    await SettingsService.setEchoCancel(_echoCancel);
    await SettingsService.setKeepScreen(_keepScreen);

    if (context.mounted) {
      _showSnack('Ajustes guardados');
      await ref.read(settingsProvider.notifier).reload();
      Navigator.pop(context);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ajustes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _cyan),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Guardar',
              style: TextStyle(color: _cyan, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _card,
                        border: Border.all(color: _cyan, width: 2),
                        image: _avatarPath != null
                            ? DecorationImage(
                                image: FileImage(File(_avatarPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _avatarPath == null
                          ? const Icon(Icons.person, color: _cyan, size: 40)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _cyan,
                          border: Border.all(color: _bg, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: Color(0xFF001830),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Toca para cambiar foto',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 24),

            // Sección: Dispositivo
            _SectionLabel(label: 'Dispositivo'),
            const SizedBox(height: 8),
            _SettingsCard(
              child: Column(
                children: [
                  _FieldRow(
                    icon: Icons.badge_outlined,
                    label: 'Nombre',
                    child: SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Mi dispositivo',
                          hintStyle: TextStyle(color: _muted),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  _Divider(),
                  _FieldRow(
                    icon: Icons.lan_outlined,
                    label: 'Puerto UDP',
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _portController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '5555',
                          hintStyle: TextStyle(color: _muted),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sección: Audio
            _SectionLabel(label: 'Audio'),
            const SizedBox(height: 8),
            _SettingsCard(
              child: Column(
                children: [
                  _ToggleRow(
                    icon: Icons.noise_aware,
                    label: 'Reducción de ruido',
                    subtitle: 'Filtra ruido ambiental',
                    value: _noiseSuppress,
                    onChanged: (v) => setState(() => _noiseSuppress = v),
                  ),
                  _Divider(),
                  _ToggleRow(
                    icon: Icons.hearing,
                    label: 'Cancelación de eco',
                    subtitle: 'Evita el eco en bocina',
                    value: _echoCancel,
                    onChanged: (v) => setState(() => _echoCancel = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sección: Pantalla
            _SectionLabel(label: 'Pantalla'),
            const SizedBox(height: 8),
            _SettingsCard(
              child: _ToggleRow(
                icon: Icons.screen_lock_portrait_outlined,
                label: 'Mantener pantalla encendida',
                subtitle: 'Durante llamadas activas',
                value: _keepScreen,
                onChanged: (v) => setState(() => _keepScreen = v),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: _cyan, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _cyan, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _cyan,
            activeTrackColor: _cyan.withOpacity(0.3),
            inactiveTrackColor: _border,
            inactiveThumbColor: _muted,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: _border,
      margin: const EdgeInsets.only(left: 44),
    );
  }
}
