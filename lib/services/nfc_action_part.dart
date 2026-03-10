part of 'nfc_service.dart';

/// TimeRecord helper — 기존 필드 보존, 지정된 필드만 오버라이드
TimeRecord _withFields(String date, TimeRecord? e, {
  String? wake, String? study, String? studyEnd,
  String? outing, String? returnHome, String? bedTime,
  List<MealEntry>? meals, bool clearReturnHome = false,
}) => TimeRecord(
  date: date,
  wake: wake ?? e?.wake,
  study: study ?? e?.study,
  studyEnd: studyEnd ?? e?.studyEnd,
  outing: outing ?? e?.outing,
  returnHome: clearReturnHome ? null : (returnHome ?? e?.returnHome),
  arrival: e?.arrival,
  bedTime: bedTime ?? e?.bedTime,
  mealStart: e?.mealStart, mealEnd: e?.mealEnd,
  meals: meals ?? e?.meals,
);

/// ═══════════════════════════════════════════════════════════
/// NFC — DayState FSM Handlers (식사 독립 추적)
/// ═══════════════════════════════════════════════════════════
extension _NfcActionHandlers on NfcService {

  // ═══ 기상 (wake) ═══

  Future<void> _handleWake(String dateStr, String timeStr, {bool auto = false}) async {
    if (_state != DayState.idle && _state != DayState.sleeping && !auto) {
      _emitAction('wake_already', '🚿', '이미 기상됨');
      return;
    }
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final e = records[dateStr];
      if (e?.wake != null && !auto) {
        _emitAction('wake_already', '🚿', '이미 기상 (${e!.wake})');
        return;
      }
      await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, wake: timeStr))
          .timeout(const Duration(seconds: 5));

      _state = DayState.awake;
      await _saveState();
      _startWakeReminder();

      final tgTime = DateFormat('HH:mm').format(DateTime.now());
      if (!auto) {
        _sendNfc('⏰ 기상 $tgTime');
        _notifyNative(title: '기상 인증', body: '기상 $tgTime');
        _emitAction('wake', '🚿', '기상 $tgTime');
      } else {
        _sendNfc('⏰ 자동 기상 $tgTime');
        _emitAction('wake_auto', '🚿', '자동 기상');
      }
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Wake 에러: $e');
    }
  }

  // ═══ 외출/귀가 (outing) ═══

  Future<void> _handleOuting(String dateStr, String timeStr) async {
    _log('외출: state=${_state.name}');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final e = records[dateStr];
      final tgTime = DateFormat('HH:mm').format(DateTime.now());

      if (_state == DayState.outing) {
        // ── 귀가 ──
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, returnHome: timeStr))
            .timeout(const Duration(seconds: 5));
        String dur = '';
        if (e?.outing != null) {
          final m = _timeDiffMin(e!.outing!, timeStr);
          if (m > 0) dur = ' (${_fmtMin(m)})';
        }
        _state = DayState.returned;
        await _saveState();
        _sendNfc('🏠 귀가 $tgTime$dur');
        _notifyNative(title: '귀가', body: '귀가 $tgTime$dur');
        _emitAction('outing_end', '🏠', '귀가 $tgTime$dur');
      } else {
        // ── 외출 ──
        await fb.updateTimeRecord(dateStr,
            _withFields(dateStr, e, outing: timeStr, clearReturnHome: true))
            .timeout(const Duration(seconds: 5));
        String loc = '';
        try {
          final pos = await LocationService().getCurrentPosition();
          if (pos != null) loc = ' (${LocationService.formatPosition(pos)})';
        } catch (_) {}
        _state = DayState.outing;
        await _saveState();
        _cancelReminders();
        _sendNfc('🚶 외출 $tgTime$loc');
        _notifyNative(title: '외출', body: '외출 $tgTime');
        _emitAction('outing_start', '🚪', '외출 $tgTime$loc');
      }
    } catch (e) {
      _log('Outing 에러: $e');
    }
  }

  // ═══ 공부 (study) ═══

  Future<void> _handleStudy(String dateStr, String timeStr) async {
    _log('공부: state=${_state.name}');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final e = records[dateStr];
      final tgTime = DateFormat('HH:mm').format(DateTime.now());

      // Case 1: 외출 중 → 귀가 + 공부 재개
      if (_state == DayState.outing) {
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, returnHome: timeStr))
            .timeout(const Duration(seconds: 5));
        String dur = '외출';
        if (e?.outing != null) {
          final m = _timeDiffMin(e!.outing!, timeStr);
          if (m > 0) dur = '외출 ${_fmtMin(m)}';
        }
        _state = DayState.studying;
        await _saveState();
        _startMealReminder();
        _sendNfc('📚 공부 재개 $tgTime ($dur)');
        _notifyNative(title: '공부 재개', body: '귀가 → 공부 ($dur)');
        _emitAction('study_resume', '📚', '공부 재개 ($dur)');
        _triggerWidgetUpdate();
        return;
      }

      // Case 2: 공부 중 → 종료
      if (_state == DayState.studying) {
        // 열린 식사 닫기
        final meals = List<MealEntry>.from(e?.meals ?? []);
        if (_isMealing) {
          final openIdx = meals.lastIndexWhere((m) => m.end == null);
          if (openIdx >= 0) meals[openIdx] = meals[openIdx].withEnd(timeStr);
          _isMealing = false;
        }
        await fb.updateTimeRecord(dateStr,
            _withFields(dateStr, e, studyEnd: timeStr, meals: meals.isNotEmpty ? meals : null))
            .timeout(const Duration(seconds: 5));
        String dur = '';
        if (e?.study != null) {
          final net = _calcNetStudy(e!, timeStr);
          if (net > 0) dur = ' (순공 ${_fmtMin(net)})';
        }
        _state = DayState.returned;
        await _saveState();
        _cancelReminders();
        _sendNfc('📚 공부 종료 $tgTime$dur');
        _notifyNative(title: '공부 종료', body: '공부 종료 $tgTime$dur');
        _emitAction('study_end', '📚', '공부종료 $tgTime$dur');
        return;
      }

      // Case 3: 새 공부 시작
      final place = _findTagPlace(NfcTagRole.study);
      await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, study: timeStr))
          .timeout(const Duration(seconds: 5));
      final placeMsg = place != null ? ' ($place)' : '';
      _state = DayState.studying;
      await _saveState();
      _startMealReminder();
      _sendNfc('📚 공부 시작 $tgTime$placeMsg');
      _notifyNative(title: '공부 시작', body: '공부 시작 $tgTime$placeMsg');
      _emitAction('study_start', '📚', '공부시작 $tgTime$placeMsg');
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Study 에러: $e');
    }
  }

  // ═══ 식사 (meal) — DayState 변경 없음 ═══

  Future<void> _handleMeal(String dateStr, String timeStr) async {
    _log('식사: mealing=$_isMealing');
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final e = records[dateStr];
      final meals = List<MealEntry>.from(e?.meals ?? []);
      final tgTime = DateFormat('HH:mm').format(DateTime.now());

      if (!_isMealing) {
        // ── 식사 시작 ──
        _isMealing = true;
        meals.add(MealEntry(start: timeStr));
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, meals: meals))
            .timeout(const Duration(seconds: 5));
        String loc = '';
        try {
          final pos = await LocationService().getCurrentPosition();
          if (pos != null) loc = ' (${LocationService.formatPosition(pos)})';
        } catch (_) {}
        await _saveState();
        _sendNfc('🍽 식사 시작 $tgTime$loc');
        _notifyNative(title: '식사 시작', body: '식사 시작 $tgTime (${meals.length}번째)');
        _emitAction('meal_start', '🍽️', '식사 시작 $tgTime');
      } else {
        // ── 식사 종료 ──
        _isMealing = false;
        final openIdx = meals.lastIndexWhere((m) => m.end == null);
        if (openIdx >= 0) meals[openIdx] = meals[openIdx].withEnd(timeStr);
        await fb.updateTimeRecord(dateStr, _withFields(dateStr, e, meals: meals))
            .timeout(const Duration(seconds: 5));
        final dur = openIdx >= 0 ? meals[openIdx].durationFormatted : null;
        final durMsg = dur != null ? ' ($dur)' : '';
        await _saveState();
        _sendNfc('🍽 식사 종료 $tgTime$durMsg');
        _notifyNative(title: '식사 종료', body: '식사 종료 $tgTime$durMsg');
        _emitAction('meal_end', '🍽️', '식사 종료 $tgTime$durMsg');
      }
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Meal 에러: $e');
    }
  }

  // ═══ 수면 (sleep) + 일일 요약 ═══

  Future<void> _handleSleep(String dateStr, String timeStr) async {
    if (_state == DayState.idle || _state == DayState.sleeping) {
      _emitAction('sleep_skip', '🛏️', '취침 불가 (${_state.name})');
      return;
    }
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final now = DateTime.now();

      // UL-2: 4~7시 → 전날 bedTime 미기록이면 전날로 귀속
      if (now.hour >= 4 && now.hour < 7) {
        final yday = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
        if (records[yday]?.bedTime == null) dateStr = yday;
      }

      final e = records[dateStr];
      final meals = List<MealEntry>.from(e?.meals ?? []);

      // 열린 식사 닫기
      if (_isMealing) {
        _isMealing = false;
        final oi = meals.lastIndexWhere((m) => m.end == null);
        if (oi >= 0) meals[oi] = meals[oi].withEnd(timeStr);
      }

      // 공부 중이면 종료
      String? studyEnd;
      if (_state == DayState.studying && e?.study != null && e?.studyEnd == null) {
        studyEnd = timeStr;
      }

      await fb.updateTimeRecord(dateStr,
          _withFields(dateStr, e, studyEnd: studyEnd, bedTime: timeStr, meals: meals))
          .timeout(const Duration(seconds: 5));

      _state = DayState.sleeping;
      await _saveState();
      _cancelReminders();

      final tgTime = DateFormat('HH:mm').format(now);
      final summary = _buildSummary(e, studyEnd ?? e?.studyEnd, timeStr, meals);
      _sendNfc('😴 취침 $tgTime\n$summary');
      _notifyNative(title: '취침', body: '취침 $tgTime — 좋은 밤 되세요');
      _emitAction('sleep', '🛏️', '취침 $tgTime');
      _triggerWidgetUpdate();
    } catch (e) {
      _log('Sleep 에러: $e');
    }
  }

  // ═══ 일일 요약 ═══

  String _buildSummary(TimeRecord? e, String? studyEnd, String bed, List<MealEntry> meals) {
    final lines = <String>[];
    if (e?.wake != null) lines.add('⏱ 활동 ${_fmtMin(_timeDiffMin(e!.wake!, bed))}');
    if (e?.study != null && studyEnd != null) {
      final total = _timeDiffMin(e!.study!, studyEnd);
      int mealMin = 0;
      for (final m in meals) { if (m.durationMin != null) mealMin += m.durationMin!; }
      final net = (total - mealMin).clamp(0, 1440);
      if (net > 0) lines.add('📚 순공 ${_fmtMin(net)}');
    }
    final done = meals.where((m) => m.durationMin != null).toList();
    if (done.isNotEmpty) {
      final tm = done.fold<int>(0, (s, m) => s + m.durationMin!);
      lines.add('🍽 식사 ${done.length}회 (${_fmtMin(tm)})');
    }
    if (e?.outing != null && e?.returnHome != null) {
      final m = _timeDiffMin(e!.outing!, e!.returnHome!);
      if (m > 0) lines.add('🚶 외출 ${_fmtMin(m)}');
    }
    if (lines.isEmpty) return '오늘 하루 수고하셨습니다 🌙';
    return '── 일일 요약 ──\n${lines.join('\n')}';
  }

  // ═══ Utilities ═══

  void _triggerWidgetUpdate() {
    Future.delayed(const Duration(milliseconds: 500), () async {
      try { (await SharedPreferences.getInstance()).setBool('widget_needs_update', true); } catch (_) {}
    });
  }

  void _sendNfc(String msg) { TelegramService().sendNfc(msg); }

  Future<void> _notifyNative({required String title, required String body}) async {
    try { await _nfcChannel.invokeMethod('showNotification', {'title': title, 'body': body}); }
    catch (_) {}
  }

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notifPermissionRequested) return;
    _notifPermissionRequested = true;
    try { await _nfcChannel.invokeMethod('requestNotificationPermission'); } catch (_) {}
  }

  int _timeDiffMin(String start, String end) {
    final sp = start.split(':'); final ep = end.split(':');
    final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
    var e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
    if (e < s) e += 1440;
    return e - s;
  }

  String _fmtMin(int m) => m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';

  int _calcNetStudy(TimeRecord tr, String end) {
    if (tr.study == null) return 0;
    final total = _timeDiffMin(tr.study!, end);
    int meal = 0;
    for (final m in tr.meals) { if (m.durationMin != null) meal += m.durationMin!; }
    return (total - meal).clamp(0, 1440);
  }

  String? _findTagPlace(NfcTagRole role) {
    for (final t in _tags) { if (t.role == role && t.placeName != null) return t.placeName; }
    return null;
  }
}
