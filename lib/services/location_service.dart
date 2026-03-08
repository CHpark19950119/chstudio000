import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// GPS 유틸리티 — one-shot 위치 조회 전용
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }
    if (perm == LocationPermission.deniedForever) return false;
    return true;
  }

  /// GPS one-shot: 현재 위치 (10초 타임아웃)
  Future<Position?> getCurrentPosition() async {
    try {
      final ok = await requestPermissions();
      if (!ok) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[Location] GPS error: $e');
      return null;
    }
  }

  /// 좌표 → "37.5665,126.9780" 문자열
  static String formatPosition(Position pos) {
    return '${pos.latitude.toStringAsFixed(4)},${pos.longitude.toStringAsFixed(4)}';
  }
}
