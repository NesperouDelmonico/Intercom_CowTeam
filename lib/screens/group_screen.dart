import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/room_provider.dart';
import 'package:intercom_app/screens/discovery_screen.dart';
import 'package:intercom_app/models/device.dart';
import 'package:flutter/services.dart';

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
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
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
    final notifier = ref.read(roomProvider.notifier);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: isActive
            ? Row(
                children: [
                  const Text('Sala grupal'),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _cyan.withOpacity(0.4)),
                    ),
                    child: Text(
                      room.roomCode ?? '',
                      style: const TextStyle(color: _cyan, fontSize: 11),
                    ),
                  ),
                ],
              )
            : const Text('Sala grupal'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _cyan),
          onPressed: () async {
            if (isActive) await notifier.leaveRoom();
            if (context.mounted) Navigator.pop(context);
          },
        ),
        actions: isActive
            ? [
                // Mute global
                IconButton(
                  icon: Icon(
                    room.globalMuted ? Icons.mic_off : Icons.mic_none,
                    color: room.globalMuted ? const Color(0xFFCC4444) : _cyan,
                  ),
                  onPressed: notifier.toggleGlobalMute,
                ),
                // Timer
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      _fmt(_elapsed),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 0.5, color: _border),
        ),
      ),
      body: isActive
          ? _ActiveRoom(room: room, notifier: notifier)
          : _IdleRoom(notifier: notifier),
    );
  }
}

