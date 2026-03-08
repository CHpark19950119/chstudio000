import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import '../models/models.dart';
import 'firebase_service.dart';
import 'creature_service.dart';
import '../utils/study_date_utils.dart';

// ══════════════════════════════════════════
//  FocusService — ChangeNotifier Singleton
//  Hive-first 데이터 흐름, 세션 기록 보장
// ══════════════════════════════════════════

class FocusService extends ChangeNotifier {
  static final FocusService _instance = FocusService._internal();
  factory FocusService() => _instance;
  FocusService._internal();

  static const _boxName = 'focus_data';

  // ── 상태 ──
  bool _isRunning = false;
  String _currentMode = 'study';
  String _currentSubject = '자료해석';
  DateTime? _sessionStart;
  DateTime? _segmentStart;
  int _totalStudyMin = 0;
  int _totalLectureMin = 0;
  int _totalRestMin = 0;
  final List<FocusSegment> _segments = [];
  int _accumulatedActiveSec = 0;

  // ── 화장실 휴식 ──
  Timer? _bathroomTimer;
  int _bathroomSec = 0;
  String? _prevModeBeforeBathroom;

  // ── 문제 시간 서브타이머 ──
  DateTime? _problemStart;
  final List<({int seconds, String subject})> _problemLaps = [];
  bool _subTimerActive = false;

  // ── 거치대 ──
  bool _isOnCradle = false;
  bool _cradlePaused = false;
  String? _preModeBeforeCradle;
  int _cradleFocusSec = 0;
  int _cradleRestSec = 0;
  int _cradleRestCount = 0;
  final List<int> _cradleRestDurations = [];
  DateTime? _cradleRestStart;

  // ── 오늘 기록 (Hive에서 로드) ──
  List<FocusCycle> _todaySessions = [];
  int _todayStudyMinutes = 0;

  // ── 내부 타이머 ──
  Timer? _uiTimer;
  Timer? _liveSyncTimer;

  // ── Getters ──
  bool get isRunning => _isRunning;
  String get currentMode => _currentMode;
  String get currentSubject => _currentSubject;
  DateTime? get sessionStart => _sessionStart;

  // 화장실
  bool get isBathroomBreak => _bathroomTimer != null;
  int get bathroomSec => _bathroomSec;
  String? get prevModeBeforeBathroom => _prevModeBeforeBathroom;

  // 서브타이머
  bool get subTimerActive => _subTimerActive;
  DateTime? get problemStart => _problemStart;
  List<({int seconds, String subject})> get problemLaps => List.unmodifiable(_problemLaps);

  // 거치대
  bool get isOnCradle => _isOnCradle;
  bool get cradlePaused => _cradlePaused;
  int get cradleFocusSec => _cradleFocusSec;
  int get cradleRestSec => _cradleRestSec;
  int get cradleRestCount => _cradleRestCount;
  List<int> get cradleRestDurations => List.unmodifiable(_cradleRestDurations);

  // 오늘 기록
  List<FocusCycle> get todaySessions => List.unmodifiable(_todaySessions);
  int get todayStudyMinutes => _todayStudyMinutes;
  int get todaySessionCount => _todaySessions.length;

  int get concentrationRate {
    final total = _cradleFocusSec + _cradleRestSec;
    if (total < 30) return 100;
    return ((_cradleFocusSec / total) * 100).round().clamp(0, 100);
  }

