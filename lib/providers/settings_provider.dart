import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intercom_app/services/settings_service.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  final String deviceName;
  final String? avatarPath;
  final int port;
  final bool noiseSuppress;
  final bool echoCancel;
  final bool keepScreen;
  final bool voxEnabled;
  final double voxThreshold;
  final int noiseLevel;
  final double micGain;
  const AppSettings({
    required this.deviceName,
    required this.port,
    this.micGain = 1.0,
    this.avatarPath,
    this.noiseSuppress = true,
    this.echoCancel = true,
    this.keepScreen = true,
    this.voxEnabled = false,
    this.voxThreshold = 500.0,
    this.noiseLevel = 1,
  });
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return _load();
  }

  Future<AppSettings> _load() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final fallback = info.model;
    final name = await SettingsService.getDeviceName(fallback);
    final port = await SettingsService.getPort();
    final noise = await SettingsService.getNoiseSuppress();
    final echo = await SettingsService.getEchoCancel();
    final screen = await SettingsService.getKeepScreen();
    final dir = await getApplicationDocumentsDirectory();
    final avatarFile = File('${dir.path}/avatar.jpg');
    final avatar = avatarFile.existsSync() ? avatarFile.path : null;
    final voxEnabled = await SettingsService.getVoxEnabled();
    final voxThreshold = await SettingsService.getVoxThreshold();
    final noiseLevel = await SettingsService.getNoiseLevel();
    final micGain = await SettingsService.getMicGain();

    return AppSettings(
      deviceName: name,
      port: port,
      avatarPath: avatar,
      noiseSuppress: noise,
      echoCancel: echo,
      keepScreen: screen,
      voxEnabled: voxEnabled,
      voxThreshold: voxThreshold,
      noiseLevel: noiseLevel,
      micGain: micGain,
    );
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _load());
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
