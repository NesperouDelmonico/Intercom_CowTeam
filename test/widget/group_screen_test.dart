import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/room_provider.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/screens/group_screen.dart';
import 'package:intercom_app/services/room_service.dart';
import 'package:intercom_app/models/room_info.dart';

class FakeSettingsNotifier extends AsyncNotifier<AppSettings>
    implements SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings(
    deviceName: 'TestDevice',
    port: 5555,
    noiseSuppress: false,
    echoCancel: false,
    keepScreen: false,
    avatarPath: null,
  );

  @override
  Future<void> save(AppSettings s) async {}

  @override
  Future<void> reload() async {}
}

class FakeRoomNotifier extends Notifier<RoomState> implements RoomNotifier {
  final RoomState _initialState;
  FakeRoomNotifier({RoomState? state})
    : _initialState = state ?? const RoomState();

  @override
  RoomState build() => _initialState;

  @override
  void setHostClosedCallback(void Function() cb) {}
  @override
  Future<void> createRoom() async {}
  @override
  Future<void> joinRoom(String hostIp) async {}
  @override
  Future<void> joinRoomByCode(String code) async {}
  @override
  Future<void> leaveRoom() async {}
  @override
  void toggleGlobalMute() {}
  @override
  void setMemberMuted(String ip, bool muted) {}
  @override
  void setMemberVolume(String ip, double volume) {}
  @override
  void setMicGain(double gain) {}
  @override
  void setVox({required bool enabled, required double threshold}) {}
  @override
  Future<void> setNoiseLevel(int level) async {}
  @override
  void setLowPowerMode(bool v) {}
  @override
  void setMemberEventCallback(void Function(String, bool) cb) {}
  @override
  Future<bool> hasNetworkConnection() async => true;
  @override
  Future<List<RoomInfo>> discoverRooms() async => [];
  @override
  Future<bool> searchAndJoinViaWifiDirect(String code) async => false;
}

Widget buildTestApp(Widget child, {RoomState? roomState}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(FakeSettingsNotifier.new),
      roomProvider.overrideWith(() => FakeRoomNotifier(state: roomState)),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00E5FF)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF001830),
            shape: const StadiumBorder(),
          ),
        ),
      ),
      home: child,
    ),
  );
}

void main() {
  group('GroupScreen — sala inactiva', () {
    testWidgets('muestra título Sala grupal', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Sala grupal'), findsOneWidget);
    });

    testWidgets('muestra botón Crear sala', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Crear sala'), findsOneWidget);
    });

    testWidgets('muestra sección Unirse por código', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Unirse por código'), findsOneWidget);
    });

    testWidgets('muestra botón Buscar salas activas', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Buscar salas activas'), findsOneWidget);
    });

    testWidgets('muestra campo de texto para código', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('campo de código acepta texto numérico', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      expect(find.text('1234'), findsOneWidget);
    });

    testWidgets('no muestra controles de sala activa', (tester) async {
      await tester.pumpWidget(buildTestApp(const GroupScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.call_end), findsNothing);
    });
  });

  group('GroupScreen — sala activa', () {
    final activeState = RoomState(
      status: RoomStatus.hosting,
      roomCode: '9876',
      isHost: true,
      globalMuted: false,
      members: {
        '192.168.49.1': RoomMember(
          name: 'Nesp',
          ip: '192.168.49.1',
          avatarBase64: null,
        ),
        '192.168.49.2': RoomMember(
          name: 'Marietta',
          ip: '192.168.49.2',
          avatarBase64: null,
        ),
      },
    );

    testWidgets('muestra código de sala en AppBar', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      // El código aparece en AppBar y en controles — verificar que existe al menos uno
      expect(find.text('9876'), findsWidgets);
    });

    testWidgets('muestra botón salir', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('muestra tarjetas de miembros', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      expect(find.text('NE'), findsOneWidget); // iniciales Nesp
      expect(find.text('MA'), findsOneWidget); // iniciales Marietta
    });

    testWidgets('muestra panel de audio colapsado', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      expect(find.text('Audio de mi micrófono'), findsOneWidget);
    });

    testWidgets('muestra ícono de micrófono en AppBar', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      // mic_none aparece en AppBar y en controles globales
      expect(find.byIcon(Icons.mic_none), findsWidgets);
    });

    testWidgets('no muestra botón Crear sala cuando está activa', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: activeState),
      );
      await tester.pumpAndSettle();
      expect(find.text('Crear sala'), findsNothing);
    });
  });

  group('GroupScreen — tarjeta de miembro', () {
    testWidgets('muestra iniciales cuando no hay avatar', (tester) async {
      final state = RoomState(
        status: RoomStatus.hosting,
        roomCode: '1111',
        isHost: true,
        members: {
          '192.168.49.1': RoomMember(name: 'Carlos', ip: '192.168.49.1'),
        },
      );
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: state),
      );
      await tester.pumpAndSettle();
      expect(find.text('CA'), findsOneWidget);
    });

    testWidgets('nombre truncado a 10 caracteres', (tester) async {
      final state = RoomState(
        status: RoomStatus.hosting,
        roomCode: '2222',
        isHost: true,
        members: {
          '192.168.49.1': RoomMember(
            name: 'NombreMuyLargo',
            ip: '192.168.49.1',
          ),
        },
      );
      await tester.pumpWidget(
        buildTestApp(const GroupScreen(), roomState: state),
      );
      await tester.pumpAndSettle();
      expect(find.text('NombreMuyL'), findsOneWidget);
    });
  });
}