// ── Sala inactiva ──────────────────────────────────────────
class _IdleRoom extends StatelessWidget {
  final RoomNotifier notifier;
  const _IdleRoom({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: const Row(
              children: [
                Icon(Icons.group_outlined, color: _muted, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sin sala activa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Crea o únete a una sala',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: notifier.createRoom,
            icon: const Icon(Icons.add),
            label: const Text('Crear sala'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final device = await Navigator.push<Device>(
                context,
                MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
              );
              if (device != null) {
                notifier.joinRoom(device.ip);
              }
            },
            icon: const Icon(Icons.search, color: _cyan),
            label: const Text('Buscar sala', style: TextStyle(color: _cyan)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _cyan),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sala activa ────────────────────────────────────────────
class _ActiveRoom extends StatelessWidget {
  final RoomState room;
  final RoomNotifier notifier;
  const _ActiveRoom({required this.room, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final members = room.members.values.toList();

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: members.length,
            itemBuilder: (context, i) =>
                _MemberCard(member: members[i], notifier: notifier),
          ),
        ),
        _AudioSettingsPanel(),
        // Controles globales
        _GlobalControls(room: room, notifier: notifier),
      ],
    );
  }
}

// ── Tarjeta de miembro (estilo Discord) ───────────────────
class _MemberCard extends StatefulWidget {
  final dynamic member;
  final RoomNotifier notifier;
  const _MemberCard({required this.member, required this.notifier});

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  bool _showVolume = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final initials = m.name.length >= 2
        ? m.name.substring(0, 2).toUpperCase()
        : m.name.toUpperCase();
    final isSpeaking = m.speakingLevel > 0.1;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSpeaking && !m.isMuted
              ? _cyan.withOpacity(0.4 + m.speakingLevel * 0.6)
              : _border,
          width: isSpeaking && !m.isMuted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Avatar con anillo de voz
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _bg,
                border: Border.all(
                  color: m.isMuted
                      ? _muted
                      : isSpeaking
                      ? _cyan
                      : _border,
                  width: isSpeaking && !m.isMuted ? 2.5 : 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: _cyan,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Nombre
            Text(
              m.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Barra de nivel de voz
            SizedBox(
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: m.isMuted ? 0 : m.speakingLevel,
                  backgroundColor: _border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    m.speakingLevel > 0.7 ? const Color(0xFFFF4444) : _cyan,
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Controles individuales
            if (_showVolume)
              Row(
                children: [
                  const Icon(Icons.volume_down, color: _muted, size: 14),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        activeTrackColor: _cyan,
                        inactiveTrackColor: _border,
                        thumbColor: _cyan,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: m.volume.clamp(0.0, 2.0),
                        min: 0,
                        max: 2,
                        onChanged: (v) =>
                            widget.notifier.setMemberVolume(m.ip, v),
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up, color: _muted, size: 14),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Silenciar individualmente
                  GestureDetector(
                    onTap: () =>
                        widget.notifier.setMemberMuted(m.ip, !m.isMuted),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.isMuted
                            ? const Color(0xFFCC2222).withOpacity(0.2)
                            : _bg,
                        border: Border.all(
                          color: m.isMuted ? const Color(0xFFCC2222) : _border,
                        ),
                      ),
                      child: Icon(
                        m.isMuted ? Icons.mic_off : Icons.mic_none,
                        color: m.isMuted ? const Color(0xFFCC4444) : _muted,
                        size: 16,
                      ),
                    ),
                  ),
                  // Toggle volumen
                  GestureDetector(
                    onTap: () => setState(() => _showVolume = !_showVolume),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _showVolume ? _cyan.withOpacity(0.2) : _bg,
                        border: Border.all(
                          color: _showVolume ? _cyan : _border,
                        ),
                      ),
                      child: Icon(
                        Icons.tune,
                        color: _showVolume ? _cyan : _muted,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── Controles globales ─────────────────────────────────────
class _GlobalControls extends StatefulWidget {
  final RoomState room;
  final RoomNotifier notifier;
  const _GlobalControls({required this.room, required this.notifier});

  @override
  State<_GlobalControls> createState() => _GlobalControlsState();
}

class _GlobalControlsState extends State<_GlobalControls> {
  bool _isBluetooth = false;
  bool _isSpeaker = true;

  static const _ch = MethodChannel('com.example.intercom_app/audio');

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    final hasBt = await _ch.invokeMethod<bool>('isBluetoothConnected') ?? false;
    setState(() {
      _isBluetooth = hasBt;
      _isSpeaker = !hasBt;
    });
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(
            icon: widget.room.globalMuted ? Icons.mic_off : Icons.mic_none,
            label: widget.room.globalMuted ? 'Silenciado' : 'Micrófono',
            active: widget.room.globalMuted,
            activeColor: const Color(0xFFCC4444),
            onTap: widget.notifier.toggleGlobalMute,
          ),
          GestureDetector(
            onTap: () async {
              await widget.notifier.leaveRoom();
              if (context.mounted) Navigator.pop(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFCC2222),
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Salir',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          _CtrlBtn(
            icon: Icons.bluetooth,
            label: 'Bluetooth',
            active: _isBluetooth,
            activeColor: _cyan,
            onTap: _isBluetooth ? _deactivateBluetooth : _activateBluetooth,
          ),
          _CtrlBtn(
            icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
            label: 'Altavoz',
            active: _isSpeaker,
            activeColor: _cyan,
            onTap: _isSpeaker ? _deactivateSpeaker : _activateSpeaker,
          ),
          _CtrlBtn(
            icon: Icons.tag,
            label: widget.room.roomCode ?? '',
            active: false,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Código: ${widget.room.roomCode}'),
                  backgroundColor: _card,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? _cyan) : _muted;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? (activeColor ?? _cyan).withOpacity(0.15) : _bg,
              border: Border.all(
                color: active
                    ? (activeColor ?? _cyan).withOpacity(0.5)
                    : _border,
              ),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

class _AudioSettingsPanel extends ConsumerStatefulWidget {
  const _AudioSettingsPanel();

  @override
  ConsumerState<_AudioSettingsPanel> createState() =>
      _AudioSettingsPanelState();
}

class _AudioSettingsPanelState extends ConsumerState<_AudioSettingsPanel> {
  bool _voxEnabled = false;
  double _voxThreshold = 500;
  double _micGain = 1.0;
  int _noiseLevel = 1; // 0=bajo, 1=medio, 2=alto
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, color: _cyan, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Audio de mi micrófono',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 0.5, color: _border),
                  const SizedBox(height: 12),

                  // VOX
                  Row(
                    children: [
                      const Icon(Icons.sensors, color: _cyan, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VOX',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Activar solo al hablar',
                              style: TextStyle(color: _muted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          final newVal = !_voxEnabled;
                          setState(() => _voxEnabled = newVal);
                          ref
                              .read(roomProvider.notifier)
                              .setVox(
                                enabled: newVal,
                                threshold: _voxThreshold,
                              );
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
                          'Sensibilidad VOX',
                          style: TextStyle(color: _muted, fontSize: 11),
                        ),
                        const Spacer(),
                        Text(
                          _voxThreshold.toInt().toString(),
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: _sliderTheme(context),
                      child: Slider(
                        value: _voxThreshold,
                        min: 100,
                        max: 2000,
                        onChanged: (v) {
                          setState(() => _voxThreshold = v);
                          ref
                              .read(roomProvider.notifier)
                              .setVox(enabled: _voxEnabled, threshold: v);
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Container(height: 0.5, color: _border),
                  const SizedBox(height: 12),

                  // Ganancia del micrófono
                  Row(
                    children: [
                      const Icon(Icons.mic, color: _cyan, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Ganancia del micrófono',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        '${(_micGain * 100).toInt()}%',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: _sliderTheme(context),
                    child: Slider(
                      value: _micGain,
                      min: 0.2,
                      max: 3.0,
                      onChanged: (v) {
                        setState(() => _micGain = v);
                        ref.read(roomProvider.notifier).setMicGain(v);
                      },
                    ),
                  ),

                  const SizedBox(height: 12),
                  Container(height: 0.5, color: _border),
                  const SizedBox(height: 12),

                  // Reducción de ruido
                  Row(
                    children: [
                      const Icon(Icons.noise_aware, color: _cyan, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Reducción de ruido',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _NoiseBtn(
                        label: 'Bajo',
                        active: _noiseLevel == 0,
                        onTap: () {
                          setState(() => _noiseLevel = 0);
                          ref.read(roomProvider.notifier).setNoiseLevel(0);
                        },
                      ),
                      _NoiseBtn(
                        label: 'Medio',
                        active: _noiseLevel == 1,
                        onTap: () {
                          setState(() => _noiseLevel = 1);
                          ref.read(roomProvider.notifier).setNoiseLevel(1);
                        },
                      ),
                      _NoiseBtn(
                        label: 'Alto',
                        active: _noiseLevel == 2,
                        onTap: () {
                          setState(() => _noiseLevel = 2);
                          ref.read(roomProvider.notifier).setNoiseLevel(2);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderTheme.of(context).copyWith(
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      activeTrackColor: _cyan,
      inactiveTrackColor: _border,
      thumbColor: _cyan,
      overlayShape: SliderComponentShape.noOverlay,
    );
  }
}

class _NoiseBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NoiseBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? _cyan.withOpacity(0.15) : _bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? _cyan : _border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? _cyan : _muted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
