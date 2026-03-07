import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import '../utils/study_date_utils.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 수면 관리 서비스 (P5: #32~38)
/// ═══════════════════════════════════════════════════════════
///
/// #32: 취침 목표 설정 + 알림 시퀀스
/// #33: 야간 앱 잠금 (Method Channel → Kotlin)
/// #34: 수면 중 화면 켜짐 감지 (Method Channel → Kotlin)
/// #35: 수면 스코어 (SleepGrade 모델 연산)
/// #36: Tasker Intent 연동
/// #37: 야간 그레이스케일 (Tasker 트리거)
/// #38: 야간 네트워크 차단 (Tasker 트리거)
class SleepService {
  static final SleepService _instance = SleepService._internal();
  factory SleepService() => _instance;
  SleepService._internal();

  // ── Kotlin Method Channels ──
  static const _sleepChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/sleep');
  static const _taskerChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/tasker');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const int _warningNotifId = 2001;
  static const int _bedtimeNotifId = 2002;
  static const int _lockNotifId = 2003;
  static const String _channelId = 'cheonhong_sleep';
  static const String _channelName = '수면 관리';

  bool _initialized = false;
  bool _nightModeActive = false;
  bool _screenMonitoring = false;
  Timer? _midnightTimer;
  SleepSettings _settings = SleepSettings();

  bool get isNightModeActive => _nightModeActive;
  bool get isScreenMonitoring => _screenMonitoring;
  SleepSettings get settings => _settings;

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;

