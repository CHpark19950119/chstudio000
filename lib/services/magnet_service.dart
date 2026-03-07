import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MagnetService {
  static final MagnetService _i = MagnetService._();
  factory MagnetService() => _i;
  MagnetService._();

  StreamSubscription? _sub;
  final _controller = StreamController<bool>.broadcast();

  bool _onCradle = false;
  bool get isOnCradle => _onCradle;
  Stream<bool> get cradleStream => _controller.stream;
  bool _enabled = false;
  bool get isEnabled => _enabled;

  // 자기장 임계값 (uT)
  // 일반 환경: ~30-60 uT (지구 자기장)
  // 자석 근접: 100-500+ uT
  double _threshold = 120.0;
  double get threshold => _threshold;

  // 디바운스: 짧은 변동 무시
  DateTime? _lastChange;
  static const _debounce = Duration(milliseconds: 800);

  // 최근 magnitude (디버그/UI용)
  double _lastMagnitude = 0;
  double get lastMagnitude => _lastMagnitude;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool('magnet_enabled') ?? false;
    _threshold = p.getDouble('magnet_threshold') ?? 120.0;
    if (_enabled) start();
  }

  void start() {
    _sub?.cancel();
    try {
      _sub = magnetometerEventStream(
        samplingPeriod: const Duration(milliseconds: 200),
      ).listen(
        (event) {
          final magnitude = sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          _lastMagnitude = magnitude;

          final now = DateTime.now();
          final isStrong = magnitude > _threshold;

          if (isStrong != _onCradle) {
            if (_lastChange != null &&
                now.difference(_lastChange!) < _debounce) {
              return;
            }
            _lastChange = now;
            _onCradle = isStrong;
            _controller.add(_onCradle);
            debugPrint(
              '[Magnet] ${_onCradle ? "ON CRADLE" : "OFF CRADLE"} '
              '(${magnitude.toStringAsFixed(1)} uT)',
            );
          }
        },
        onError: (e) {
          debugPrint('[Magnet] sensor error: $e');
        },
      );
      debugPrint('[Magnet] started (threshold: ${_threshold.toStringAsFixed(1)} uT)');
    } catch (e) {
      debugPrint('[Magnet] start failed: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _onCradle = false;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('magnet_enabled', v);
    if (v) {
      start();
    } else {
      stop();
    }
  }

  /// 캘리브레이션: 3초간 측정 → 평균의 70%를 임계값으로
  Future<double> calibrate() async {
    final values = <double>[];
    final sub = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      values.add(magnitude);
    });

    await Future.delayed(const Duration(seconds: 3));
    await sub.cancel();

    if (values.isEmpty) return _threshold;

    final avg = values.reduce((a, b) => a + b) / values.length;
    _threshold = (avg * 0.7).clamp(50.0, 1000.0);

    final p = await SharedPreferences.getInstance();
    await p.setDouble('magnet_threshold', _threshold);

    debugPrint(
      '[Magnet] calibrated: avg=${avg.toStringAsFixed(1)}, '
      'threshold=${_threshold.toStringAsFixed(1)}',
    );
    return _threshold;
  }

  Future<void> setThreshold(double value) async {
    _threshold = value;
    final p = await SharedPreferences.getInstance();
    await p.setDouble('magnet_threshold', _threshold);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
