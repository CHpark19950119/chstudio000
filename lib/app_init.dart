import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';

import 'services/alarm_service.dart';
import 'services/firebase_service.dart';
import 'services/focus_service.dart';
import 'services/focus_mode_service.dart';
import 'services/local_cache_service.dart';
import 'services/location_service.dart';
import 'services/nfc_service.dart';
import 'services/briefing_service.dart';
import 'services/sleep_service.dart';
import 'services/magnet_service.dart';

class AppInit {
  static Future<void> run() async {
    // ── Phase 0: Locale 초기화 (DateFormat 'ko' 사용 전 필수) ──
    await initializeDateFormatting('ko', null);

    // ── Phase 1: Firebase + LocalCache (필수 선행) ──
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await LocalCacheService().init();

    // ── Phase 1.5: Day Rollover (경량, 블로킹 OK) ──
    try {
      await FirebaseService().checkDayRollover()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AppInit] rollover error: $e');
    }

    // ── Phase 2: 서비스 초기화 (병렬, 개별 try-catch) ──
    await Future.wait([
      AlarmService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      FocusService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      FocusModeService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      LocationService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      NfcService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      SleepService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
    ]);

    // ── Phase 3: 상태 복원 (병렬, 개별 try-catch) ──
    await Future.wait([
      FocusService().restoreState().timeout(const Duration(seconds: 8)).catchError((_) {}),
      AlarmService().syncPendingWakeRecords().timeout(const Duration(seconds: 8)).catchError((_) {}),
    ]);

    // ── Phase 4: 백그라운드 서비스 ──
    SleepService().checkAndActivateNightMode();
    MagnetService().init().catchError((_) {});

    // ── Phase 5: 마이그레이션 + 진단 (비블로킹) ──
    Future(() async {
      try {
        await FirebaseService().migrateToTodayHistory()
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        debugPrint('[AppInit] migration error: $e');
      }
      try {
        await FirebaseService().diagnosePhaseCData()
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint('[AppInit] diag error: $e');
      }
    });
  }
}