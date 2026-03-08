part of 'nfc_service.dart';

/// TimeRecord helper — copy existing fields, override only specified ones
TimeRecord _withFields(String date, TimeRecord? e, {
  String? wake, String? study, String? studyEnd,
  String? outing, String? returnHome, String? bedTime,
  List<MealEntry>? meals,
  bool clearReturnHome = false,
}) => TimeRecord(
  date: date,
  wake: wake ?? e?.wake,
  study: study ?? e?.study,
  studyEnd: studyEnd ?? e?.studyEnd,
  outing: outing ?? e?.outing,
  returnHome: clearReturnHome ? null : (returnHome ?? e?.returnHome),
  arrival: e?.arrival,
  bedTime: bedTime ?? e?.bedTime,
  mealStart: e?.mealStart,
  mealEnd: e?.mealEnd,
  meals: meals ?? e?.meals,
);

/// ═══════════════════════════════════════════════════════════
/// NFC — Role Action Handlers
/// ═══════════════════════════════════════════════════════════
extension _NfcActionHandlers on NfcService {

  // ── 기상 (wake) ──

  Future<void> _handleWake(String dateStr, String timeStr) async {
    _log('기상 처리 시작: $dateStr $timeStr');

    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final e = records[dateStr];
      if (e?.wake != null) {
        _emitAction('wake_already', '🚿', '이미 기상 기록됨 (${e!.wake})');
        return;
      }
      await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, wake: timeStr));
      await _notifyNativeResult(title: '기상 인증', body: '기상시간 $timeStr 기록 완료');
      _sendNfc('⏰ 기상 $timeStr (집)');
      _isOut = false; _isStudying = false; _isMealing = false;
      await _saveToggleState();
      _emitAction('wake', '🚿', '기상시간 $timeStr 기록');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_qr_wake');
      await prefs.remove('pending_qr_wake_time');
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Wake 에러: $e');
      await _notifyNativeResult(title: 'NFC 처리 실패', body: '기상 기록 실패');
    }
  }

  // ── 외출/귀가 토글 (outing) ──

  Future<void> _handleOutingToggle(String dateStr, String timeStr) async {
    _log('외출 토글: isOut=$_isOut → ${!_isOut}');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final e = records[dateStr];

      if (!_isOut) {
        _isOut = true;
        await fb.updateTimeRecord(dateStr,
            _withFields(dateStr, e, outing: timeStr, clearReturnHome: true));
        // GPS one-shot
        String locStr = '';
        try {
          final pos = await LocationService().getCurrentPosition();
          if (pos != null) locStr = ' (${LocationService.formatPosition(pos)})';
        } catch (_) {}
        await _notifyNativeResult(title: 'NFC 처리 완료', body: '외출 시작 $timeStr');
        _sendNfc('🚶 외출 $timeStr$locStr');
        _emitAction('outing_start', '🚪', '외출 $timeStr$locStr');
      } else {
        _isOut = false;
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, returnHome: timeStr));
        String durMsg = '';
        if (e?.outing != null) {
          final outMin = _timeDiffMin(e!.outing!, timeStr);
          if (outMin > 0) durMsg = ' (외출 ${_formatMin(outMin)})';
        }
        await _notifyNativeResult(title: 'NFC 처리 완료', body: '귀가 $timeStr$durMsg');
        _sendNfc('🏠 귀가 $timeStr$durMsg');
        _emitAction('outing_end', '🏠', '귀가 $timeStr$durMsg');
      }
      await _saveToggleState();
    } catch (e) {
      _log('Outing 에러: $e');
      await _notifyNativeResult(title: 'NFC 처리 실패', body: '외출 토글 실패');
    }
  }

  // ── 공부 시작 / 재개 / 종료 (study) ──

  Future<void> _handleStudyToggle(String dateStr, String timeStr) async {
    _log('공부 토글: isStudying=$_isStudying, isMealing=$_isMealing, isOut=$_isOut');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final e = records[dateStr];

      // Case 1: 식사 중 → 공부 재개 (식사 종료 + 공부 복귀)
      if (_isMealing) {
        _isMealing = false;
        _isStudying = true;
        _wasStudyingBeforeMeal = false;
        final meals = List<MealEntry>.from(e?.meals ?? []);
        final openIdx = meals.lastIndexWhere((m) => m.end == null);
        int mealMin = 0;
        if (openIdx >= 0) {
          meals[openIdx] = meals[openIdx].withEnd(timeStr);
          mealMin = meals[openIdx].durationMin ?? 0;
        }
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, meals: meals));
        final durMsg = mealMin > 0 ? '식사 ${_formatMin(mealMin)}' : '식사';
        await _notifyNativeResult(title: '공부 재개', body: '식사 종료 → 공부 복귀 ($durMsg)');
        _sendNfc('📚 공부 재개 $timeStr ($durMsg)');
        _emitAction('study_resume', '📚', '공부 재개 ($durMsg)');
        await _saveToggleState();
        _triggerWidgetUpdate();
        return;
      }

      // Case 2: 외출 중 → 공부 재개 (외출 종료 + 공부 복귀)
      if (_isOut) {
        _isOut = false;
        _isStudying = true;
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, returnHome: timeStr));
        String durMsg = '외출';
        if (e?.outing != null) {
          final outMin = _timeDiffMin(e!.outing!, timeStr);
          if (outMin > 0) durMsg = '외출 ${_formatMin(outMin)}';
        }
        await _notifyNativeResult(title: '공부 재개', body: '귀가 → 공부 복귀 ($durMsg)');
        _sendNfc('📚 공부 재개 $timeStr ($durMsg)');
        _emitAction('study_resume', '📚', '공부 재개 ($durMsg)');
        await _saveToggleState();
        _triggerWidgetUpdate();
        return;
      }

      // Case 3: 공부 중 → 종료
      if (_isStudying) {
        _isStudying = false;
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, studyEnd: timeStr));
        String durMsg = '';
        if (e?.study != null) {
          final netMin = _calcNetStudyMin(e!, timeStr);
          if (netMin > 0) durMsg = ' (순공 ${_formatMin(netMin)})';
        }
        await _notifyNativeResult(title: '공부 종료', body: '공부 종료 $timeStr$durMsg');
        _sendNfc('📚 공부 종료 $timeStr$durMsg');
        _emitAction('study_end', '📚', '공부종료 $timeStr$durMsg');
        await _saveToggleState();
        return;
      }

      // Case 4: idle → 새 공부 시작
      _isStudying = true;
      final tagPlace = _findTagPlaceName(NfcTagRole.study);
      await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, study: timeStr));
      final placeMsg = tagPlace != null ? ' ($tagPlace)' : '';
      await _notifyNativeResult(title: '공부 시작', body: '공부 시작 $timeStr$placeMsg');
      _sendNfc('📚 공부 시작 $timeStr$placeMsg');
      _emitAction('study_start', '📚', '공부시작 $timeStr$placeMsg');
      _triggerWidgetUpdate();
      await _saveToggleState();
    } catch (e) {
      _log('Study 에러: $e');
      await _notifyNativeResult(title: 'NFC 처리 실패', body: '공부 토글 실패');
    }
  }

  // ── 수면시작 (sleep) ──

  Future<void> _handleSleep(String dateStr, String timeStr) async {
    _log('수면시작 처리: $dateStr $timeStr');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();

      // UL-2: 오전 4시~7시 → 전날 bedTime 없으면 전날로 귀속
      final now = DateTime.now();
      if (now.hour >= 4 && now.hour < 7) {
        final yesterday = DateFormat('yyyy-MM-dd').format(
            now.subtract(const Duration(days: 1)));
        if (records[yesterday]?.bedTime == null) {
          _log('UL-2: 전날($yesterday) bedTime 미기록 → 전날로 귀속');
          dateStr = yesterday;
        }
      }

      final e = records[dateStr];

      // 열린 식사 닫기
      final meals = List<MealEntry>.from(e?.meals ?? []);
      if (_isMealing) {
        _isMealing = false;
        final openIdx = meals.lastIndexWhere((m) => m.end == null);
        if (openIdx >= 0) meals[openIdx] = meals[openIdx].withEnd(timeStr);
      }

      // 공부 중이면 종료
      String? finalStudyEnd;
      if (_isStudying) {
        _isStudying = false;
        if (e?.study != null && e?.studyEnd == null) {
          finalStudyEnd = timeStr;
        }
      }

      await fb.updateTimeRecord(dateStr, _withFields(dateStr, e,
          studyEnd: finalStudyEnd, bedTime: timeStr, meals: meals));
      await _saveToggleState();

      // 오늘 순공시간 계산
      String netMsg = '';
      final studyStart = e?.study;
      final studyEndFinal = finalStudyEnd ?? e?.studyEnd;
      if (studyStart != null && studyEndFinal != null) {
        final totalMin = _timeDiffMin(studyStart, studyEndFinal);
        int mealMin = 0;
        for (final m in meals) {
          if (m.durationMin != null) mealMin += m.durationMin!;
        }
        final netMin = (totalMin - mealMin).clamp(0, 1440);
        if (netMin > 0) netMsg = ' (오늘 순공 ${_formatMin(netMin)})';
      }

      await _notifyNativeResult(title: '수면시작', body: '취침 $timeStr$netMsg — 좋은 밤 되세요');
      _sendNfc('😴 취침 $timeStr$netMsg');
      _emitAction('sleep', '🛏️', '취침시간 $timeStr$netMsg');
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Sleep 에러: $e');
      await _notifyNativeResult(title: 'NFC 처리 실패', body: '수면 기록 실패');
    }
  }

  // ── 식사 토글 (meal) ──

  Future<void> _handleMealToggle(String dateStr, String timeStr) async {
    _log('식사 토글: isMealing=$_isMealing → ${!_isMealing}');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final e = records[dateStr];
      final meals = List<MealEntry>.from(e?.meals ?? []);

      if (!_isMealing) {
        _wasStudyingBeforeMeal = _isStudying;
        _isMealing = true;
        meals.add(MealEntry(start: timeStr));
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, meals: meals));
        // GPS one-shot
        String locStr = '';
        try {
          final pos = await LocationService().getCurrentPosition();
          if (pos != null) locStr = ' (${LocationService.formatPosition(pos)})';
        } catch (_) {}
        await _notifyNativeResult(
            title: '식사 시작', body: '식사 시작 $timeStr (${meals.length}번째)');
        _sendNfc('🍽 식사 시작 $timeStr$locStr');
        _emitAction('meal_start', '🍽️', '식사 시작 $timeStr');
      } else {
        _isMealing = false;
        final openIdx = meals.lastIndexWhere((m) => m.end == null);
        if (openIdx >= 0) meals[openIdx] = meals[openIdx].withEnd(timeStr);
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, meals: meals));
        final lastMeal = openIdx >= 0 ? meals[openIdx] : null;
        final durMsg = lastMeal?.durationFormatted != null
            ? ' (${lastMeal!.durationFormatted})' : '';

        if (_wasStudyingBeforeMeal) {
          _isStudying = true;
          _wasStudyingBeforeMeal = false;
          await _notifyNativeResult(title: '식사 종료 → 공부 복귀',
              body: '식사 종료 $timeStr$durMsg — 공부 모드로 복귀합니다');
          _sendNfc('📚 공부 재개 $timeStr$durMsg');
          _emitAction('meal_end_study_resume', '📚', '식사 종료$durMsg → 공부 복귀');
        } else {
          await _notifyNativeResult(title: '식사 종료', body: '식사 종료 $timeStr$durMsg');
          _sendNfc('🍽 식사 종료 $timeStr$durMsg');
          _emitAction('meal_end', '🍽️', '식사 종료 $timeStr$durMsg');
        }
      }
      await _saveToggleState();
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Meal 에러: $e');
      await _notifyNativeResult(title: 'NFC 처리 실패', body: '식사 기록 실패');
    }
  }

  // ── Utilities ──

  void _triggerWidgetUpdate() {
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('widget_needs_update', true);
      } catch (_) {}
    });
  }

  void _sendNfc(String message) {
    TelegramService().sendNfc(message);
  }

  Future<void> _notifyNativeResult({required String title, required String body}) async {
    try {
      await _nfcChannel.invokeMethod('showNotification', {
        'title': title, 'body': body,
      });
      _log('알림 표시: $title — $body');
    } catch (e) {
      _log('알림 표시 실패: $e');
    }
  }

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notifPermissionRequested) return;
    _notifPermissionRequested = true;
    try {
      await _nfcChannel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      _log('알림 권한 요청 실패: $e');
    }
  }

  /// 시간 문자열 차이 (분)
  int _timeDiffMin(String start, String end) {
    final sParts = start.split(':');
    final eParts = end.split(':');
    final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
    var eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
    if (eMin < sMin) eMin += 1440;
    return eMin - sMin;
  }

  /// 분 → "Xh Xm" 또는 "Xm" 포맷
  String _formatMin(int min) {
    if (min >= 60) return '${min ~/ 60}h ${min % 60}m';
    return '${min}m';
  }

  /// 순공시간 계산: (studyEnd - study) - 총 식사시간
  int _calcNetStudyMin(TimeRecord tr, String endTime) {
    if (tr.study == null) return 0;
    final totalMin = _timeDiffMin(tr.study!, endTime);
    int mealMin = 0;
    for (final m in tr.meals) {
      if (m.durationMin != null) mealMin += m.durationMin!;
    }
    return (totalMin - mealMin).clamp(0, 1440);
  }

  /// study 역할 태그의 placeName 조회
  String? _findTagPlaceName(NfcTagRole role) {
    for (final t in _tags) {
      if (t.role == role && t.placeName != null) return t.placeName;
    }
    return null;
  }
}
