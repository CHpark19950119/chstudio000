import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/models.dart';
import 'firebase_service.dart';
import 'creature_service.dart';
import '../utils/study_date_utils.dart';

class FocusTimerService {
  static final FocusTimerService _instance = FocusTimerService._internal();
  factory FocusTimerService() => _instance;
  FocusTimerService._internal();

  bool _isRunning = false;
  String _currentMode = 'study';
  String _currentSubject = '자료해석';
  DateTime? _sessionStart;
  DateTime? _segmentStart;
  int _totalStudyMin = 0;
  int _totalLectureMin = 0;
  int _totalRestMin = 0;
  final List<FocusSegment> _segments = [];

  /// [Bug #2 Fix] 모드 전환 시 누적된 활성(순공+강의) 초 보존
  int _accumulatedActiveSec = 0;

  bool get isRunning => _isRunning;
  String get currentMode => _currentMode;
  String get currentSubject => _currentSubject;

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
  }

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

    await _recordStudyStartIfFirst();
    await FlutterForegroundTask.startService(
      notificationTitle: _notifTitle(),
      notificationText: '시작됨',
      callback: _focusCallback,
    );
    _startLiveSync();
    await _saveState();
  }

  Future<void> switchMode(String newMode) async {
    if (_currentMode == newMode) return;

    final prevMode = _currentMode;
    final segSec = _segmentStart != null
        ? DateTime.now().difference(_segmentStart!).inSeconds
        : 0;

    // [Bug #2 Fix] 활성 모드에서 나갈 때 누적 초 보존
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
  }

  Future<void> changeSubject(String subject) async {
    // 과목 변경 시에도 활성 시간 누적 보존
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
  }

  Future<FocusCycle> endSession() async {
    _endSegment();
    _isRunning = false;
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

    await _syncToFirebase(cycle);
    // 실시간 동기화 데이터 삭제
    try {
      await FirebaseService().clearLiveFocus(cycle.date);
    } catch (_) {}
    await _clearState();
    return cycle;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('study_start_$dateStr', timeStr);
    }
  }

  Future<void> _syncToFirebase(FocusCycle cycle) async {
    // ★ 10초 미만 세션 무시
    final totalSec = (cycle.studyMin + cycle.lectureMin + cycle.restMin) * 60;
    if (totalSec < 10 && cycle.effectiveMin == 0) {
      debugPrint('[FocusTimer] 10초 미만 세션 무시: ${totalSec}s');
      return;
    }
    final addedMin = cycle.studyMin + cycle.lectureMin;
    try {
      final fb = FirebaseService();

      // 1) study 문서에 focusCycles + studyTimeRecords 저장 (기존 호환)
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

      // 2) Phase C: today 문서의 studyTime 합산
      if (addedMin > 0) {
        try {
          await fb.updateTodayField('studyTime.total', FieldValue.increment(addedMin));
          // 과목별 합산
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
          debugPrint('[FocusTimer] today update fail: $e');
        }
      }

      // 3) Phase C: history에 세션 디테일 추가
      try {
        fb.appendFocusSessionToHistory(cycle.date, {
          'subject': cycle.subject,
          'start': cycle.startTime,
          'end': cycle.endTime ?? DateTime.now().toIso8601String(),
          'minutes': addedMin,
          'effectiveMin': cycle.effectiveMin,
        });
      } catch (_) {}

      print('[FocusTimer] _syncToFirebase OK: ${cycle.date} ${cycle.effectiveMin}min');

      // Creature reward
      if (addedMin > 0) {
        try {
          await CreatureService().addStudyReward(addedMin);
        } catch (_) {}
      }
    } catch (e) {
      print('[FocusTimer] _syncToFirebase FAIL: $e');
    }
  }

  /// [F5] 실시간 진행 동기화 (30초마다 Firebase에 현재 상태 업데이트)
  Timer? _liveSyncTimer;

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
      final dateStr = StudyDateUtils.todayKey(_sessionStart!); // ★ FIX: 4AM 경계 적용
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

  /// [F7] 포커스 기록 삭제 + studyTimeRecord 보정
  Future<void> deleteFocusCycle(String date, String cycleId) async {
    try {
      final fb = FirebaseService();
      final cycles = await fb.getFocusCycles(date);
      final target = cycles.firstWhere((c) => c.id == cycleId,
          orElse: () => FocusCycle(id: '', date: date, startTime: '', subject: ''));

      // cycles에서 제거
      cycles.removeWhere((c) => c.id == cycleId);
      await fb.overwriteFocusCycles(date, cycles);

      // studyTimeRecord 보정 (삭제된 만큼 차감)
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
    } catch (_) {}
  }

  Future<void> _saveState() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('focus_running', _isRunning);
    await p.setString('focus_mode', _currentMode);
    await p.setString('focus_subject', _currentSubject);
    if (_sessionStart != null) {
      await p.setString('focus_session_start', _sessionStart!.toIso8601String());
    }
    if (_segmentStart != null) {
      await p.setString('focus_segment_start', _segmentStart!.toIso8601String());
    }
    await p.setInt('focus_study_min', _totalStudyMin);
    await p.setInt('focus_lecture_min', _totalLectureMin);
    await p.setInt('focus_rest_min', _totalRestMin);
    await p.setInt('focus_accumulated_active_sec', _accumulatedActiveSec);
  }

  Future<bool> restoreState() async {
    final p = await SharedPreferences.getInstance();
    _isRunning = p.getBool('focus_running') ?? false;
    if (!_isRunning) return false;
    _currentMode = p.getString('focus_mode') ?? 'study';
    _currentSubject = p.getString('focus_subject') ?? '자료해석';
    final ss = p.getString('focus_session_start');
    if (ss != null) _sessionStart = DateTime.parse(ss);
    final sg = p.getString('focus_segment_start');
    if (sg != null) _segmentStart = DateTime.parse(sg);
    _totalStudyMin = p.getInt('focus_study_min') ?? 0;
    _totalLectureMin = p.getInt('focus_lecture_min') ?? 0;
    _totalRestMin = p.getInt('focus_rest_min') ?? 0;
    _accumulatedActiveSec = p.getInt('focus_accumulated_active_sec') ?? 0;
    _startLiveSync();
    return true;
  }

  Future<void> _clearState() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [
      'focus_running', 'focus_mode', 'focus_subject',
      'focus_session_start', 'focus_segment_start',
      'focus_study_min', 'focus_lecture_min', 'focus_rest_min',
      'focus_accumulated_active_sec',
    ]) {
      await p.remove(k);
    }
  }

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

    // [Bug #2 Fix] 세션 전체 경과 + 활성 누적 타이머
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
}

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
    // ★ 10초마다 알림 업데이트 (바탕화면 상태 표시용)
    if (_tick % 10 == 0) {
      SharedPreferences.getInstance().then((p) {
        final sm = p.getInt('focus_study_min') ?? 0;
        final lm = p.getInt('focus_lecture_min') ?? 0;
        final mode = p.getString('focus_mode') ?? 'study';
        final subject = p.getString('focus_subject') ?? '';
        final sgStr = p.getString('focus_segment_start');
        final ssStr = p.getString('focus_session_start');
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
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

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

  /// [Bug #2 Fix] 메인 타이머: 활성 누적 시간 (휴식 중에는 휴식 시간)
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