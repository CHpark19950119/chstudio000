import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'firebase_service.dart';

class FocusModeService {
  static final FocusModeService _instance = FocusModeService._internal();
  factory FocusModeService() => _instance;
  FocusModeService._internal();

  static const _focusChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');
  static const _usageChannel =
      MethodChannel('com.cheonhong.cheonhong_studio/usage_stats');

  bool _active = false;
  Timer? _monitorTimer;
  FocusModeConfig _config = FocusModeConfig();

  /// 기본 차단 앱 목록 (패키지명 키워드)
  static const _defaultBlockedKeywords = [
    'youtube', 'instagram', 'twitter', 'tiktok', 'facebook',
    'reddit', 'discord', 'netflix', 'twitch', 'tving',
    'wavve', 'watcha', 'coupangplay', 'disney',
  ];

  bool get isActive => _active;

  Future<void> initialize() async {
    try {
      _config = await FirebaseService().getFocusModeConfig();
    } catch (_) {
      _config = FocusModeConfig(
        enabled: true,
        blockedPackages: [],
        enableDnd: true,
        showOverlay: true,
      );
    }
  }

  Future<void> requestPermissions() async {
    try {
      final hasPermission = await _usageChannel.invokeMethod<bool>('hasPermission');
      if (hasPermission != true) {
        await _usageChannel.invokeMethod('requestPermission');
      }
    } catch (e) {
      debugPrint('[FocusMode] Permission request error: $e');
    }
  }

  /// [Bug #1] 포커스 세션 시작 시 활성화
  Future<void> activate() async {
    _active = true;

    // DND 모드 활성화
    if (_config.enableDnd) {
      try {
        await _focusChannel.invokeMethod('enableDnd');
      } catch (_) {}
    }

    // 포그라운드 앱 모니터링 시작 (3초 간격)
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkForegroundApp();
    });

    await _saveActiveState(true);
  }

  /// [Bug #1] 포커스 세션 종료 시 비활성화
  Future<void> deactivate() async {
    _active = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;

    // DND 모드 해제
    if (_config.enableDnd) {
      try {
        await _focusChannel.invokeMethod('disableDnd');
      } catch (_) {}
    }

    await _saveActiveState(false);
  }

  /// [Bug #1] 포그라운드 앱 감지 → 차단 앱이면 경고
  Future<void> _checkForegroundApp() async {
    if (!_active) return;

    try {
      final foreground = await _focusChannel.invokeMethod<String>('getForegroundApp');
      if (foreground == null) return;

      // 자기 앱인지 확인
      if (foreground.contains('cheonhong')) return;

      // 차단 앱 목록 체크
      final blocked = _isBlockedApp(foreground);
      if (blocked) {
        debugPrint('[FocusMode] Blocked app detected: $foreground');
        // 오버레이 경고 표시
        if (_config.showOverlay) {
          try {
            await _focusChannel.invokeMethod('showBlockOverlay');
          } catch (_) {}
        }
        // 경고 횟수 기록 (통계용)
        await _recordViolation(foreground);
      }
    } catch (e) {
      debugPrint('[FocusMode] Check error: $e');
    }
  }

  bool _isBlockedApp(String packageName) {
    final pkg = packageName.toLowerCase();

    // 사용자 지정 차단 앱 확인
    for (final blocked in _config.blockedPackages) {
      if (pkg.contains(blocked.toLowerCase())) return true;
    }

    // 기본 차단 키워드 확인
    for (final keyword in _defaultBlockedKeywords) {
      if (pkg.contains(keyword)) return true;
    }

    return false;
  }

  Future<void> _recordViolation(String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt('focus_violations_today') ?? 0;
      await prefs.setInt('focus_violations_today', count + 1);
      final violations = prefs.getStringList('focus_violation_apps') ?? [];
      if (!violations.contains(packageName)) {
        violations.add(packageName);
        await prefs.setStringList('focus_violation_apps', violations);
      }
    } catch (_) {}
  }

  Future<void> _saveActiveState(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('focus_mode_active', active);
    } catch (_) {}
  }

  /// 오늘 위반 횟수 조회
  Future<int> getTodayViolations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('focus_violations_today') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 오늘 위반 앱 목록
  Future<List<String>> getTodayViolationApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('focus_violation_apps') ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 일일 위반 기록 리셋
  Future<void> resetDailyViolations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('focus_violations_today', 0);
      await prefs.setStringList('focus_violation_apps', []);
    } catch (_) {}
  }

  /// 오늘 앱 사용 통계 수집 (Kotlin UsageStats)
  Future<List<AppUsageStat>> collectTodayUsageStats() async {
    try {
      final result = await _usageChannel.invokeMethod<List>('getUsageStats');
      if (result == null) return [];

      final stats = <AppUsageStat>[];
      for (final item in result) {
        final map = Map<String, dynamic>.from(item);
        final pkg = (map['packageName'] ?? '') as String;
        final minutes = (map['totalTimeInForeground'] ?? 0) as int;
        if (minutes < 1) continue;

        stats.add(AppUsageStat(
          date: DateTime.now().toIso8601String().substring(0, 10),
          packageName: pkg,
          appName: _extractAppName(pkg),
          usageMinutes: minutes,
          category: _categorize(pkg),
        ));
      }

      stats.sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));
      return stats;
    } catch (e) {
      debugPrint('[FocusMode] collectTodayUsageStats error: $e');
      return [];
    }
  }

  /// Firebase에 오늘 앱 사용 통계 업로드
  Future<void> uploadDailyStats() async {
    try {
      final stats = await collectTodayUsageStats();
      if (stats.isEmpty) return;

      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      await FirebaseService().saveAppUsageStats(dateStr, stats);
    } catch (e) {
      debugPrint('[FocusMode] uploadDailyStats error: $e');
    }
  }

  String _extractAppName(String packageName) {
    final parts = packageName.split('.');
    final last = parts.isNotEmpty ? parts.last : packageName;
    return last[0].toUpperCase() + last.substring(1);
  }

  String _categorize(String pkg) {
    final p = pkg.toLowerCase();
    if (['youtube', 'netflix', 'tving', 'wavve', 'watcha', 'twitch',
         'coupangplay', 'disney', 'vlc', 'mxplayer'].any((k) => p.contains(k))) return 'video';
    if (['instagram', 'twitter', 'facebook', 'tiktok', 'reddit',
         'discord', 'kakao', 'line', 'telegram'].any((k) => p.contains(k))) return 'sns';
    if (['quizlet', 'anki', 'notion', 'evernote', 'study',
         'dictionary', 'acrobat', 'kindle'].any((k) => p.contains(k))) return 'study';
    return 'other';
  }
}