  // ── 초기화 ──
  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cheonhong_focus_silent',
        channelName: '집중 세션 (조용히)',
        channelDescription: 'CHEONHONG STUDIO 집중 타이머 - 상태바 전용',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await _loadTodaySessions();
  }

  // ══════════════════════════════════════════
  //  Hive 세션 기록 CRUD
  // ══════════════════════════════════════════

  Future<Box> _openBox() async => Hive.openBox(_boxName);

  Future<void> _loadTodaySessions() async {
    try {
      final box = await _openBox();
      final dateStr = StudyDateUtils.todayKey();
      final raw = box.get('sessions_$dateStr');
      if (raw != null) {
        final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        _todaySessions = list.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return FocusCycle.fromMap(m);
        }).toList();
        _todayStudyMinutes = _todaySessions.fold(0, (s, c) => s + c.effectiveMin);
      } else {
        _todaySessions = [];
        _todayStudyMinutes = 0;
      }
      debugPrint('[FocusService] loaded ${_todaySessions.length} sessions for $dateStr (${_todayStudyMinutes}min)');
    } catch (e) {
      debugPrint('[FocusService] loadTodaySessions error: $e');
      _todaySessions = [];
      _todayStudyMinutes = 0;
    }
  }

  Future<void> _saveSessionToHive(FocusCycle cycle) async {
    try {
      final box = await _openBox();
      final dateStr = cycle.date;
      // 기존 목록 로드
      final raw = box.get('sessions_$dateStr');
      List<Map<String, dynamic>> list = [];
      if (raw != null) {
        final decoded = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      list.add(cycle.toMap());
      await box.put('sessions_$dateStr', list);
      // 오늘 총 순공시간 갱신
      final total = list.fold<int>(0, (s, m) {
        return s + ((m['effectiveMin'] ?? 0) as int);
      });
      await box.put('todayStudyMin_$dateStr', total);
      debugPrint('[FocusService] saved session to Hive: ${cycle.id} (${cycle.effectiveMin}min)');
    } catch (e) {
      debugPrint('[FocusService] saveSessionToHive error: $e');
    }
  }

  /// 외부에서 기록 리프레시 (기록 탭 진입 시)
  Future<void> refreshTodaySessions() async {
    await _loadTodaySessions();
    notifyListeners();
  }

  /// 특정 날짜 세션 목록 (Hive 우선 → Firebase fallback)
  Future<List<FocusCycle>> getSessionsForDate(String dateStr) async {
    // 1. Hive
    try {
      final box = await _openBox();
      final raw = box.get('sessions_$dateStr');
      if (raw != null) {
        final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        final sessions = list.map((e) => FocusCycle.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        if (sessions.isNotEmpty) return sessions;
      }
    } catch (_) {}
    // 2. Firebase fallback
    try {
      final cycles = await FirebaseService().getFocusCycles(dateStr)
          .timeout(const Duration(seconds: 3));
      // Hive에 캐시
      if (cycles.isNotEmpty) {
        try {
          final box = await _openBox();
          await box.put('sessions_$dateStr', cycles.map((c) => c.toMap()).toList());
        } catch (_) {}
      }
      return cycles;
    } catch (_) {}
    return [];
  }

  /// 최근 7일 일별 순공시간 (Hive → Firebase fallback)
  Future<Map<String, int>> getWeeklyStudyMinutes() async {
    final result = <String, int>{};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dt = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final sessions = await getSessionsForDate(dateStr);
      result[dateStr] = sessions.fold(0, (s, c) => s + c.effectiveMin);
    }
    return result;
  }

  // ══════════════════════════════════════════
  //  세션 시작 / 종료
  // ══════════════════════════════════════════

  Future<void> startSession({
    required String subject,
    String mode = 'study',
  }) async {
    _currentSubject = subject;
    _currentMode = mode;
    _sessionStart = DateTime.now();
    _segmentStart = DateTime.now();
    _totalStudyMin = 0;
    _totalLectureMin = 0;
    _totalRestMin = 0;
    _accumulatedActiveSec = 0;
    _segments.clear();
    _isRunning = true;

    // 거치대/서브타이머 초기화
    _cradleFocusSec = 0;
    _cradleRestSec = 0;
    _cradleRestCount = 0;
    _cradleRestDurations.clear();
    _cradleRestStart = null;
    _cradlePaused = false;
    _preModeBeforeCradle = null;
    _subTimerActive = false;
    _problemStart = null;
    _problemLaps.clear();

    await _recordStudyStartIfFirst();
    await FlutterForegroundTask.startService(
      notificationTitle: _notifTitle(),
      notificationText: '시작됨',
      callback: _focusCallback,
    );
    _startLiveSync();
    _startUiTimer();
    await _saveState();
    notifyListeners();
  }

  Future<FocusCycle> endSession() async {
    _endSegment();
    _isRunning = false;
    _uiTimer?.cancel();
    _uiTimer = null;
    _bathroomTimer?.cancel();
    _bathroomTimer = null;
    _stopLiveSync();
    await FlutterForegroundTask.stopService();

    final effectiveMin = _totalStudyMin + (_totalLectureMin * 0.5).round();
    final cycle = FocusCycle(
      id: 'fc_${_sessionStart!.millisecondsSinceEpoch}',
      date: StudyDateUtils.todayKey(_sessionStart!),
      startTime: _sessionStart!.toIso8601String(),
      endTime: DateTime.now().toIso8601String(),
      subject: _currentSubject,
      segments: List.from(_segments),
      studyMin: _totalStudyMin,
      lectureMin: _totalLectureMin,
      effectiveMin: effectiveMin,
      restMin: _totalRestMin,
    );

    // ★ 핵심: Hive에 즉시 저장 + 로컬 목록 갱신
    _todaySessions.add(cycle);
    _todayStudyMinutes += effectiveMin;
    await _saveSessionToHive(cycle);
    await _clearState();
    notifyListeners(); // ← UI 즉시 갱신

    // 백그라운드 Firebase write
    _syncToFirebase(cycle);
    try {
      await FirebaseService().clearLiveFocus(cycle.date);
    } catch (_) {}

    return cycle;
  }

  // ══════════════════════════════════════════
  //  모드 전환 / 과목 변경
  // ══════════════════════════════════════════

  Future<void> switchMode(String newMode) async {
    if (_currentMode == newMode) return;

    final prevMode = _currentMode;
    final segSec = _segmentStart != null
        ? DateTime.now().difference(_segmentStart!).inSeconds
        : 0;

    if (prevMode == 'study' || prevMode == 'lecture') {
      _accumulatedActiveSec += segSec;
    }

    _endSegment();
    _currentMode = newMode;
    _segmentStart = DateTime.now();

    await FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle(),
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  Future<void> changeSubject(String subject) async {
    if (_currentMode == 'study' || _currentMode == 'lecture') {
      final segSec = _segmentStart != null
          ? DateTime.now().difference(_segmentStart!).inSeconds
          : 0;
      _accumulatedActiveSec += segSec;
    }

    _endSegment();
    _currentSubject = subject;
    _segmentStart = DateTime.now();
    await FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle(),
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  화장실 휴식
  // ══════════════════════════════════════════

  Future<void> startBathroomBreak() async {
    _prevModeBeforeBathroom = _currentMode;
    _bathroomSec = 0;
    await switchMode('rest');
    _bathroomTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _bathroomSec++;
    });
    notifyListeners();
  }

  Future<void> endBathroomBreak() async {
    _bathroomTimer?.cancel();
    _bathroomTimer = null;
    final restoreMode = _prevModeBeforeBathroom ?? 'study';
    _prevModeBeforeBathroom = null;
    _bathroomSec = 0;
    await switchMode(restoreMode);
  }

  // ══════════════════════════════════════════
  //  문제 시간 서브타이머
  // ══════════════════════════════════════════

  void toggleSubTimer() {
    if (_subTimerActive) {
      if (_problemStart != null) {
        final elapsed = DateTime.now().difference(_problemStart!).inSeconds;
        _problemLaps.add((seconds: elapsed, subject: _currentSubject));
      }
      _subTimerActive = false;
      _problemStart = null;
    } else {
      _subTimerActive = true;
      _problemStart = DateTime.now();
    }
    notifyListeners();
  }

  void resetSubTimer() {
    _subTimerActive = false;
    _problemStart = null;
    _problemLaps.clear();
    notifyListeners();
  }

  int get problemElapsedSec {
    if (!_subTimerActive || _problemStart == null) return 0;
    return DateTime.now().difference(_problemStart!).inSeconds;
  }

  // ══════════════════════════════════════════
  //  거치대 (Cradle)
  // ══════════════════════════════════════════

  void onCradleChanged(bool onCradle) {
    if (!_isRunning) {
      _isOnCradle = onCradle;
      notifyListeners();
      return;
    }

    final wasOnCradle = _isOnCradle;
    _isOnCradle = onCradle;

    if (onCradle && !wasOnCradle) {
      if (_cradlePaused) {
        _cradlePaused = false;
        if (_cradleRestStart != null) {
          final restSec = DateTime.now().difference(_cradleRestStart!).inSeconds;
          _cradleRestDurations.add(restSec);
          _cradleRestStart = null;
        }
        final restoreMode = _preModeBeforeCradle ?? 'study';
        _preModeBeforeCradle = null;
        switchMode(restoreMode);
      }
    } else if (!onCradle && wasOnCradle) {
      _cradlePaused = true;
      _preModeBeforeCradle = _currentMode;
      _cradleRestCount++;
      _cradleRestStart = DateTime.now();
      switchMode('rest');
    }

    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  현재 상태 스냅샷
  // ══════════════════════════════════════════

  FocusTimerState getCurrentState() {
    if (!_isRunning || _segmentStart == null) return FocusTimerState.idle();
    final now = DateTime.now();
    final segSec = now.difference(_segmentStart!).inSeconds;
    final effMin = _totalStudyMin + (_totalLectureMin * 0.5).round();
    int curMin = segSec ~/ 60;
    int dispEff = effMin;
    if (_currentMode == 'study') {
      dispEff += curMin;
    } else if (_currentMode == 'lecture') {
      dispEff += (curMin * 0.5).round();
    }
    final totalActive = _totalStudyMin + _totalLectureMin + curMin;

    final sessionSec = _sessionStart != null
        ? now.difference(_sessionStart!).inSeconds
        : 0;
    int activeElapsedSec = _accumulatedActiveSec;
    if (_currentMode == 'study' || _currentMode == 'lecture') {
      activeElapsedSec += segSec;
    }

    return FocusTimerState(
      isRunning: true,
      mode: _currentMode,
      subject: _currentSubject,
      segmentElapsedSeconds: segSec,
      sessionElapsedSeconds: sessionSec,
      activeElapsedSeconds: activeElapsedSec,
      totalStudyMin: _currentMode == 'study' ? _totalStudyMin + curMin : _totalStudyMin,
      totalLectureMin: _currentMode == 'lecture' ? _totalLectureMin + curMin : _totalLectureMin,
      totalRestMin: _currentMode == 'rest' ? _totalRestMin + curMin : _totalRestMin,
      effectiveMin: dispEff,
      cycleProgress: (totalActive % 90) / 90.0,
      cycleCount: totalActive ~/ 90,
      sessionStartTime: _sessionStart,
    );
  }

  // ══════════════════════════════════════════
  //  포커스 기록 삭제 + studyTimeRecord 보정
  // ══════════════════════════════════════════

  Future<void> deleteFocusCycle(String date, String cycleId) async {
    try {
      final fb = FirebaseService();
      final cycles = await fb.getFocusCycles(date);
      final target = cycles.firstWhere((c) => c.id == cycleId,
          orElse: () => FocusCycle(id: '', date: date, startTime: '', subject: ''));

      cycles.removeWhere((c) => c.id == cycleId);
      await fb.overwriteFocusCycles(date, cycles);

      if (target.id.isNotEmpty) {
        final existing = await fb.getStudyTimeRecords();
        final prev = existing[date];
        if (prev != null) {
          final record = StudyTimeRecord(
            date: date,
            totalMinutes: (prev.totalMinutes - target.studyMin - target.lectureMin).clamp(0, 999999),
            studyMinutes: (prev.studyMinutes - target.studyMin).clamp(0, 999999),
            lectureMinutes: (prev.lectureMinutes - target.lectureMin).clamp(0, 999999),
            effectiveMinutes: (prev.effectiveMinutes - target.effectiveMin).clamp(0, 999999),
          );
          await fb.updateStudyTimeRecord(date, record);
        }
      }

      // Hive 동기화
      try {
        final box = await _openBox();
        final raw = box.get('sessions_$date');
        if (raw != null) {
          final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
          list.removeWhere((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return m['id'] == cycleId;
          });
          await box.put('sessions_$date', list);
        }
      } catch (_) {}

      // 오늘이면 로컬 목록도 갱신
      if (date == StudyDateUtils.todayKey()) {
        _todaySessions.removeWhere((c) => c.id == cycleId);
        _todayStudyMinutes = _todaySessions.fold(0, (s, c) => s + c.effectiveMin);
        notifyListeners();
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════
  //  내부 헬퍼
  // ══════════════════════════════════════════

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;
      if (_isOnCradle && !_cradlePaused) {
        _cradleFocusSec++;
      } else if (_cradlePaused) {
        _cradleRestSec++;
      }
      notifyListeners();
    });
  }

  void _endSegment() {
    if (_segmentStart == null) return;
    final now = DateTime.now();
    final dur = now.difference(_segmentStart!).inMinutes;
    if (dur > 0) {
      _segments.add(FocusSegment(
        startTime: _segmentStart!.toIso8601String(),
        endTime: now.toIso8601String(),
        subject: _currentSubject,
        mode: _currentMode,
        durationMin: dur,
      ));
      switch (_currentMode) {
        case 'study':
          _totalStudyMin += dur;
          break;
        case 'lecture':
          _totalLectureMin += dur;
          break;
        case 'rest':
          _totalRestMin += dur;
          break;
      }
    }
  }

  String _notifTitle() {
    final e =
        _currentMode == 'study' ? '📖' : _currentMode == 'lecture' ? '🎧' : '☕';
    final t =
        _currentMode == 'study' ? '집중공부' : _currentMode == 'lecture' ? '강의듣기' : '휴식';
    return '$e $t · $_currentSubject';
  }

  String _notifText() {
    final eff = _totalStudyMin + (_totalLectureMin * 0.5).round();
    final sessionMin = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!).inMinutes : 0;
    return '순공 ${eff ~/ 60}h${eff % 60}m · 세션 ${sessionMin}분';
  }

  Future<void> _recordStudyStartIfFirst() async {
    final dateStr = StudyDateUtils.todayKey();
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      if (existing?.study != null) return;
      await fb.updateTimeRecord(dateStr,
          TimeRecord(date: dateStr, wake: existing?.wake, study: timeStr));
    } catch (_) {
      try {
        final box = await _openBox();
        await box.put('study_start_$dateStr', timeStr);
      } catch (_) {}
    }
  }

  Future<void> _syncToFirebase(FocusCycle cycle) async {
    final totalSec = (cycle.studyMin + cycle.lectureMin + cycle.restMin) * 60;
    if (totalSec < 10 && cycle.effectiveMin == 0) {
      debugPrint('[FocusService] 10초 미만 세션 무시: ${totalSec}s');
      return;
    }
    final addedMin = cycle.studyMin + cycle.lectureMin;
    try {
      final fb = FirebaseService();

      await fb.saveFocusCycle(cycle.date, cycle);
      final existing = await fb.getStudyTimeRecords();
      final prev = existing[cycle.date];
      final record = StudyTimeRecord(
        date: cycle.date,
        totalMinutes: (prev?.totalMinutes ?? 0) + addedMin,
        studyMinutes: (prev?.studyMinutes ?? 0) + cycle.studyMin,
        lectureMinutes: (prev?.lectureMinutes ?? 0) + cycle.lectureMin,
        effectiveMinutes: (prev?.effectiveMinutes ?? 0) + cycle.effectiveMin,
      );
      await fb.updateStudyTimeRecord(cycle.date, record);

      if (addedMin > 0) {
        try {
          await fb.updateTodayField('studyTime.total', FieldValue.increment(addedMin));
          final subjectMin = <String, int>{};
          for (final seg in cycle.segments) {
            if (seg.mode == 'study' || seg.mode == 'lecture') {
              subjectMin[seg.subject] = (subjectMin[seg.subject] ?? 0) + seg.durationMin;
            }
          }
          for (final entry in subjectMin.entries) {
            await fb.updateTodayField('studyTime.subjects.${entry.key}', FieldValue.increment(entry.value));
          }
        } catch (e) {
          debugPrint('[FocusService] today update fail: $e');
        }
      }

      try {
        fb.appendFocusSessionToHistory(cycle.date, {
          'subject': cycle.subject,
          'start': cycle.startTime,
          'end': cycle.endTime ?? DateTime.now().toIso8601String(),
          'minutes': addedMin,
          'effectiveMin': cycle.effectiveMin,
        });
      } catch (_) {}

      debugPrint('[FocusService] sync OK: ${cycle.date} ${cycle.effectiveMin}min');

      if (addedMin > 0) {
        try {
          await CreatureService().addStudyReward(addedMin);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[FocusService] sync FAIL: $e');
    }
  }

  // ── 실시간 동기화 (30초마다) ──

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncLiveProgress();
    });
  }

  void _stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  Future<void> _syncLiveProgress() async {
    if (!_isRunning) return;
    try {
      final fb = FirebaseService();
      final st = getCurrentState();
      final dateStr = StudyDateUtils.todayKey(_sessionStart!);
      await fb.updateLiveFocus(dateStr, {
        'isRunning': true,
        'mode': st.mode,
        'subject': st.subject,
        'effectiveMin': st.effectiveMin,
        'studyMin': st.totalStudyMin,
        'lectureMin': st.totalLectureMin,
        'restMin': st.totalRestMin,
        'lastUpdate': DateTime.now().toIso8601String(),
        'lastDevice': 'android',
      });
    } catch (_) {}
  }

  // ── 상태 저장/복원 (Hive) ──

  Future<void> _saveState() async {
    try {
      final box = await _openBox();
      await box.put('focus_running', _isRunning);
      await box.put('focus_mode', _currentMode);
      await box.put('focus_subject', _currentSubject);
      if (_sessionStart != null) {
        await box.put('focus_session_start', _sessionStart!.toIso8601String());
      }
      if (_segmentStart != null) {
        await box.put('focus_segment_start', _segmentStart!.toIso8601String());
      }
      await box.put('focus_study_min', _totalStudyMin);
      await box.put('focus_lecture_min', _totalLectureMin);
      await box.put('focus_rest_min', _totalRestMin);
      await box.put('focus_accumulated_active_sec', _accumulatedActiveSec);
    } catch (e) {
      debugPrint('[FocusService] saveState error: $e');
    }
  }

  Future<bool> restoreState() async {
    try {
      final box = await _openBox();
      _isRunning = box.get('focus_running', defaultValue: false) as bool;
      if (!_isRunning) return false;
      _currentMode = box.get('focus_mode', defaultValue: 'study') as String;
      _currentSubject = box.get('focus_subject', defaultValue: '자료해석') as String;
      final ss = box.get('focus_session_start') as String?;
      if (ss != null) _sessionStart = DateTime.parse(ss);
      final sg = box.get('focus_segment_start') as String?;
      if (sg != null) _segmentStart = DateTime.parse(sg);
      _totalStudyMin = box.get('focus_study_min', defaultValue: 0) as int;
      _totalLectureMin = box.get('focus_lecture_min', defaultValue: 0) as int;
      _totalRestMin = box.get('focus_rest_min', defaultValue: 0) as int;
      _accumulatedActiveSec = box.get('focus_accumulated_active_sec', defaultValue: 0) as int;
      _startLiveSync();
      _startUiTimer();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[FocusService] restoreState error: $e');
      return false;
    }
  }

  Future<void> _clearState() async {
    try {
      final box = await _openBox();
      for (final k in [
        'focus_running', 'focus_mode', 'focus_subject',
        'focus_session_start', 'focus_segment_start',
        'focus_study_min', 'focus_lecture_min', 'focus_rest_min',
        'focus_accumulated_active_sec',
      ]) {
        await box.delete(k);
      }
    } catch (e) {
      debugPrint('[FocusService] clearState error: $e');
    }
  }
}

