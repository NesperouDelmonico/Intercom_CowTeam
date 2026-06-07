import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/call_state.dart';
import 'package:intercom_app/providers/call_provider.dart';
import 'package:intercom_app/services/audio_service.dart';
import 'package:intercom_app/services/settings_service.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'dart:io';

const _cyan = Color(0xFF00E5FF);
const _bg = Color(0xFF0A1628);
const _card = Color(0xFF0D1F38);
const _border = Color(0xFF1A3A5C);
const _muted = Color(0xFF445566);
const _ch = MethodChannel('com.example.intercom_app/audio');

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _isMuted = false;
  bool _isPushToTalk = false;
  bool _isSpeaker = false;
  bool _isBluetooth = false;
  double _speakingLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _applyScreenSettings();
    _initAudioOutput();
    _listenToAudioLevel();
  }

  void _listenToAudioLevel() {
    const ch = MethodChannel('com.example.intercom_app/audio');
    // Escuchar nivel de audio cada 100ms
    Stream.periodic(const Duration(milliseconds: 100)).listen((_) async {
      if (!mounted) return;
      try {
        final level = await ch.invokeMethod<double>('getAudioLevel') ?? 0.0;
        if (mounted) setState(() => _speakingLevel = level.clamp(0.0, 1.0));
      } catch (_) {
        if (mounted) setState(() => _speakingLevel = 0.0);
      }
    });
  }

  Future<void> _initAudioOutput() async {
    final bool hasBt = await _ch.invokeMethod('isBluetoothConnected') ?? false;
    setState(() {
      _isBluetooth = hasBt;
      _isSpeaker = !hasBt;
    });
  }

  Future<void> _applyScreenSettings() async {
    final keep = await SettingsService.getKeepScreen();
    if (keep) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours.toString().padLeft(2, '0')}:' : ''}$m:$s';
  }

  Future<void> _toggleMute() async {
    final newMuted = !_isMuted;
    ref.read(callProvider.notifier).setMuted(newMuted);
    setState(() => _isMuted = newMuted);
  }

  Future<void> _activateBluetooth() async {
    await _ch.invokeMethod('enableBluetooth');
    setState(() {
      _isBluetooth = true;
      _isSpeaker = false;
    });
  }

  Future<void> _deactivateBluetooth() async {
    await _ch.invokeMethod('disableBluetooth');
    setState(() {
      _isBluetooth = false;
      _isSpeaker = true;
    });
  }

  Future<void> _activateSpeaker() async {
    await _ch.invokeMethod('enableSpeaker');
    setState(() {
      _isSpeaker = true;
      _isBluetooth = false;
    });
  }

  Future<void> _deactivateSpeaker() async {
    await _ch.invokeMethod('disableSpeaker');
    setState(() => _isSpeaker = false);
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);

    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.idle) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });

    final initials =
        call.remoteDevice?.name != null && call.remoteDevice!.name.length >= 2
        ? call.remoteDevice!.name.substring(0, 2).toUpperCase()
        : 'AN';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('En llamada'),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 88 + (_speakingLevel * 16),
              height: 88 + (_speakingLevel * 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _card,
                border: Border.all(
                  color: _speakingLevel > 0.1
                      ? _cyan.withOpacity(0.4 + _speakingLevel * 0.6)
                      : _cyan,
                  width: 2 + (_speakingLevel * 4),
                ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: _cyan,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ref
              .watch(settingsProvider)
              .when(
                data: (s) => s.avatarPath != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: FileImage(File(s.avatarPath!)),
                        ),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            // Avatar
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _card,
                border: Border.all(color: _cyan, width: 2),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: _cyan,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              call.remoteDevice?.name ?? 'Dispositivo',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            StreamBuilder<Duration>(
              stream: Stream.periodic(
                const Duration(seconds: 1),
                (i) => Duration(seconds: i + 1),
              ),
              builder: (context, snap) {
                return Text(
                  _formatTime(snap.data ?? Duration.zero),
                  style: const TextStyle(color: _muted, fontSize: 14),
                );
              },
            ),
            const Spacer(),
            // Switch PTT
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Manos libres',
                  style: TextStyle(
                    color: _isPushToTalk ? _muted : _cyan,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _isPushToTalk = !_isPushToTalk),
                  child: Container(
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _isPushToTalk ? _cyan : _border,
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _isPushToTalk
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Push-to-talk',
                  style: TextStyle(
                    color: _isPushToTalk ? _cyan : _muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // Botón PTT / micrófono
            GestureDetector(
              onTapDown: _isPushToTalk ? (_) {} : null,
              onTapUp: _isPushToTalk ? (_) {} : null,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMuted
                      ? _border
                      : (_isPushToTalk ? _cyan : _cyan.withOpacity(0.15)),
                  border: Border.all(
                    color: _isMuted ? _muted : _cyan,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  color: _isMuted ? _muted : (_isPushToTalk ? _bg : _cyan),
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isMuted
                  ? 'Micrófono silenciado'
                  : (_isPushToTalk ? 'Mantén para hablar' : 'Micrófono activo'),
              style: TextStyle(color: _isMuted ? _muted : _muted, fontSize: 11),
            ),
            const Spacer(),
            // Botones de acción
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionBtn(
                  icon: _isMuted ? Icons.mic_off : Icons.mic_none,
                  label: _isMuted ? 'Silenciado' : 'Silenciar',
                  active: _isMuted,
                  onTap: _toggleMute,
                ),
                _HangupBtn(
                  onTap: () => ref.read(callProvider.notifier).endCall(),
                ),
                _ActionBtn(
                  icon: Icons.bluetooth,
                  label: 'Bluetooth',
                  active: _isBluetooth,
                  activeColor: _cyan,
                  onTap: _isBluetooth
                      ? _deactivateBluetooth
                      : _activateBluetooth,
                ),
                _ActionBtn(
                  icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                  label: 'Altavoz',
                  active: _isSpeaker,
                  activeColor: _cyan,
                  onTap: _isSpeaker ? _deactivateSpeaker : _activateSpeaker,
                ),
              ],
            ),

            _VoxPanel(
              audioService: ref.read(callProvider.notifier).audioService,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? Colors.white) : _muted;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? (activeColor ?? Colors.white).withOpacity(0.15)
                  : _card,
              border: Border.all(
                color: active
                    ? (activeColor ?? Colors.white).withOpacity(0.4)
                    : _border,
              ),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

class _HangupBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _HangupBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFCC2222),
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          const Text('Colgar', style: TextStyle(color: _muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _VoxPanel extends StatefulWidget {
  final AudioService audioService;
  const _VoxPanel({required this.audioService});

  @override
  State<_VoxPanel> createState() => _VoxPanelState();
}

class _VoxPanelState extends State<_VoxPanel> {
  bool _voxEnabled = false;
  double _voxThreshold = 500;
  double _volume = 1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: _cyan, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'VOX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final newVal = !_voxEnabled;
                  await widget.audioService.setVox(
                    enabled: newVal,
                    threshold: _voxThreshold,
                  );
                  setState(() => _voxEnabled = newVal);
                },
                child: Container(
                  width: 44,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _voxEnabled ? _cyan : _border,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _voxEnabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_voxEnabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Sensibilidad',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                Expanded(
                  child: Slider(
                    value: _voxThreshold,
                    min: 100,
                    max: 2000,
                    activeColor: _cyan,
                    inactiveColor: _border,
                    onChanged: (v) async {
                      await widget.audioService.setVox(
                        enabled: _voxEnabled,
                        threshold: v,
                      );
                      setState(() => _voxThreshold = v);
                    },
                  ),
                ),
                Text(
                  _voxThreshold.toInt().toString(),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.volume_up, color: _cyan, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Volumen',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 2.0,
                  activeColor: _cyan,
                  inactiveColor: _border,
                  onChanged: (v) async {
                    await widget.audioService.setVolume(v);
                    setState(() => _volume = v);
                  },
                ),
              ),
              Text(
                '${(_volume * 100).toInt()}%',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
