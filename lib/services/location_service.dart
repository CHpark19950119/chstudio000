import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../utils/study_date_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'local_cache_service.dart';

// ═══════════════════════════════════════════
//  포그라운드 서비스 TaskHandler (앱 강제 종료 후에도 독립 실행)
// ═══════════════════════════════════════════

@pragma('vm:entry-point')
void locationServiceCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  static const _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[LocationHandler] onStart (headless or app-alive)');
    // 헤드리스 모드에서 Firebase 초기화
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // 이미 초기화된 경우 무시
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final isTracking = prefs.getBool('location_tracking') ?? false;
    if (!isTracking) return;

    // 마지막 기록 시간 확인 → 간격 미달이면 스킵
    final lastMs = prefs.getInt('location_last_record_ms') ?? 0;
    final elapsed = timestamp.millisecondsSinceEpoch - lastMs;
    final isTravelMode = prefs.getBool('location_travel_mode') ?? false;
    final motionName = prefs.getString('motion_state') ?? 'unknown';
    final isMoving = motionName == 'moving';

    int requiredMs;
    if (isTravelMode) {
      requiredMs = 30 * 1000;       // 30초
    } else if (isMoving) {
      requiredMs = 5 * 60 * 1000;   // 5분
    } else {
      requiredMs = 15 * 60 * 1000;  // 15분
    }

    if (elapsed < requiredMs - 5000) return; // 5초 여유

    // 메인 앱이 살아있으면 LocationService가 처리 → 여기선 최근 기록 여부만 체크
    // 메인 Timer가 살아있으면 lastMs가 갱신되므로 여기까지 도달 안 함
    // 여기 도달 = 메인 앱 사망 → 직접 기록
    debugPrint('[LocationHandler] 🛰️ 헤드리스 GPS 기록 (${elapsed ~/ 1000}s 경과)');

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final timeStr = DateFormat('HH:mm').format(now);

      // Firebase에 직접 기록
      try {
        final record = <String, dynamic>{
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'timestamp': timeStr,
          'placeName': prefs.getString('location_current_place') ?? '알 수 없음',
          'placeId': prefs.getString('location_current_place_id'),
          'source': 'headless',
        };

        await FirebaseFirestore.instance
            .collection('users').doc(_uid)
            .collection('location_records').doc(dateStr)
            .collection('entries').add(record)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // Firebase 실패 → 로컬 캐싱
        debugPrint('[LocationHandler] Firebase 실패, 로컬 캐싱: $e');
        final pending = prefs.getStringList('pending_locations') ?? [];
        pending.add(jsonEncode({
          'date': dateStr,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'timestamp': timeStr,
          'placeName': prefs.getString('location_current_place') ?? '알 수 없음',
          'source': 'headless_cached',
        }));
        await prefs.setStringList('pending_locations', pending);
      }

      // 마지막 기록 시간 갱신
      await prefs.setInt('location_last_record_ms', now.millisecondsSinceEpoch);

      // 알림 업데이트
      final placeName = prefs.getString('location_current_place') ?? '추적 중';
      FlutterForegroundTask.updateService(
        notificationTitle: '📍 $placeName',
        notificationText: '${isTravelMode ? "15분" : isMoving ? "5분" : "15분"} 간격 · $timeStr 기록',
      );
    } catch (e) {
      debugPrint('[LocationHandler] GPS 오류: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[LocationHandler] onDestroy');
  }
}