    // 알림 채널 생성
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'CHEONHONG STUDIO 수면 관리 알림',
          importance: Importance.high,
          playSound: true,
        ),
      );
    }

    // Firebase에서 설정 로드
    try {
      _settings = await FirebaseService().getSleepSettings();
    } catch (_) {}

    // 이전 야간모드 상태 복원
    await _restoreNightMode();

    _initialized = true;
  }

  // ═══════════════════════════════════════════
  //  #32: 취침 목표 설정 + 알림 시퀀스
  // ═══════════════════════════════════════════

  /// 수면 설정 저장 + 알림 스케줄링
  Future<void> updateSettings(SleepSettings newSettings) async {
    _settings = newSettings;

    // Firebase 저장
    try {
      await FirebaseService().saveSleepSettings(newSettings);
    } catch (e) {
      debugPrint('[SleepService] Firebase save error: $e');
    }

    // 로컬 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sleep_target_bed', newSettings.targetBedTime);
    await prefs.setBool('sleep_enabled', newSettings.enabled);
    await prefs.setBool('sleep_app_lock', newSettings.appLockEnabled);
    await prefs.setBool('sleep_screen_monitor', newSettings.screenMonitor);

    // 알림 다시 스케줄
    await cancelAllNotifications();
    if (newSettings.enabled) {
      await scheduleBedtimeAlerts(newSettings);
    }
  }

  /// 취침 알림 시퀀스 스케줄링
  /// 1) 경고 알림: targetBedTime - warningMinBefore
  /// 2) 취침 알림: targetBedTime
  /// 3) 잠금 알림: 00:00 (자정)
  Future<void> scheduleBedtimeAlerts(SleepSettings settings) async {
    final parts = settings.targetBedTime.split(':');
    final bedH = int.parse(parts[0]);
    final bedM = int.parse(parts[1]);
    final now = tz.TZDateTime.now(tz.local);

    // 1. 취침 경고 (30분 전)
    var warningTime = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, bedH, bedM)
      ..subtract(Duration(minutes: settings.warningMinBefore));
    final warnH = bedH;
    final warnM = bedM - settings.warningMinBefore;
    var warnDt = tz.TZDateTime(tz.local, now.year, now.month, now.day,
        warnM < 0 ? warnH - 1 : warnH, warnM < 0 ? warnM + 60 : warnM);
    if (warnDt.isBefore(now)) warnDt = warnDt.add(const Duration(days: 1));

    await _notifications.zonedSchedule(
      _warningNotifId,
      '🌙 취침 ${settings.warningMinBefore}분 전',
      '곧 취침 시간입니다. 마무리 준비를 시작하세요.',
      warnDt,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 2. 취침 알림
    var bedDt = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, bedH, bedM);
    if (bedDt.isBefore(now)) bedDt = bedDt.add(const Duration(days: 1));

    await _notifications.zonedSchedule(
      _bedtimeNotifId,
      '😴 취침 시간!',
      '목표 취침 ${settings.targetBedTime}. 폰을 내려놓으세요.',
      bedDt,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          ongoing: true,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 3. 자정 잠금 알림 (appLock 활성 시)
    if (settings.appLockEnabled) {
      var lockDt = tz.TZDateTime(
          tz.local, now.year, now.month, now.day + 1, 0, 0);
      if (lockDt.isBefore(now)) lockDt = lockDt.add(const Duration(days: 1));

      await _notifications.zonedSchedule(
        _lockNotifId,
        '🔒 야간 앱 잠금 활성화',
        'SNS/영상 앱이 차단됩니다. 전화·문자·카톡통화는 허용.',
        lockDt,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancel(_warningNotifId);
    await _notifications.cancel(_bedtimeNotifId);
    await _notifications.cancel(_lockNotifId);
  }

  // ═══════════════════════════════════════════
  //  #33: 야간 앱 잠금
  // ═══════════════════════════════════════════

  /// 야간 모드 수동 활성화/비활성화
  Future<void> activateNightMode() async {
    _nightModeActive = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night_mode_active', true);
    await prefs.setString('night_mode_activated_at',
        DateFormat('HH:mm').format(DateTime.now()));

    // Kotlin 쪽 야간 앱 잠금 활성화
    try {
      await _sleepChannel.invokeMethod('activateNightLock', {
        'allowedApps': _settings.allowedApps,
      });
    } catch (e) {
      debugPrint('[SleepService] Night lock activate error: $e');
    }

    // #37: 그레이스케일 활성화
    await _enableGrayscale();
  }

  Future<void> deactivateNightMode() async {
    _nightModeActive = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night_mode_active', false);

    try {
      await _sleepChannel.invokeMethod('deactivateNightLock');
    } catch (e) {
      debugPrint('[SleepService] Night lock deactivate error: $e');
    }

    // #37: 그레이스케일 비활성화
    await _disableGrayscale();
  }

  /// 야간 모드 자동 체크 (매분 호출 또는 타이머)
  Future<void> checkAndActivateNightMode() async {
    if (!_settings.enabled || !_settings.appLockEnabled) return;

    final now = DateTime.now();
    final h = now.hour;

    // 00:00 ~ 05:30 → 야간 모드 활성화
    if ((h >= 0 && h < 5) || (h == 5 && now.minute <= 30)) {
      if (!_nightModeActive) {
        await activateNightMode();
      }
    } else {
      if (_nightModeActive) {
        await deactivateNightMode();
      }
    }
  }

  // ═══════════════════════════════════════════
  //  N5+N6: NFC 침대 태그 → 수면모드 진입
  // ═══════════════════════════════════════════

  /// NFC sleep 태그로 호출됨
  /// 1) bedTime 기록
  /// 2) 야간 모드 활성화 (앱 잠금 + 그레이스케일)
  /// 3) 하루 기록 "종료" 마킹 (N6: 12시 초기화 대신 수면 기준)
  Future<void> enterSleepMode(String dateStr, String timeStr) async {
    debugPrint('[SleepService] 🛏️ NFC 수면모드 진입: $dateStr $timeStr');

    // 1) bedTime 기록
    try {
      final existing = await FirebaseService().getSleepRecord(dateStr);
      final record = SleepRecord(
        date: dateStr,
        bedTime: timeStr,
        wakeTime: existing?.wakeTime,
        sleepMinutes: existing?.sleepMinutes,
        screenOnCount: existing?.screenOnCount ?? 0,
        screenOnMinutes: existing?.screenOnMinutes ?? 0,
      );
      await FirebaseService().saveSleepRecord(dateStr, record);
      debugPrint('[SleepService] ✅ bedTime 기록: $timeStr');
    } catch (e) {
      debugPrint('[SleepService] ⚠️ bedTime 기록 실패: $e');
      // 로컬 폴백
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sleep_bed_$dateStr', timeStr);
    }

    // 2) 야간 모드 활성화
    await activateNightMode();

    // 3) 하루 종료 마킹 (N6)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('day_ended_at', '$dateStr $timeStr');
    await prefs.setString('day_ended_date', dateStr);
    debugPrint('[SleepService] ✅ 하루 기록 종료 마킹: $dateStr $timeStr');

    // 4) 화면 모니터링 시작
    await startScreenMonitoring();
  }

  /// N6: 수면모드 기준으로 하루가 종료되었는지 확인
  Future<bool> isDayEndedBySleep(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final endedDate = prefs.getString('day_ended_date');
    return endedDate == dateStr;
  }

  /// N6: 기상 시 새 하루 시작 (수면모드 해제 + 하루 종료 마킹 초기화)
  Future<void> startNewDay() async {
    await deactivateNightMode();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('day_ended_at');
    await prefs.remove('day_ended_date');
    debugPrint('[SleepService] ✅ 새 하루 시작 — 수면모드 해제');
  }

  Future<void> _restoreNightMode() async {
    final prefs = await SharedPreferences.getInstance();
    final wasActive = prefs.getBool('night_mode_active') ?? false;
    if (wasActive) {
      await checkAndActivateNightMode();
    }
  }

  // ═══════════════════════════════════════════
  //  #34: 수면 중 화면 켜짐 감지
  // ═══════════════════════════════════════════

  /// 화면 모니터링 시작 (취침 기록 시)
  Future<void> startScreenMonitoring() async {
    if (!_settings.screenMonitor) return;
    _screenMonitoring = true;

    try {
      await _sleepChannel.invokeMethod('startScreenMonitor');
      debugPrint('[SleepService] Screen monitoring started');
    } catch (e) {
      debugPrint('[SleepService] Screen monitor start error: $e');
    }
  }

  /// 화면 모니터링 중지 + 결과 가져오기
  Future<({int count, int minutes})> stopScreenMonitoring() async {
    _screenMonitoring = false;

    try {
      final result = await _sleepChannel
          .invokeMethod<Map>('stopScreenMonitor');
      if (result != null) {
        return (
          count: (result['screenOnCount'] ?? 0) as int,
          minutes: (result['screenOnMinutes'] ?? 0) as int,
        );
      }
    } catch (e) {
      debugPrint('[SleepService] Screen monitor stop error: $e');
    }
    return (count: 0, minutes: 0);
  }

  /// 현재 모니터링 통계 가져오기
  Future<({int count, int minutes})> getScreenMonitorStats() async {
    try {
      final result = await _sleepChannel
          .invokeMethod<Map>('getScreenMonitorStats');
      if (result != null) {
        return (
          count: (result['screenOnCount'] ?? 0) as int,
          minutes: (result['screenOnMinutes'] ?? 0) as int,
        );
      }
    } catch (e) {}
    return (count: 0, minutes: 0);
  }

  // ═══════════════════════════════════════════
  //  #35: 수면 스코어 계산
  // ═══════════════════════════════════════════

  /// 수면 기록 저장 (취침 시)
  Future<void> recordBedTime() async {
    final now = DateTime.now();
    final date = StudyDateUtils.todayKey();
    final timeStr = DateFormat('HH:mm').format(now);

    try {
      final existing = await FirebaseService().getSleepRecord(date);
      final record = SleepRecord(
        date: date,
        bedTime: timeStr,
        wakeTime: existing?.wakeTime,
        sleepMinutes: existing?.sleepMinutes,
        screenOnCount: existing?.screenOnCount ?? 0,
        screenOnMinutes: existing?.screenOnMinutes ?? 0,
      );
      await FirebaseService().saveSleepRecord(date, record);
    } catch (e) {
      // 로컬 폴백
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sleep_bed_$date', timeStr);
    }

    // 화면 모니터링 시작
    await startScreenMonitoring();
  }

  /// 기상 시 수면 기록 완성
  Future<SleepGrade?> completeWakeRecord(String wakeTime) async {
    final todayDt = StudyDateUtils.effectiveDate();
    final date = DateFormat('yyyy-MM-dd')
        .format(todayDt.subtract(const Duration(days: 1)));
    final today = StudyDateUtils.todayKey();

    // 화면 모니터링 중지
    final screenStats = await stopScreenMonitoring();

    // 어제 또는 오늘 수면기록 찾기
    SleepRecord? existing;
    String recordDate = date;
    try {
      existing = await FirebaseService().getSleepRecord(date);
      existing ??= await FirebaseService().getSleepRecord(today);
      if (existing != null && existing.date == today) recordDate = today;
    } catch (_) {}

    // 수면시간 계산
    int? sleepMinutes;
    if (existing?.bedTime != null) {
      sleepMinutes = _calcSleepMinutes(existing!.bedTime!, wakeTime);
    }

    final record = SleepRecord(
      date: recordDate,
      bedTime: existing?.bedTime,
      wakeTime: wakeTime,
      sleepMinutes: sleepMinutes,
      screenOnCount: screenStats.count,
      screenOnMinutes: screenStats.minutes,
    );

    try {
      await FirebaseService().saveSleepRecord(recordDate, record);
    } catch (_) {}

    // 수면 스코어 계산
    final alarmSettings = await FirebaseService().getAlarmSettings();
    return SleepGrade.calculate(
      date: recordDate,
      settings: _settings,
      record: record,
      targetWakeTime: alarmSettings.targetWakeTime,
    );
  }

  /// 수면시간 계산 (bedTime, wakeTime → 분)
  int _calcSleepMinutes(String bedTime, String wakeTime) {
    try {
      final bp = bedTime.split(':');
      final wp = wakeTime.split(':');
      int bedMin = int.parse(bp[0]) * 60 + int.parse(bp[1]);
      int wakeMin = int.parse(wp[0]) * 60 + int.parse(wp[1]);

      // 자정 넘어간 경우: bedTime이 더 크면 (예: 23:30 → 07:00)
      if (bedMin > wakeMin) {
        return (1440 - bedMin) + wakeMin;
      }
      return wakeMin - bedMin;
    } catch (_) {
      return 0;
    }
  }

  /// 특정 날짜 수면 스코어 가져오기
  Future<SleepGrade?> getSleepGrade(String date) async {
    try {
      final record = await FirebaseService().getSleepRecord(date);
      if (record == null) return null;
      final alarmSettings = await FirebaseService().getAlarmSettings();
      return SleepGrade.calculate(
        date: date,
        settings: _settings,
        record: record,
        targetWakeTime: alarmSettings.targetWakeTime,
      );
    } catch (_) {
      return null;
    }
  }

  /// 최근 N일 수면 기록 가져오기
  Future<List<({SleepRecord record, SleepGrade grade})>>
      getRecentSleepHistory(int days) async {
    final results = <({SleepRecord record, SleepGrade grade})>[];
    final now = DateTime.now();
    final alarmSettings = await FirebaseService().getAlarmSettings();

    for (int i = 0; i < days; i++) {
      final date = DateFormat('yyyy-MM-dd')
          .format(now.subtract(Duration(days: i)));
      try {
        final record = await FirebaseService().getSleepRecord(date);
        if (record != null) {
          final grade = SleepGrade.calculate(
            date: date,
            settings: _settings,
            record: record,
            targetWakeTime: alarmSettings.targetWakeTime,
          );
          results.add((record: record, grade: grade));
        }
      } catch (_) {}
    }
    return results;
  }

  // ═══════════════════════════════════════════
  //  #36: Tasker Intent 연동
  // ═══════════════════════════════════════════

  /// Tasker에 Intent 브로드캐스트
  Future<void> sendTaskerIntent(String action, {Map<String, String>? extras}) async {
    try {
      await _taskerChannel.invokeMethod('sendIntent', {
        'action': action,
        'extras': extras ?? {},
      });
      debugPrint('[SleepService] Tasker intent sent: $action');
    } catch (e) {
      debugPrint('[SleepService] Tasker intent error: $e');
    }
  }

  /// Tasker 이벤트 수신 등록
  Future<void> registerTaskerReceiver() async {
    try {
      _taskerChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onTaskerEvent':
            final action = call.arguments['action'] as String?;
            debugPrint('[SleepService] Tasker event received: $action');
            await _handleTaskerEvent(action);
            break;
        }
      });
      await _taskerChannel.invokeMethod('registerReceiver');
    } catch (e) {
      debugPrint('[SleepService] Tasker register error: $e');
    }
  }

  Future<void> _handleTaskerEvent(String? action) async {
    switch (action) {
      case 'com.cheonhong.BEDTIME':
        await recordBedTime();
        break;
      case 'com.cheonhong.WAKE':
        final time = DateFormat('HH:mm').format(DateTime.now());
        await completeWakeRecord(time);
        break;
      case 'com.cheonhong.NIGHT_MODE_ON':
        await activateNightMode();
        break;
      case 'com.cheonhong.NIGHT_MODE_OFF':
        await deactivateNightMode();
        break;
    }
  }

  // ═══════════════════════════════════════════
  //  #37: 야간 그레이스케일
  // ═══════════════════════════════════════════

  Future<void> _enableGrayscale() async {
    // Tasker 연동: 그레이스케일 ON
    await sendTaskerIntent('com.cheonhong.GRAYSCALE_ON');
    // Kotlin fallback: 직접 설정 변경 (root/ADB 권한 필요)
    try {
      await _sleepChannel.invokeMethod('enableGrayscale');
    } catch (_) {}
  }

  Future<void> _disableGrayscale() async {
    await sendTaskerIntent('com.cheonhong.GRAYSCALE_OFF');
    try {
      await _sleepChannel.invokeMethod('disableGrayscale');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  #38: 야간 네트워크 차단
  // ═══════════════════════════════════════════

  Future<void> enableNetworkBlock() async {
    await sendTaskerIntent('com.cheonhong.NETWORK_OFF');
    try {
      await _sleepChannel.invokeMethod('enableNetworkBlock');
    } catch (_) {}
  }

  Future<void> disableNetworkBlock() async {
    await sendTaskerIntent('com.cheonhong.NETWORK_ON');
    try {
      await _sleepChannel.invokeMethod('disableNetworkBlock');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  유틸리티
  // ═══════════════════════════════════════════

  /// 수면 등급별 이모지
  static String gradeEmoji(String grade) {
    switch (grade) {
      case 'S+': return '🌙✨';
      case 'S': return '🌙';
      case 'A': return '😴';
      case 'B': return '💤';
      case 'C': return '😪';
      case 'D': return '🫠';
      default: return '💀';
    }
  }

  /// 수면 시간 → 상태 텍스트
  static String sleepQualityLabel(int? minutes) {
    if (minutes == null) return '기록 없음';
    if (minutes >= 420 && minutes <= 480) return '최적 (7~8h)';
    if (minutes >= 360 && minutes < 420) return '약간 부족';
    if (minutes > 480 && minutes <= 540) return '약간 과다';
    if (minutes < 360) return '수면 부족';
    return '과다 수면';
  }
}