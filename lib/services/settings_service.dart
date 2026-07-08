import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _keyName = 'device_name';
  static const _keyPort = 'port';
  static const _keyNoiseSuppress = 'noise_suppress';
  static const _keyEchoCancel = 'echo_cancel';
  static const _keyKeepScreen = 'keep_screen';

  static Future<String> getDeviceName(String fallback) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyName) ?? fallback;
  }

  static Future<void> setDeviceName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyName, name);
  }

  static Future<int> getPort() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyPort) ?? 5555;
  }

  static Future<void> setPort(int port) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyPort, port);
  }

  static Future<bool> getNoiseSuppress() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyNoiseSuppress) ?? true;
  }

  static Future<void> setNoiseSuppress(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyNoiseSuppress, value);
  }

  static Future<bool> getEchoCancel() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyEchoCancel) ?? true;
  }

  static Future<void> setEchoCancel(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyEchoCancel, value);
  }

  static Future<bool> getKeepScreen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyKeepScreen) ?? true;
  }

  static Future<void> setKeepScreen(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyKeepScreen, value);
  }

  static const _keyVoxEnabled = 'vox_enabled';
  static const _keyVoxThreshold = 'vox_threshold';
  static const _keyNoiseLevel = 'noise_level';

  static Future<bool> getVoxEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyVoxEnabled) ?? false;
  }

  static Future<void> setVoxEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyVoxEnabled, value);
  }

  static Future<double> getVoxThreshold() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_keyVoxThreshold) ?? 500).toDouble();
  }

  static Future<void> setVoxThreshold(double value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyVoxThreshold, value.toInt());
  }

  static Future<int> getNoiseLevel() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyNoiseLevel) ?? 1; // 1 = Medio por defecto
  }

  static Future<void> setNoiseLevel(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyNoiseLevel, value);
  }

  static const _keyMicGain = 'mic_gain';

  static Future<double> getMicGain() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_keyMicGain) ?? 100) / 100.0;
  }

  static Future<void> setMicGain(double value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyMicGain, (value * 100).toInt());
  }
}
