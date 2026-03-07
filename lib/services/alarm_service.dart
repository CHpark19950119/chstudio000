import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import 'telegram_service.dart';
import '../utils/study_date_utils.dart';

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Kotlin AlarmManager + AudioManager Method Channel
  static const _alarmChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/alarm');

  static const int _alarmId = 1001;
  static const int _vibrationNotifId = 1002; // 진동 전용 알림
  static const String _channelId = 'cheonhong_alarm';
  static const String _channelName = '기상 알람';
  static const String _vibChannelId = 'cheonhong_alarm_vib';
  static const String _vibChannelName = '기상 알람 진동';
  bool _initialized = false;

  /// F3: 진동 활성 상태 (NFC로만 해제)
  static bool _vibrationActive = false;
  static bool get isVibrationActive => _vibrationActive;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings,
        onDidReceiveNotificationResponse: _onTapped);

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // F1: 소리+진동 채널 (메인)
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'CHEONHONG STUDIO 기상 알람 (소리+진동)',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList(
              [0, 1000, 500, 1000, 500, 1000, 500, 1000]),
          sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        ),
      );
      // F3: 진동 전용 채널 (소리 없음, 진동만)
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          _vibChannelId,
          _vibChannelName,
          description: '기상 알람 진동 (NFC로만 해제)',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
          vibrationPattern: Int64List.fromList(
              [0, 800, 400, 800, 400, 800]),
        ),
      );
    }
    _initialized = true;
  }

  Future<void> scheduleAlarm(AlarmSettings settings) async {
    // Firebase 저장
    try {
      await FirebaseService().saveAlarmSettings(settings);
    } catch (e) {
      debugPrint('[AlarmService] Firebase save error: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_target_time', settings.targetWakeTime);
    await prefs.setBool('alarm_enabled', settings.enabled);
    await prefs.setBool('alarm_qr_enabled', settings.qrWakeEnabled);
    // F3: NFC 해제 모드 저장
    await prefs.setBool('alarm_nfc_dismiss', true);

    await cancelAlarm();
    if (!settings.enabled) return;

    final parts = settings.targetWakeTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    // ══ Kotlin AlarmManager 우선 사용 ══
    try {
      await _alarmChannel.invokeMethod('scheduleAlarm', {
        'hour': hour,
        'minute': minute,
        'activeDays': settings.activeDays,
        'label': '⏰ NFC 태그를 스캔하여 기상하세요!',
        'maxVolume': true, // F2: 볼륨 MAX 플래그
      });
      debugPrint('[AlarmService] Native alarm scheduled: $hour:$minute');
    } catch (e) {
      debugPrint('[AlarmService] Native alarm failed: $e');
    }

    // Flutter 알림 백업
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      while (!settings.activeDays.contains(scheduled.weekday)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        _alarmId,
        '⏰ 기상 시간!',
        'NFC 태그를 스캔하여 기상을 인증하세요!',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('alarm_sound'),
            enableVibration: true,
            vibrationPattern: Int64List.fromList(
                [0, 1000, 500, 1000, 500, 1000, 500, 1000]),
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            // F3: 소리 끄기 버튼만 표시 (진동은 NFC로만)
            actions: const [
              AndroidNotificationAction('mute_sound', '🔇 소리 끄기',
                  showsUserInterface: false),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      debugPrint('[AlarmService] Flutter schedule error: $e');
    }
  }

  Future<void> cancelAlarm() async {
    await _notifications.cancel(_alarmId);
    await _notifications.cancel(_vibrationNotifId);
    try {
      await _alarmChannel.invokeMethod('cancelAlarm');
    } catch (_) {}
  }

  // ══════════════════════════════════════════
  //  F2: 볼륨 최대화 (알람 트리거 시 호출)
  // ══════════════════════════════════════════

  /// 알람 볼륨 + 미디어 볼륨 MAX 설정
  static Future<void> setVolumeMax() async {
    try {
      await _alarmChannel.invokeMethod('setVolumeMax');
      debugPrint('[AlarmService] 🔊 볼륨 MAX 설정');
    } catch (e) {
      debugPrint('[AlarmService] Volume MAX error: $e');
    }
  }

  /// 볼륨 복원 (원래 수준으로)
  static Future<void> restoreVolume() async {
    try {
      await _alarmChannel.invokeMethod('restoreVolume');
    } catch (_) {}
  }

  // ══════════════════════════════════════════
  //  F3: 진동 제어 (NFC로만 해제)
  // ══════════════════════════════════════════

  /// 진동 시작 (알람 트리거 시) + 애인에게 알람 알림
  static Future<void> startPersistentVibration() async {
    _vibrationActive = true;
    try {
      await _alarmChannel.invokeMethod('startVibration');
      debugPrint('[AlarmService] 📳 반복 진동 시작');
    } catch (e) {
      debugPrint('[AlarmService] Vibration error: $e');
    }
    // 나에게 알람 상태 알림
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    TelegramService().sendToMe('⏰ 알람 울림 $timeStr');
  }

  /// 진동 중지 (NFC 스캔 시에만 호출)
  static Future<void> stopVibrationByNfc() async {
    _vibrationActive = false;
    try {
      // 1순위: ForegroundService 종료 (모든 소리+진동+TTS 한번에 정리)
      await _alarmChannel.invokeMethod('stopAlarmService');
      debugPrint('[AlarmService] 🛑 알람 ForegroundService 종료 (NFC)');
    } catch (_) {}
    try {
      await _alarmChannel.invokeMethod('stopVibration');
      debugPrint('[AlarmService] 📳 NFC로 진동 해제');
    } catch (_) {}
    // 소리도 함께 중지
    await _muteAlarmSound();
    await restoreVolume();
    // 기상 시간 기록
    await _recordWakeTime();
    // 알림 제거
    final n = FlutterLocalNotificationsPlugin();
    await n.cancel(_alarmId);
    await n.cancel(_vibrationNotifId);
  }

  // ══════════════════════════════════════════
  //  1순위: 브리핑 데이터 캐시
  //  알람 설정 시 + 매일 자정에 캐시 갱신
  //  → Kotlin ForegroundService가 읽어서 TTS 브리핑 생성
  // ══════════════════════════════════════════

  /// 브리핑 데이터를 네이티브 SharedPreferences에 캐시
  static Future<void> cacheBriefingData({
    String? examDate,
    String? yesterdayGrade,
    String? yesterdayStudyTime,
    String? weatherDesc,
    String? weatherTemp,
    String? weatherCity,
  }) async {
    try {
      await _alarmChannel.invokeMethod('cacheBriefingData', {
        if (examDate != null) 'exam_date': examDate,
        if (yesterdayGrade != null) 'yesterday_grade': yesterdayGrade,
        if (yesterdayStudyTime != null)
          'yesterday_study_time': yesterdayStudyTime,
        if (weatherDesc != null) 'weather_desc': weatherDesc,
        if (weatherTemp != null) 'weather_temp': weatherTemp,
        if (weatherCity != null) 'weather_city': weatherCity,
      });
      debugPrint('[AlarmService] 📋 브리핑 데이터 캐시 완료');
    } catch (e) {
      debugPrint('[AlarmService] 브리핑 캐시 오류: $e');
    }
  }

  /// OpenAI API 키를 네이티브에 전달 (TTS API용)
  static Future<void> cacheOpenAiKey(String apiKey) async {
    try {
      await _alarmChannel.invokeMethod('cacheOpenAiKey', {'key': apiKey});
    } catch (_) {}
  }

  /// BGM 타입을 네이티브에 전달 (piano, nature, rain, none)
  static Future<void> cacheBgmType(String type) async {
    try {
      await _alarmChannel.invokeMethod('cacheBgmType', {'type': type});
    } catch (_) {}
  }

  /// 알람 ForegroundService 즉시 중지
  static Future<void> stopAlarmForegroundService() async {
    try {
      await _alarmChannel.invokeMethod('stopAlarmService');
      debugPrint('[AlarmService] 🛑 알람 서비스 강제 종료');
    } catch (_) {}
  }

  /// 소리만 끄기 (버튼으로 가능, 진동은 유지)
  static Future<void> _muteAlarmSound() async {
    try {
      await _alarmChannel.invokeMethod('muteAlarmSound');
    } catch (_) {}
    // 소리 채널 알림 제거 후 진동 전용으로 교체
    final n = FlutterLocalNotificationsPlugin();
    await n.cancel(_alarmId);
    if (_vibrationActive) {
      // 진동 전용 알림으로 교체 (ongoing)
      await n.show(
        _vibrationNotifId,
        '📳 NFC를 스캔하여 기상하세요!',
        '진동은 NFC 태그 스캔으로만 해제됩니다',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _vibChannelId,
            _vibChannelName,
            importance: Importance.high,
            priority: Priority.max,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false, // 시스템 진동은 Method Channel로 제어
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    }
  }

  // ─── 배터리 최적화 ───

  static Future<bool> isBatteryOptExempt() async {
    try {
      final result = await _alarmChannel.invokeMethod<bool>('isBatteryOptExempt');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestBatteryOptExemption() async {
    try {
      await _alarmChannel.invokeMethod('requestBatteryOptExemption');
    } catch (_) {}
  }

  static Future<void> openBatterySettings() async {
    try {
      await _alarmChannel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  static Future<bool> canScheduleExactAlarms() async {
    try {
      final result =
          await _alarmChannel.invokeMethod<bool>('canScheduleExactAlarms');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestExactAlarmPermission() async {
    try {
      await _alarmChannel.invokeMethod('requestExactAlarmPermission');
    } catch (_) {}
  }

  // ─── 알림 탭 처리 ───

  static void _onTapped(NotificationResponse response) async {
    if (response.actionId == 'mute_sound') {
      // F3: 소리만 끄기 (진동은 NFC로만)
      await _muteAlarmSound();
      debugPrint('[AlarmService] 🔇 소리 끔 (진동 유지)');
    } else if (response.actionId == 'dismiss') {
      // 레거시 dismiss
      final prefs = await SharedPreferences.getInstance();
      final qrEnabled = prefs.getBool('alarm_qr_enabled') ?? false;
      if (qrEnabled) {
        await prefs.setBool('pending_qr_wake', true);
        await prefs.setString('pending_qr_wake_time',
            DateFormat('HH:mm').format(DateTime.now()));
      } else {
        await _recordWakeTime();
      }
      final n = FlutterLocalNotificationsPlugin();
      await n.cancel(_alarmId);
    } else if (response.actionId == 'snooze') {
      await _snooze();
    }
  }

  static Future<bool> hasPendingQrWake() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pending_qr_wake') ?? false;
  }

  static Future<void> completeQrWake() async {
    await _recordWakeTime();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_qr_wake');
    await prefs.remove('pending_qr_wake_time');
  }

  static Future<void> cancelPendingQrWake() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_qr_wake');
    await prefs.remove('pending_qr_wake_time');
  }

  static Future<void> _recordWakeTime() async {
    final now = DateTime.now();
    final dateStr = StudyDateUtils.todayKey();
    final timeStr = DateFormat('HH:mm').format(now);
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      if (existing?.wake != null) return;
      final record =
          TimeRecord(date: dateStr, wake: timeStr, study: existing?.study);
      await fb.updateTimeRecord(dateStr, record);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wake_$dateStr', timeStr);
      await prefs.setString('pending_wake_sync', dateStr);
    }
  }

  static Future<void> _snooze() async {
    final prefs = await SharedPreferences.getInstance();
    final min = prefs.getInt('snooze_minutes') ?? 5;
    final n = FlutterLocalNotificationsPlugin();
    await n.cancel(_alarmId);
    // 진동도 일시 중지
    try {
      await _alarmChannel.invokeMethod('stopVibration');
    } catch (_) {}
    _vibrationActive = false;

    final t = tz.TZDateTime.now(tz.local).add(Duration(minutes: min));
    await n.zonedSchedule(
      _alarmId,
      '⏰ 스누즈 끝! 진짜 일어나세요!',
      '이미 $min분 지났습니다 · NFC 스캔 필요',
      t,
      const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            category: AndroidNotificationCategory.alarm),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> syncPendingWakeRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final date = prefs.getString('pending_wake_sync');
    if (date == null) return;
    final wake = prefs.getString('wake_$date');
    if (wake == null) return;
    try {
      await FirebaseService()
          .updateTimeRecord(date, TimeRecord(date: date, wake: wake));
      await prefs.remove('pending_wake_sync');
    } catch (_) {}
  }

  Future<String?> getTodayWakeTime() async {
    final dateStr = StudyDateUtils.todayKey();
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('wake_$dateStr');
    if (local != null) return local;
    try {
      final records = await FirebaseService().getTimeRecords();
      return records[dateStr]?.wake;
    } catch (_) {
      return null;
    }
  }
}