import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// CHEONHONG STUDIO — Cradle Detection (Angle-based)
/// 가속도계 중력 벡터 각도로 거치대 안착/분리 감지
/// - 캘리브레이션: 5초 측정 → 평균 중력 벡터 → Hive 저장
/// - ON 감지: 10초 연속 캘리 각도 ±12° 이내
/// - OFF 감지: 3초 연속 캘리 각도 ±25° 초과
/// - 히스테리시스: 12° ~ 25° 데드존
class CradleService {
  static final CradleService _i = CradleService._();
  factory CradleService() => _i;
  CradleService._();

  StreamSubscription? _sub;
  final _controller = StreamController<bool>.broadcast();

  bool _onCradle = false;
  bool get isOnCradle => _onCradle;
  Stream<bool> get cradleStream => _controller.stream;
  bool _enabled = false;
  bool get isEnabled => _enabled;
  bool _calibrated = false;
  bool get isCalibrated => _calibrated;

  // Calibration reference gravity vector
  double _refX = 0, _refY = 0, _refZ = 9.8;

  // Angle thresholds (degrees)
  static const double _attachAngle = 12.0;
  static const double _detachAngle = 25.0;

  // Detection counters
  int _stableCount = 0;
  int _unstableCount = 0;
  static const int _stableRequired = 50;   // 10sec (200ms * 50)
  static const int _unstableRequired = 15; // 3sec  (200ms * 15)

  // Debug
  double _lastAngle = 0;
  double get lastAngle => _lastAngle;

  Future<void> init() async {
    try {
      final box = await Hive.openBox('cradle');
      _enabled = box.get('enabled', defaultValue: false) as bool;
      _calibrated = box.get('calibrated', defaultValue: false) as bool;
      _refX = (box.get('refX', defaultValue: 0.0) as num).toDouble();
      _refY = (box.get('refY', defaultValue: 0.0) as num).toDouble();
      _refZ = (box.get('refZ', defaultValue: 9.8) as num).toDouble();
      debugPrint('[Cradle] init: enabled=$_enabled, calibrated=$_calibrated, ref=($_refX, $_refY, $_refZ)');
      if (_enabled && _calibrated) start();
    } catch (e) {
      debugPrint('[Cradle] init failed: $e');
    }
  }

  void start() {
    _sub?.cancel();
    _stableCount = 0;
    _unstableCount = 0;
    try {
      _sub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 200),
      ).listen(
        _onAccelEvent,
        onError: (e) => debugPrint('[Cradle] sensor error: $e'),
      );
      debugPrint('[Cradle] started (ref: $_refX, $_refY, $_refZ)');
    } catch (e) {
      debugPrint('[Cradle] start failed: $e');
    }
  }

  void _onAccelEvent(AccelerometerEvent event) {
    final angle = _angleDeg(event.x, event.y, event.z, _refX, _refY, _refZ);
    _lastAngle = angle;

    if (_onCradle) {
      // Currently ON -> detect OFF
      if (angle > _detachAngle) {
        _unstableCount++;
        _stableCount = 0;
        if (_unstableCount >= _unstableRequired) {
          _onCradle = false;
          _unstableCount = 0;
          _controller.add(false);
          debugPrint('[Cradle] OFF — angle=${angle.toStringAsFixed(1)}deg');
        }
      } else {
        _unstableCount = 0;
      }
    } else {
      // Currently OFF -> detect ON
      if (angle < _attachAngle) {
        _stableCount++;
        _unstableCount = 0;
        if (_stableCount >= _stableRequired) {
          _onCradle = true;
          _stableCount = 0;
          _controller.add(true);
          debugPrint('[Cradle] ON — angle=${angle.toStringAsFixed(1)}deg');
        }
      } else if (angle > _detachAngle) {
        _stableCount = 0;
      }
      // dead zone (12~25 deg): counter holds
    }
  }

  /// Angle between two vectors in degrees
  double _angleDeg(double x1, double y1, double z1,
                   double x2, double y2, double z2) {
    final dot = x1 * x2 + y1 * y2 + z1 * z2;
    final m1 = sqrt(x1 * x1 + y1 * y1 + z1 * z1);
    final m2 = sqrt(x2 * x2 + y2 * y2 + z2 * z2);
    if (m1 < 0.01 || m2 < 0.01) return 180.0;
    return acos((dot / (m1 * m2)).clamp(-1.0, 1.0)) * 180.0 / pi;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _onCradle = false;
    _stableCount = 0;
    _unstableCount = 0;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      final box = await Hive.openBox('cradle');
      await box.put('enabled', v);
    } catch (_) {}
    if (v && _calibrated) {
      start();
    } else if (!v) {
      stop();
    }
  }

  /// Calibrate: 5sec measurement -> average gravity vector -> Hive save
  Future<void> calibrate() async {
    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];

    final sub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((event) {
      xs.add(event.x);
      ys.add(event.y);
      zs.add(event.z);
    });

    await Future.delayed(const Duration(seconds: 5));
    await sub.cancel();

    if (xs.isEmpty) {
      debugPrint('[Cradle] calibration failed: no data');
      return;
    }

    _refX = xs.reduce((a, b) => a + b) / xs.length;
    _refY = ys.reduce((a, b) => a + b) / ys.length;
    _refZ = zs.reduce((a, b) => a + b) / zs.length;
    _calibrated = true;

    try {
      final box = await Hive.openBox('cradle');
      await box.put('refX', _refX);
      await box.put('refY', _refY);
      await box.put('refZ', _refZ);
      await box.put('calibrated', true);
    } catch (_) {}

    debugPrint('[Cradle] calibrated: ref=($_refX, $_refY, $_refZ), samples=${xs.length}');
    if (_enabled) start();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