// ── Foreground Task Callback ──

@pragma('vm:entry-point')
void _focusCallback() {
  FlutterForegroundTask.setTaskHandler(_FocusHandler());
}

class _FocusHandler extends TaskHandler {
  int _tick = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _tick = 0;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick++;
    if (_tick % 10 == 0) {
      Hive.openBox('focus_data').then((box) {
        final sm = box.get('focus_study_min', defaultValue: 0) as int;
        final lm = box.get('focus_lecture_min', defaultValue: 0) as int;
        final mode = box.get('focus_mode', defaultValue: 'study') as String;
        final subject = box.get('focus_subject', defaultValue: '') as String;
        final sgStr = box.get('focus_segment_start') as String?;
        final ssStr = box.get('focus_session_start') as String?;
        int cur = 0;
        if (sgStr != null) {
          cur = DateTime.now().difference(DateTime.parse(sgStr)).inMinutes;
        }
        int sessionMin = 0;
        if (ssStr != null) {
          sessionMin = DateTime.now().difference(DateTime.parse(ssStr)).inMinutes;
        }
        final ts = mode == 'study' ? sm + cur : sm;
        final tl = mode == 'lecture' ? lm + cur : lm;
        final eff = ts + (tl * 0.5).round();
        final modeEmoji = mode == 'study' ? '📖' : mode == 'lecture' ? '🎧' : '☕';
        final modeLabel = mode == 'study' ? '집중' : mode == 'lecture' ? '강의' : '휴식';
        FlutterForegroundTask.updateService(
            notificationTitle: '$modeEmoji $modeLabel · $subject',
            notificationText: '순공 ${eff ~/ 60}h${eff % 60}m · 세션 ${sessionMin}분');
      }).catchError((_) {});
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

// ── FocusTimerState (읽기 전용 스냅샷) ──

class FocusTimerState {
  final bool isRunning;
  final String mode;
  final String subject;
  final int segmentElapsedSeconds;
  final int sessionElapsedSeconds;
  final int activeElapsedSeconds;
  final int totalStudyMin;
  final int totalLectureMin;
  final int totalRestMin;
  final int effectiveMin;
  final double cycleProgress;
  final int cycleCount;
  final DateTime? sessionStartTime;

  FocusTimerState({
    required this.isRunning,
    required this.mode,
    required this.subject,
    required this.segmentElapsedSeconds,
    this.sessionElapsedSeconds = 0,
    this.activeElapsedSeconds = 0,
    required this.totalStudyMin,
    required this.totalLectureMin,
    required this.totalRestMin,
    required this.effectiveMin,
    required this.cycleProgress,
    required this.cycleCount,
    this.sessionStartTime,
  });

  factory FocusTimerState.idle() => FocusTimerState(
        isRunning: false, mode: 'study', subject: '',
        segmentElapsedSeconds: 0, sessionElapsedSeconds: 0,
        activeElapsedSeconds: 0,
        totalStudyMin: 0, totalLectureMin: 0, totalRestMin: 0,
        effectiveMin: 0, cycleProgress: 0, cycleCount: 0);

  String get effectiveTimeFormatted {
    return '${effectiveMin ~/ 60}h ${effectiveMin % 60}m';
  }

  String get mainTimerFormatted {
    final sec = mode == 'rest' ? segmentElapsedSeconds : activeElapsedSeconds;
    return _formatSec(sec);
  }

  String get segmentTimeFormatted => _formatSec(segmentElapsedSeconds);
  String get sessionTimeFormatted => _formatSec(sessionElapsedSeconds);

  static String _formatSec(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
