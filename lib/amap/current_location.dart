import 'package:geolocator/geolocator.dart';

Future<bool> _ensureLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    return false;
  }
  return true;
}

/// 缓存位置，毫秒级返回，用于地图首屏中心，避免阻塞在冷启动 GPS。
Future<({double latitude, double longitude})?> tryGetLastKnownLocation() async {
  try {
    if (!await _ensureLocationPermission()) return null;
    final p = await Geolocator.getLastKnownPosition();
    if (p == null) return null;
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null;
  }
}

/// 获取当前 GPS 坐标（可能较慢）；失败或未授权时返回 null。
Future<({double latitude, double longitude})?> tryGetCurrentLocation() async {
  try {
    if (!await _ensureLocationPermission()) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null;
  }
}

/// 先尝试缓存位置，没有再短时定位，用于「定位」按钮与选点初始中心。
Future<({double latitude, double longitude})?> tryGetBestLocation() async {
  final last = await tryGetLastKnownLocation();
  if (last != null) return last;
  try {
    if (!await _ensureLocationPermission()) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 6),
      ),
    );
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null;
  }
}
