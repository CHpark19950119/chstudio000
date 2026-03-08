import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';

import 'services/firebase_service.dart';
import 'services/focus_service.dart';
import 'services/local_cache_service.dart';
import 'services/nfc_service.dart';
import 'services/cradle_service.dart';

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
      FocusService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      NfcService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
    ]);

    // ── Phase 3: 상태 복원 (병렬, 개별 try-catch) ──
    await Future.wait([
      FocusService().restoreState().timeout(const Duration(seconds: 8)).catchError((_) {}),
    ]);

    // ── Phase 4: 거치대 서비스 ──
    CradleService().init().catchError((_) {});
  }
}
