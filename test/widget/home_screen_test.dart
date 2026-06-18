import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercom_app/models/room_state.dart';
import 'package:intercom_app/providers/room_provider.dart';
import 'package:intercom_app/providers/settings_provider.dart';
import 'package:intercom_app/screens/home_screen.dart';
import 'package:intercom_app/models/room_info.dart';

// Settings falsos para los tests
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

// RoomNotifier falso
class FakeRoomNotifier extends Notifier<RoomState> implements RoomNotifier {
  @override
  RoomState build() => const RoomState();

  @override
  Future<void> createRoom() async {}

  @override
  void setHostClosedCallback(void Function() cb) {}

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

Widget buildTestApp(Widget child) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(FakeSettingsNotifier.new),
      roomProvider.overrideWith(FakeRoomNotifier.new),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00E5FF)),
      ),
      home: child,
    ),
  );
}

void main() {
  group('HomeScreen — estructura básica', () {
    testWidgets('muestra título Intercom by CowTeam', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Intercom by CowTeam'), findsOneWidget);
    });

    testWidgets('muestra botón de ajustes', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('muestra botón de info', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('muestra tarjeta de perfil', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Tu dispositivo'), findsOneWidget);
    });

    testWidgets('muestra botón de sala de comunicación', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Sala de comunicación'), findsOneWidget);
    });

    testWidgets('muestra botón conectar dispositivo', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Conectar dispositivo'), findsOneWidget);
    });
  });

  group('HomeScreen — perfil', () {
    testWidgets('muestra nombre del dispositivo en tarjeta', (tester) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('TestDevice'), findsOneWidget);
    });

    testWidgets('muestra ícono de persona cuando no hay avatar', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}