/// GPS 위치 추적 + 장소 자동 태깅 서비스
/// v8.5: 15분 상시 백그라운드 + 이동 시 5분 + NFC 트리거 15분
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const _wifiChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/wifi');

  static const _placesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';
  static const _placesBaseUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  // ─── 간격 설정 ───
  static const _idleInterval = Duration(minutes: 15);     // 기본 15분
  static const _movingInterval = Duration(minutes: 5);     // 이동 감지 시 5분
  static const _travelInterval = Duration(minutes: 15);    // NFC 외출 트리거 시 15분
  static const _moveThresholdMeters = 50.0;
  static const _stationaryThreshold = 2;

  // ─── 상태 ───
  bool _isTracking = false;
  Timer? _trackTimer;
  Position? _lastPosition;
  Position? _prevPosition;
  String? _currentPlaceName;
  String? _currentPlaceId;
  DateTime? _stayStart;
  List<KnownPlace> _knownPlaces = [];

  MotionState _motionState = MotionState.unknown;
  int _stationaryCount = 0;
  LocationState _locationState = LocationState.idle;

  DateTime? _unknownStayStart;
  static const _unknownStayMinutes = 20;

  /// 이동 구간 집계: 반복 기록 방지
  DateTime? _movementStart;
  bool _wasMoving = false;

  /// NFC 외출 트리거에 의한 여행 모드
  bool _isTravelMode = false;

  /// 3-③ 15분 체류 감지: 같은 위치에 15분 이상 → 자동 이동 종료
  DateTime? _stationaryStart;
  static const _dwellAutoStopMinutes = 15;

  // ─── Getters ───
  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  String? get currentPlaceName => _currentPlaceName;
  MotionState get motionState => _motionState;
  LocationState get locationState => _locationState;

  // ─── 초기화 ───
  Future<void> initialize() async {
    _initForegroundTask();
    await _loadKnownPlaces();
    await _restoreState();
    // GPS는 NFC 외출/귀가로만 제어 (WiFi 모니터 제거)
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cheonhong_location_tracking',
        channelName: '위치 추적',
        channelDescription: 'CHEONHONG STUDIO GPS 추적 서비스',
        channelImportance: NotificationChannelImportance.HIGH,    // ★ #8: HIGH로 변경
        priority: NotificationPriority.HIGH,                       // ★ #8: HIGH로 변경
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// ★ #8: 배터리 최적화 면제 요청 + 삼성 배터리 설정 안내
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      // 1) Android 표준 배터리 최적화 면제 요청
      await _wifiChannel.invokeMethod('requestBatteryOptimization');
      debugPrint('[Location] ✅ 배터리 최적화 면제 요청');
    } catch (e) {
      debugPrint('[Location] ⚠️ 배터리 최적화 면제 요청 실패: $e');
    }
    try {
      // 2) 삼성 배터리 설정 Intent (Samsung Device Care)
      await _wifiChannel.invokeMethod('openSamsungBatterySettings');
      debugPrint('[Location] ✅ 삼성 배터리 설정 열기');
    } catch (e) {
      debugPrint('[Location] ⚠️ 삼성 배터리 설정 열기 실패 (비삼성 기기?): $e');
    }
  }

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }
    if (perm == LocationPermission.deniedForever) return false;
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  // ══════════════════════════════════════════
  //  추적 시작/중지
  // ══════════════════════════════════════════

  /// 15분 상시 추적 시작 (NFC 외출 태그에 의해 호출)
  DateTime? _lastGpsToggle;
  Future<void> startTracking() async {
    if (_isTracking) return;
    // 디바운스: 30초 이내 재호출 방지
    final now = DateTime.now();
    if (_lastGpsToggle != null && now.difference(_lastGpsToggle!).inSeconds < 30) {
      debugPrint('[Location] GPS 디바운스: 30초 이내 재호출 무시');
      return;
    }
    _lastGpsToggle = now;
    final ok = await requestPermissions();
    if (!ok) return;

    // 헤드리스 모드에서 캐싱된 기록 동기화
    try { await syncPendingLocations(); } catch (_) {}

    _isTracking = true;
    _locationState = LocationState.preparing;
    _motionState = MotionState.unknown;
    _stationaryCount = 0;
    _stationaryStart = null;
    await _saveState();

    // ★ #8: 첫 추적 시작 시 배터리 최적화 면제 요청
    final prefs = await SharedPreferences.getInstance();
    final batteryExemptionRequested = prefs.getBool('battery_exemption_requested') ?? false;
    if (!batteryExemptionRequested) {
      await requestBatteryOptimizationExemption();
      await prefs.setBool('battery_exemption_requested', true);
    }

    await FlutterForegroundTask.startService(
      notificationTitle: '📍 위치 추적 중',
      notificationText: '15분 간격 기록',
      serviceId: 200,
      callback: locationServiceCallback,
    );

    await _recordCurrentLocation();
    _scheduleNextRecord();
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    // 디바운스: 30초 이내 재호출 방지
    final now = DateTime.now();
    if (_lastGpsToggle != null && now.difference(_lastGpsToggle!).inSeconds < 30) {
      debugPrint('[Location] GPS 디바운스: 30초 이내 재호출 무시');
      return;
    }
    _lastGpsToggle = now;
    _isTracking = false;
    _isTravelMode = false;
    _locationState = LocationState.idle;
    _trackTimer?.cancel();
    _trackTimer = null;

    // 이동 구간이 있으면 먼저 종료
    if (_wasMoving && _movementStart != null) {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      await _finalizeMovement(now, dateStr);
      _wasMoving = false;
    }

    await _finalizeStay();
    _unknownStayStart = null;
    await _saveState();

    await FlutterForegroundTask.stopService();
  }

  // ══════════════════════════════════════════
  //  NFC 트리거: 여행 모드 전환
  // ══════════════════════════════════════════

  /// NFC 외출 태그 → 15분 간격으로 전환
  void setTravelMode(bool traveling) {
    _isTravelMode = traveling;
    if (traveling) {
      _locationState = LocationState.traveling;
      _motionState = MotionState.moving;
    } else {
      _locationState = LocationState.staying;
    }

    if (_isTracking) {
      _scheduleNextRecord(); // 간격 재조정
    }

    _updateNotification();
    debugPrint('[Location] Travel mode: $traveling');
  }

  /// NFC 귀가 태그 → 현재 체류를 "집"으로 강제 설정
  /// stopTracking() 호출 전에 실행하면 _finalizeStay()에서 "집 체류"로 기록됨
  void forceCurrentPlaceAsHome() {
    _currentPlaceName = '집';
    _currentPlaceId = _knownPlaces
        .where((p) => p.category == 'home')
        .map((p) => p.id)
        .firstOrNull;
    debugPrint('[Location] 🏠 현재 위치 → 집으로 강제 설정');
  }

  // ══════════════════════════════════════════
  //  스마트 GPS 간격
  // ══════════════════════════════════════════

  void _scheduleNextRecord() {
    _trackTimer?.cancel();

    Duration interval;
    if (_isTravelMode) {
      interval = _travelInterval;  // NFC 외출 → 15분
    } else if (_motionState == MotionState.moving) {
      interval = _movingInterval;  // 이동 감지 → 5분
    } else {
      interval = _idleInterval;    // 기본 → 15분
    }

    _trackTimer = Timer(interval, () async {
      if (!_isTracking) return;
      await _recordCurrentLocation();
      _scheduleNextRecord();
    });
  }

  void _detectMotion(Position current) {
    if (_prevPosition == null) {
      _prevPosition = current;
      _motionState = MotionState.unknown;
      return;
    }

    final dist = _haversineDistance(
      _prevPosition!.latitude, _prevPosition!.longitude,
      current.latitude, current.longitude,
    );

    if (dist > _moveThresholdMeters) {
      _motionState = MotionState.moving;
      _stationaryCount = 0;
      _stationaryStart = null; // 이동 시작 → 체류 타이머 리셋
      if (!_isTravelMode) {
        _locationState = LocationState.traveling;
      }
      _unknownStayStart = null;
    } else {
      _stationaryCount++;
      if (_stationaryCount >= _stationaryThreshold) {
        _motionState = MotionState.stationary;
        _stationaryStart ??= DateTime.now(); // 체류 시작 시각 기록
        if (_locationState == LocationState.traveling && !_isTravelMode) {
          _locationState = LocationState.staying;
        }
      }
    }
    _prevPosition = current;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      // F9 FIX: LocationAccuracy.best → high
      // best는 WiFi 스캔을 유발하여 꺼진 WiFi를 자동으로 켤 수 있음
      // high는 GPS만 사용하므로 WiFi 간섭 없음
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _lastPosition = pos;
      return pos;
    } catch (e) {
      debugPrint('[Location] Position error: $e');
      return null;
    }
  }

  Future<String?> getCurrentWifiSsid() async {
    // F9 FIX: WiFi SSID 조회는 이미 연결된 네트워크만 반환
    // WiFi가 꺼져있으면 null 반환 (스캔 유발 방지)
    try {
      final ssid = await _wifiChannel.invokeMethod<String>('getWifiSsid');
      if (ssid == null || ssid == '<unknown ssid>' || ssid.isEmpty) return null;
      return ssid;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════
  //  위치 기록 메인 로직 (v8.6 개편)
  //  이동 중: 개별 기록 안 함 → 이동 종료 시 단일 엔트리
  //  체류: 등록 장소 즉시 기록, 미등록 20분 후 기록
  // ══════════════════════════════════════════

  Future<void> _recordCurrentLocation() async {
    final pos = await getCurrentPosition();
    if (pos == null) return;

    _detectMotion(pos);

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm').format(now);

    String? placeName;
    String? placeId;
    String? placeCategory;
    String? wifiSsid;

    // 1. WiFi SSID 매칭
    wifiSsid = await getCurrentWifiSsid();
    if (wifiSsid != null) {
      final wifiMatch = _matchByWifi(wifiSsid);
      if (wifiMatch != null) {
        placeName = wifiMatch.name;
        placeId = wifiMatch.id;
        placeCategory = wifiMatch.category;
      }
    }

    // 2. 지오펜스 매칭
    if (placeName == null) {
      final geoMatch = _matchByGeofence(pos.latitude, pos.longitude);
      if (geoMatch != null) {
        placeName = geoMatch.name;
        placeId = geoMatch.id;
        placeCategory = geoMatch.category;
      }
    }

    // 3. 미등록 장소 → Google Places (정지 상태에서만)
    if (placeName == null && _motionState == MotionState.stationary) {
      placeName = await _tryNearbyPlaceName(pos.latitude, pos.longitude);
    }

    // ── 이동/체류 상태 전환 처리 ──

    final isNowAtKnownPlace = placeId != null;
    final isNowMoving = _motionState == MotionState.moving && !isNowAtKnownPlace;

    // 이동 시작 감지
    if (isNowMoving && !_wasMoving) {
      await _finalizeStay();
      _movementStart ??= now;
      _wasMoving = true;
      _currentPlaceName = null;
      _currentPlaceId = null;
      _locationState = LocationState.traveling;
      debugPrint('[Location] 🚶 이동 시작');
    }

    // 이동 → 체류 전환 (이동 구간 종료)
    if (!isNowMoving && _wasMoving) {
      await _finalizeMovement(now, dateStr);
      _wasMoving = false;
    }

    // 장소 변경 감지 (체류 중 다른 장소로)
    if (!isNowMoving) {
      final placeChanged = _currentPlaceId != placeId ||
          (_currentPlaceId == null && _currentPlaceName != placeName);

      if (placeChanged) {
        await _finalizeStay();
        _currentPlaceName = placeName;
        _currentPlaceId = placeId;
        _stayStart = now;

        if (placeId != null) {
          await _handleArrival(placeId, dateStr, timeStr);
        }

        _locationState = placeName != null
            ? LocationState.staying
            : LocationState.traveling;
      }

      // 미등록 장소 자동 태깅 (20분 체류)
      await _handleUnknownStay(pos, now, placeName);

      // 등록 장소 체류 중일 때만 LocationRecord 저장 (이동 중 스팸 방지)
      if (_currentPlaceName != null) {
        final record = LocationRecord(
          id: 'loc_${now.millisecondsSinceEpoch}',
          date: dateStr,
          timestamp: now.toIso8601String(),
          latitude: pos.latitude,
          longitude: pos.longitude,
          placeName: _currentPlaceName,
          placeId: placeId,
          placeCategory: placeCategory,
          wifiSsid: wifiSsid,
          durationMinutes: _stayStart != null
              ? now.difference(_stayStart!).inMinutes
              : 0,
        );
        try {
          await FirebaseService().saveLocationRecord(dateStr, record);
        } catch (_) {
          await _cacheLocally(record);
        }
      }
    }

    _updateNotification();
    await _saveState();

    // ── 3-③ 15분 체류 감지: 여행 모드에서 같은 위치 15분+ → 자동 이동 종료 ──
    if (_isTravelMode &&
        _motionState == MotionState.stationary &&
        _stationaryStart != null) {
      final dwellMin = DateTime.now().difference(_stationaryStart!).inMinutes;
      if (dwellMin >= _dwellAutoStopMinutes) {
        debugPrint('[Location] 🛑 15분 체류 감지 → 자동 이동 종료 (${dwellMin}분)');
        final autoNow = DateTime.now();
        final autoDateStr = DateFormat('yyyy-MM-dd').format(autoNow);
        final autoTimeStr = DateFormat('HH:mm').format(autoNow);
        await _finalizeMovement(autoNow, autoDateStr);
        _isTravelMode = false;
        _wasMoving = false;
        _locationState = _currentPlaceName != null
            ? LocationState.staying : LocationState.idle;
        _stationaryStart = null;

        // Firebase TimeRecord에 귀가시간 기록
        try {
          final fb = FirebaseService();
          final allRecords = await fb.getTimeRecords();
          final existing = allRecords[autoDateStr];
          if (existing?.returnHome == null) {
            await fb.updateTimeRecord(autoDateStr, TimeRecord(
              date: autoDateStr,
              wake: existing?.wake,
              study: existing?.study,
              studyEnd: existing?.studyEnd,
              outing: existing?.outing,
              returnHome: autoTimeStr,
              arrival: autoTimeStr,
            ));
            debugPrint('[Location] ✅ 15분 체류 → 자동 귀가 기록: $autoTimeStr');
          }
        } catch (e) {
          debugPrint('[Location] ⚠️ 자동 귀가 기록 실패: $e');
        }

        _updateNotification();
        await _saveState();
      }
    }

    // TaskHandler가 중복 기록 방지할 수 있도록 마지막 기록 시간 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('location_last_record_ms', DateTime.now().millisecondsSinceEpoch);
  }

  /// 이동 구간 종료 → 단일 "🚶 이동 중" 타임라인 엔트리 생성
  Future<void> _finalizeMovement(DateTime endTime, String dateStr) async {
    if (_movementStart == null) return;

    final dur = endTime.difference(_movementStart!).inMinutes;
    if (dur < 2) {
      _movementStart = null;
      return;
    }

    final entry = BehaviorTimelineEntry(
      id: 'bt_move_${_movementStart!.millisecondsSinceEpoch}',
      date: dateStr,
      startTime: DateFormat('HH:mm').format(_movementStart!),
      endTime: DateFormat('HH:mm').format(endTime),
      type: 'travel',
      label: '이동 중',
      emoji: '🚶',
      placeName: null,
      durationMinutes: dur,
    );

    try {
      await FirebaseService().saveBehaviorTimeline(dateStr, entry);
    } catch (_) {}
    LocalCacheService().appendTimelineEntry(dateStr, entry.toMap());

    debugPrint('[Location] 🚶 이동 종료: ${dur}분');
    _movementStart = null;
  }

  // ── 미등록 장소 자동 태깅 ──

  bool _unknownStayNotified = false;

  Future<void> _handleUnknownStay(Position pos, DateTime now, String? placeName) async {
    if (placeName != null && _currentPlaceId != null) {
      _unknownStayStart = null;
      _unknownStayNotified = false;
      return;
    }
    if (_motionState != MotionState.stationary) {
      _unknownStayStart = null;
      _unknownStayNotified = false;
      return;
    }

    _unknownStayStart ??= now;

    final stayMin = now.difference(_unknownStayStart!).inMinutes;
    if (stayMin >= _unknownStayMinutes && _currentPlaceName == null) {
      String autoName = await _tryNearbyPlaceName(pos.latitude, pos.longitude) ??
          '미등록 장소';
      _currentPlaceName = autoName;
      _stayStart ??= _unknownStayStart;

      // ★ 미등록 장소 20분 체류 시 알림
      if (!_unknownStayNotified) {
        _unknownStayNotified = true;
        _showUnknownPlaceNotification(autoName);
      }
    }
  }

  Future<void> _showUnknownPlaceNotification(String placeName) async {
    try {
      final n = FlutterLocalNotificationsPlugin();
      const android = AndroidNotificationDetails(
        'location_place', '장소 알림',
        channelDescription: '미등록 장소 체류 알림',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      await n.show(
        9900,
        '📍 이 장소를 등록하시겠습니까?',
        '$placeName 근처에서 ${_unknownStayMinutes}분 이상 머무르고 있습니다',
        const NotificationDetails(android: android),
      );
      debugPrint('[Location] 📍 미등록 장소 알림 발송: $placeName');
    } catch (e) {
      debugPrint('[Location] 알림 발송 실패: $e');
    }
  }

  // ── Google Places Nearby ──

  DateTime? _lastPlacesQuery;
  String? _lastPlacesResult;
  double? _lastPlacesLat;
  double? _lastPlacesLng;

  Future<String?> _tryNearbyPlaceName(double lat, double lng) async {
    if (_placesApiKey == 'YOUR_GOOGLE_PLACES_API_KEY') return null;

    if (_lastPlacesResult != null && _lastPlacesQuery != null &&
        DateTime.now().difference(_lastPlacesQuery!).inMinutes < 15 &&
        _lastPlacesLat != null && _lastPlacesLng != null) {
      final dist = _haversineDistance(lat, lng, _lastPlacesLat!, _lastPlacesLng!);
      if (dist < 100) return _lastPlacesResult;
    }

    try {
      final url = Uri.parse(
        '$_placesBaseUrl?location=$lat,$lng&radius=100'
        '&type=establishment&language=ko&key=$_placesApiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final results = json['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final place = NearbyPlaceResult.fromJson(
              results.first as Map<String, dynamic>);
          _lastPlacesResult = place.name;
          _lastPlacesQuery = DateTime.now();
          _lastPlacesLat = lat;
          _lastPlacesLng = lng;
          return place.name;
        }
      }
    } catch (e) {
      debugPrint('[Location] Places API error: $e');
    }
    return null;
  }

  // ── 도착 처리 ──

  /// 귀가 자동 종료: 집 반경 진입 시 즉시 GPS 추적 종료 (travel mode일 때)
  int _homeStayCount = 0;
  static const _homeStayThreshold = 1; // U1: 1회 감지 → 즉시 종료

  Future<void> _handleArrival(String placeId, String dateStr, String timeStr) async {
    final place = _knownPlaces.where((p) => p.id == placeId);
    if (place.isEmpty) return;
    final matched = place.first;

    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];

      await fb.updateTimeRecord(dateStr, TimeRecord(
        date: dateStr,
        wake: existing?.wake,
        study: existing?.study,
        studyEnd: existing?.studyEnd,
        outing: existing?.outing,
        returnHome: existing?.returnHome,
        arrival: timeStr,
      ));

      // ── U9: GPS 도착 → 공부시작 자동기록 ──
      if (matched.autoStudyStart && existing?.study == null) {
        await fb.updateTimeRecord(dateStr, TimeRecord(
          date: dateStr,
          wake: existing?.wake,
          study: timeStr,
          studyEnd: existing?.studyEnd,
          outing: existing?.outing,
          returnHome: existing?.returnHome,
          arrival: timeStr,
        ));
        // studyTimeRecords도 동시 업데이트
        try {
          await FirebaseFirestore.instance
              .collection('users/sJ8Pxusw9gR0tNR44RhkIge7OiG2/data')
              .doc('study')
              .set({
                'studyTimeRecords': {
                  dateStr: {'studyStart': timeStr, 'lastDevice': 'android'}
                }
              }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        debugPrint('[Location] 📖 공부시작 자동 기록: ${matched.name} $timeStr');
      }

      // ── U2: 도착 즉시 타임라인 엔트리 생성 ──
      final arrivalEntry = BehaviorTimelineEntry(
        id: 'bt_arrive_${DateTime.now().millisecondsSinceEpoch}',
        date: dateStr,
        startTime: DateFormat('HH:mm').format(DateTime.now()),
        endTime: DateFormat('HH:mm').format(DateTime.now()),
        type: 'stay',
        label: '${matched.name} 도착',
        emoji: _placeEmoji(placeId),
        placeName: matched.name,
        durationMinutes: 0,
      );
      try {
        await fb.saveBehaviorTimeline(dateStr, arrivalEntry);
      } catch (_) {}
      debugPrint('[Location] 📍 도착 타임라인 즉시 기록: ${matched.name}');

      // ── 귀가 자동 GPS 종료 ──
      if (matched.category == 'home' && _isTravelMode) {
        _homeStayCount++;
        debugPrint('[Location] 🏠 집 도착 감지 ($_homeStayCount/$_homeStayThreshold)');

        if (_homeStayCount >= _homeStayThreshold) {
          // returnHome 시간 기록
          if (existing?.returnHome == null) {
            await fb.updateTimeRecord(dateStr, TimeRecord(
              date: dateStr,
              wake: existing?.wake,
              study: existing?.study,
              studyEnd: existing?.studyEnd,
              outing: existing?.outing,
              returnHome: timeStr,
              arrival: timeStr,
            ));
            debugPrint('[Location] 🏠 귀가 시간 기록: $timeStr');
          }

          // GPS 추적 자동 종료
          await stopTracking();
          debugPrint('[Location] 🏠 귀가 감지 — GPS 추적 자동 종료 $timeStr');

          // 알림으로 사용자에게 알림
          FlutterForegroundTask.updateService(
            notificationTitle: '🏠 귀가 감지',
            notificationText: '${timeStr} GPS 추적이 자동 종료되었습니다',
          );

          _homeStayCount = 0;
        }
      } else {
        _homeStayCount = 0;
      }
    } catch (e) {
      debugPrint('[Location] Arrival error: $e');
    }
  }

  // ── 체류 마무리 ──

  Future<void> _finalizeStay() async {
    if (_stayStart == null) return;

    final now = DateTime.now();
    final dur = now.difference(_stayStart!).inMinutes;
    if (dur < 2) {
      _stayStart = null;
      _currentPlaceName = null;
      _currentPlaceId = null;
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_stayStart!);
    final type = (_currentPlaceName == null) ? 'travel' : 'stay';

    // 이동 중이었으면 이동으로 기록하지 않음 (별도 _finalizeMovement에서 처리)
    if (type == 'travel') {
      _stayStart = null;
      _currentPlaceName = null;
      _currentPlaceId = null;
      return;
    }

    final entry = BehaviorTimelineEntry(
      id: 'bt_${_stayStart!.millisecondsSinceEpoch}',
      date: dateStr,
      startTime: DateFormat('HH:mm').format(_stayStart!),
      endTime: DateFormat('HH:mm').format(now),
      type: 'stay',
      label: '$_currentPlaceName 체류',
      emoji: _currentPlaceId != null ? _placeEmoji(_currentPlaceId) : '📌',
      placeName: _currentPlaceName,
      durationMinutes: dur,
    );

    try {
      await FirebaseService().saveBehaviorTimeline(dateStr, entry);
    } catch (_) {}
    LocalCacheService().appendTimelineEntry(dateStr, entry.toMap());

    _stayStart = null;
    _currentPlaceName = null;
    _currentPlaceId = null;
  }

  // ── Foreground 알림 업데이트 ──

  void _updateNotification() {
    String title;
    String text;

    if (_isTravelMode) {
      title = '🚶 이동 중 (NFC 트리거)';
      text = '30초 간격 추적';
    } else {
      switch (_locationState) {
        case LocationState.staying:
          title = '📍 ${_currentPlaceName ?? "장소"} 체류 중';
          final dur = _stayStart != null
              ? DateTime.now().difference(_stayStart!).inMinutes : 0;
          text = '${dur}분 체류 · 15분 간격';
          break;
        case LocationState.traveling:
          title = '🚶 이동 감지';
          text = '5분 간격 추적';
          break;
        default:
          title = '📍 위치 추적 중';
          text = '15분 간격 · ${_motionState == MotionState.stationary ? "정지" : "감지 중"}';
      }
    }

    FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  // ── 매칭 ──

  KnownPlace? _matchByWifi(String ssid) {
    for (final p in _knownPlaces) {
      if (p.wifiSsid != null &&
          p.wifiSsid!.toLowerCase() == ssid.toLowerCase()) return p;
    }
    return null;
  }

  KnownPlace? _matchByGeofence(double lat, double lng) {
    KnownPlace? closest;
    double minDist = double.infinity;
    for (final p in _knownPlaces) {
      final dist = _haversineDistance(lat, lng, p.latitude, p.longitude);
      if (dist <= p.radiusMeters && dist < minDist) {
        minDist = dist;
        closest = p;
      }
    }
    return closest;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * pi / 180;

  // ── 장소 CRUD ──

  Future<void> addKnownPlace(KnownPlace place) async {
    _knownPlaces.add(place);
    await FirebaseService().saveKnownPlaces(_knownPlaces);
  }

  Future<void> removeKnownPlace(String placeId) async {
    _knownPlaces.removeWhere((p) => p.id == placeId);
    await FirebaseService().saveKnownPlaces(_knownPlaces);
  }

  Future<void> updateKnownPlace(KnownPlace updated) async {
    final idx = _knownPlaces.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) _knownPlaces[idx] = updated;
    await FirebaseService().saveKnownPlaces(_knownPlaces);
  }

  List<KnownPlace> get knownPlaces => List.unmodifiable(_knownPlaces);

  Future<void> _loadKnownPlaces() async {
    try {
      _knownPlaces = await FirebaseService().getKnownPlaces();
    } catch (_) {
      _knownPlaces = [];
    }
  }

  Future<List<LocationRecord>> getTodayLocations() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return getLocationsByDate(dateStr);
  }

  Future<List<BehaviorTimelineEntry>> getTodayTimeline() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return getTimelineByDate(dateStr);
  }

  /// N3: 특정 날짜의 위치 기록 조회
  Future<List<LocationRecord>> getLocationsByDate(String dateStr) async {
    try {
      return await FirebaseService().getLocationRecords(dateStr);
    } catch (_) {
      return [];
    }
  }

  /// N3: 특정 날짜의 타임라인 조회 — 로컬 캐시 우선
  Future<List<BehaviorTimelineEntry>> getTimelineByDate(String dateStr) async {
    // 1) 인메모리 캐시 (즉시 반환)
    final cached = LocalCacheService().getTimeline(dateStr);
    if (cached != null && cached.isNotEmpty) {
      _refreshTimelineInBackground(dateStr);
      return mergeTimeline(
          cached.map((m) => BehaviorTimelineEntry.fromMap(m)).toList());
    }
    // 2) Firestore (최초 로드)
    try {
      final raw = await FirebaseService().getBehaviorTimeline(dateStr);
      if (raw.isNotEmpty) {
        LocalCacheService().saveTimeline(dateStr, raw.map((e) => e.toMap()).toList());
      }
      return mergeTimeline(raw);
    } catch (_) {
      return [];
    }
  }

  void _refreshTimelineInBackground(String dateStr) {
    Future(() async {
      try {
        final raw = await FirebaseService().getBehaviorTimeline(dateStr);
        if (raw.isNotEmpty) {
          LocalCacheService().saveTimeline(
              dateStr, raw.map((e) => e.toMap()).toList());
        }
      } catch (_) {}
    });
  }

  /// N2: 타임라인 집계 병합
  /// 같은 장소 + 연속된 체류 (갭 30분 이내) → 하나로 병합
  /// 짧은 이동 (5분 이하) → 양쪽이 같은 장소면 체류로 흡수
  /// 자정 걸침 → 같은 날짜면 병합
  static List<BehaviorTimelineEntry> mergeTimeline(
      List<BehaviorTimelineEntry> entries) {
    if (entries.length <= 1) return entries;

    // 시간순 정렬 (원본 보존)
    final sorted = List<BehaviorTimelineEntry>.from(entries)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final merged = <BehaviorTimelineEntry>[];
    var i = 0;

    while (i < sorted.length) {
      var current = sorted[i];
      i++;

      while (i < sorted.length) {
        final next = sorted[i];

        // ── 같은 장소 체류 병합 ──
        if (current.type == 'stay' && next.type == 'stay' &&
            current.placeName != null && next.placeName != null &&
            current.placeName == next.placeName) {
          final currentEnd = DateTime.tryParse(current.endTime);
          final nextStart = DateTime.tryParse(next.startTime);
          if (currentEnd != null && nextStart != null) {
            final gapMin = nextStart.difference(currentEnd).inMinutes;
            // 갭 30분 이내 → 병합
            if (gapMin <= 30) {
              current = BehaviorTimelineEntry(
                id: current.id,
                date: current.date,
                startTime: current.startTime,
                endTime: next.endTime,
                type: 'stay',
                label: current.label,
                emoji: current.emoji,
                placeName: current.placeName,
                durationMinutes: current.durationMinutes + next.durationMinutes,
              );
              i++;
              continue;
            }
          }
        }

        // ── 짧은 이동 → 같은 장소면 체류 흡수 ──
        if (next.type == 'travel' && next.durationMinutes <= 5 &&
            current.type == 'stay' && (i + 1) < sorted.length) {
          final afterTravel = sorted[i + 1];
          if (afterTravel.type == 'stay' &&
              afterTravel.placeName == current.placeName) {
            // 이동 + 다음 체류를 현재에 흡수
            current = BehaviorTimelineEntry(
              id: current.id,
              date: current.date,
              startTime: current.startTime,
              endTime: afterTravel.endTime,
              type: 'stay',
              label: current.label,
              emoji: current.emoji,
              placeName: current.placeName,
              durationMinutes: current.durationMinutes +
                  next.durationMinutes + afterTravel.durationMinutes,
            );
            i += 2; // travel + next stay 둘 다 skip
            continue;
          }
        }

        break; // 병합 불가 → 다음으로
      }

      merged.add(current);
    }

    return merged;
  }

  /// N3: 특정 날짜 장소 요약
  Future<Map<String, int>> getPlaceSummaryByDate(String dateStr) async {
    final summary = <String, int>{};
    final timeline = await getTimelineByDate(dateStr);
    for (final entry in timeline) {
      if (entry.type == 'stay' && entry.placeName != null && entry.durationMinutes > 0) {
        summary[entry.placeName!] = (summary[entry.placeName!] ?? 0) + entry.durationMinutes;
      }
    }

    // 오늘인 경우 현재 진행 중 체류 추가
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (dateStr == today && _currentPlaceName != null && _stayStart != null) {
      final currentMin = DateTime.now().difference(_stayStart!).inMinutes;
      if (currentMin > 0) {
        summary[_currentPlaceName!] = (summary[_currentPlaceName!] ?? 0) + currentMin;
      }
    }

    // ★ FIX: GPS 추적 종료 후 집 체류 보정 (TimeRecord 기반)
    // 귀가 NFC→GPS 종료 후에는 집 체류가 누적되지 않으므로 TimeRecord에서 보정
    if (!_isTracking || _currentPlaceName == null) {
      try {
        final records = await FirebaseService().getTimeRecords();
        final tr = records[dateStr];
        if (tr?.returnHome != null) {
          final rhParts = tr!.returnHome!.split(':');
          int rhMin = int.parse(rhParts[0]) * 60 + int.parse(rhParts[1]);

          // 끝 시점: 취침 or 현재시각
          int endMin;
          if (tr.bedTime != null) {
            final btParts = tr.bedTime!.split(':');
            endMin = int.parse(btParts[0]) * 60 + int.parse(btParts[1]);
          } else {
            final now = DateTime.now();
            endMin = now.hour * 60 + now.minute;
          }

          // 자정 넘김 보정
          if (endMin < rhMin) endMin += 1440;
          final homeDur = endMin - rhMin;

          if (homeDur > 0 && homeDur < 720) {
            // 기존 타임라인 "집" 체류 대비 부족분만 추가
            final existing = summary['집'] ?? 0;
            if (homeDur > existing) {
              summary['집'] = homeDur;
            }
          }
        }
      } catch (_) {}
    }

    // 타임라인 비었으면 로케이션 레코드 폴백
    if (summary.isEmpty) {
      final locations = await getLocationsByDate(dateStr);
      final lastDur = <String, int>{};
      for (final loc in locations) {
        final name = loc.placeName ?? '알 수 없는 장소';
        if (loc.durationMinutes > (lastDur[name] ?? 0)) {
          lastDur[name] = loc.durationMinutes;
        }
      }
      summary.addAll(lastDur);
    }

    return summary;
  }

  Future<Map<String, int>> getTodayPlaceSummary() async {
    final dateStr = StudyDateUtils.todayKey();
    return getPlaceSummaryByDate(dateStr);
  }

  Future<KnownPlace?> registerCurrentLocation({
    required String name,
    required String category,
    String? wifiSsid,
    int radiusMeters = 100,
    bool autoStudyStart = false,
  }) async {
    final pos = await getCurrentPosition();
    if (pos == null) return null;

    final place = KnownPlace(
      id: 'kp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      emoji: KnownPlace.categoryEmoji(category),
      category: category,
      latitude: pos.latitude,
      longitude: pos.longitude,
      radiusMeters: radiusMeters,
      wifiSsid: wifiSsid,
      autoStudyStart: autoStudyStart,
    );
    await addKnownPlace(place);
    return place;
  }

  String _placeEmoji(String? placeId) {
    if (placeId == null) return '📍';
    final p = _knownPlaces.where((p) => p.id == placeId);
    return p.isNotEmpty ? p.first.emoji : '📍';
  }

  // ── GPS는 NFC 외출/귀가로만 제어 (WiFi 자동 ON/OFF 제거) ──

  // ── 상태 저장/복원 ──

  Future<void> _saveState() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('location_tracking', _isTracking);
    await p.setString('location_state', _locationState.name);
    await p.setString('motion_state', _motionState.name);
    await p.setBool('location_travel_mode', _isTravelMode);
    if (_currentPlaceName != null) {
      await p.setString('location_current_place', _currentPlaceName!);
    } else {
      await p.remove('location_current_place');
    }
    if (_currentPlaceId != null) {
      await p.setString('location_current_place_id', _currentPlaceId!);
    } else {
      await p.remove('location_current_place_id');
    }
    if (_stayStart != null) {
      await p.setString('location_stay_start', _stayStart!.toIso8601String());
    } else {
      await p.remove('location_stay_start');
    }
  }

  Future<void> _restoreState() async {
    final p = await SharedPreferences.getInstance();
    _isTracking = p.getBool('location_tracking') ?? false;
    _isTravelMode = p.getBool('location_travel_mode') ?? false;
    _currentPlaceName = p.getString('location_current_place');
    _currentPlaceId = p.getString('location_current_place_id');
    final ss = p.getString('location_stay_start');
    if (ss != null) _stayStart = DateTime.parse(ss);

    final lsName = p.getString('location_state') ?? 'idle';
    _locationState = LocationState.values.firstWhere(
      (s) => s.name == lsName, orElse: () => LocationState.idle);
    final msName = p.getString('motion_state') ?? 'unknown';
    _motionState = MotionState.values.firstWhere(
      (s) => s.name == msName, orElse: () => MotionState.unknown);

    if (_isTracking) {
      // v8.7: 앱 재시작 시 GPS 자동 재개 (포그라운드 서비스가 살아있으므로)
      debugPrint('[Location] ✅ 이전 추적 상태 복원 — GPS 자동 재개');
      _isTracking = false; // startTracking에서 다시 true로 설정
      // 비동기로 재시작 (initialize 완료 후)
      Future.delayed(const Duration(seconds: 2), () {
        startTracking();
      });
    }
  }

  Future<void> _cacheLocally(LocationRecord record) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('pending_locations') ?? [];
    list.add(jsonEncode(record.toMap()));
    await p.setStringList('pending_locations', list);
  }

  Future<void> syncPendingLocations() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('pending_locations');
    if (list == null || list.isEmpty) return;
    for (final item in list) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final record = LocationRecord.fromMap(map);
        await FirebaseService().saveLocationRecord(record.date, record);
      } catch (_) {}
    }
    await p.remove('pending_locations');
  }
}