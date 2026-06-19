import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Solicita los permisos necesarios para WiFi Direct,
  /// adaptado según la versión de Android.
  static Future<bool> requestWifiDirectPermissions() async {
    final sdkInt = await _getSdkInt();

    // Ubicación siempre es necesaria
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) return false;

    // nearbyWifiDevices solo existe desde Android 13 (API 33)
    if (sdkInt >= 33) {
      final nearbyStatus = await Permission.nearbyWifiDevices.request();
      return nearbyStatus.isGranted;
    }

    return true;
  }

  static Future<int> _getSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }
}
