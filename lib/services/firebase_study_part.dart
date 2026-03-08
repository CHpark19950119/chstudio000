part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Study Doc CRUD (timeRecords, studyTime, focusCycles, liveFocus, customTasks)
/// ═══════════════════════════════════════════════════════════
extension FirebaseStudyOps on FirebaseService {

  // ── timeRecords ──

  Future<Map<String, TimeRecord>> getTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_timeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_timeRecordsField] as Map);
    return raw.map((date, value) => MapEntry(
          date, TimeRecord.fromMap(date, Map<String, dynamic>.from(value as Map))));
  }

  Future<void> updateTimeRecord(String date, TimeRecord record) async {
    final recordMap = record.toMap();
    debugPrint('[FB] updateTimeRecord: $date');
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_timeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_timeRecordsField.$date', recordMap);
    _db.doc(_studyDoc).update({
      '$_timeRecordsField.$date': recordMap,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).then((_) {
      debugPrint('[FB] updateTimeRecord: OK');
    }).catchError((e) {
      debugPrint('[FB] updateTimeRecord: update failed, trying set...');
      _db.doc(_studyDoc).set({
        _timeRecordsField: {date: recordMap},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true)).catchError((_) {});
    });
    if (date == StudyDateUtils.todayKey()) {
      updateTodayField('timeRecords', recordMap);
    }
  }

  // ── studyTimeRecords ──

  Future<Map<String, StudyTimeRecord>> getStudyTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_studyTimeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_studyTimeRecordsField] as Map);
    return raw.map((date, value) => MapEntry(
          date, StudyTimeRecord.fromMap(date, Map<String, dynamic>.from(value as Map))));
  }

  Future<void> updateStudyTimeRecord(String date, StudyTimeRecord record) async {
    if (record.effectiveMinutes == 0 && record.totalMinutes == 0) return;
    final recordMap = record.toMap();
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_studyTimeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_studyTimeRecordsField.$date', recordMap);
    _db.doc(_studyDoc).update({
      '$_studyTimeRecordsField.$date': recordMap,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).catchError((e) {
      _db.doc(_studyDoc).set({
        _studyTimeRecordsField: {date: recordMap},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
        }, SetOptions(merge: true)).catchError((_) {});
    });
    if (date == StudyDateUtils.todayKey()) {
      updateTodayField('studyTime.total', record.effectiveMinutes);
    }
  }

  // ── focusCycles ──

  Future<List<FocusCycle>> getFocusCycles(String date) async {
    final data = await getStudyData();
    if (data == null || data[_focusCyclesField] == null) return [];
    final raw = Map<String, dynamic>.from(data[_focusCyclesField] as Map);
    if (raw[date] == null) return [];
    final dayData = raw[date] as List<dynamic>;
    return dayData
        .map((c) => FocusCycle.fromMap(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  Future<void> saveFocusCycle(String date, FocusCycle cycle) async {
    final cycles = await getFocusCycles(date);
    final idx = cycles.indexWhere((c) => c.id == cycle.id);
    if (idx >= 0) {
      cycles[idx] = cycle;
    } else {
      cycles.add(cycle);
    }
    final cyclesList = cycles.map((c) => c.toMap()).toList();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_focusCyclesField, () => {}) as Map)[date] = cyclesList;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_focusCyclesField.$date', cyclesList);
    _db.doc(_studyDoc).update({
      '$_focusCyclesField.$date': cyclesList,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).catchError((e) {
      _db.doc(_studyDoc).set({
        _focusCyclesField: {date: cyclesList},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true)).catchError((_) {});
    });
    _cleanOldFocusCycles();
  }

  Future<void> overwriteFocusCycles(String date, List<FocusCycle> cycles) async {
    final cyclesList = cycles.map((c) => c.toMap()).toList();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_focusCyclesField, () => {}) as Map)[date] = cyclesList;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_focusCyclesField.$date', cyclesList);
    try {
      await _db.doc(_studyDoc).update({
        '$_focusCyclesField.$date': cyclesList,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      try {
        await _db.doc(_studyDoc).set({
          _focusCyclesField: {date: cyclesList},
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  Future<void> _cleanOldFocusCycles() async {
    try {
      final data = _studyCache ?? await getStudyData();
      if (data == null) return;
      final raw = data[_focusCyclesField];
      if (raw == null || raw is! Map) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final keysToDelete = <String, dynamic>{};
      for (final key in (raw as Map<String, dynamic>).keys) {
        try {
          if (DateTime.parse(key).isBefore(cutoff)) {
            keysToDelete['$_focusCyclesField.$key'] = FieldValue.delete();
          }
        } catch (_) {}
      }
      if (keysToDelete.isNotEmpty) {
        await _db.doc(_studyDoc).update(keysToDelete).timeout(const Duration(seconds: 5));
        final cached = _studyCache?[_focusCyclesField];
        if (cached is Map) {
          for (final key in keysToDelete.keys) {
            final dateKey = key.replaceFirst('$_focusCyclesField.', '');
            (cached as Map).remove(dateKey);
          }
        }
        debugPrint('[FocusClean] ${keysToDelete.length} old dates deleted');
      }
    } catch (e) {
      debugPrint('[FocusClean] cleanup failed (ignored): $e');
    }
  }

  // ── liveFocus (separate doc) ──

  Future<void> updateLiveFocus(String date, Map<String, dynamic> data) async {
    try {
      await _db.doc(_liveFocusDoc).set({
        ...data,
        'date': date,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> clearLiveFocus(String date) async {
    try {
      await _db.doc(_liveFocusDoc).delete().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  // ── customStudyTasks ──

  Future<List<String>> getCustomStudyTasks(String date) async {
    final data = await getStudyData();
    if (data == null || data[_customTasksField] == null) return [];
    final all = Map<String, dynamic>.from(data[_customTasksField] as Map);
    final dayTasks = all[date];
    if (dayTasks == null) return [];
    return (dayTasks as List<dynamic>).map((e) => e.toString()).toList();
  }

  Future<void> addCustomStudyTask(String date, String task) async {
    final tasks = await getCustomStudyTasks(date);
    tasks.add(task);
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> editCustomStudyTask(String date, int index, String newTask) async {
    final tasks = await getCustomStudyTasks(date);
    if (index < 0 || index >= tasks.length) return;
    tasks[index] = newTask;
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> deleteCustomStudyTask(String date, int index) async {
    final tasks = await getCustomStudyTasks(date);
    if (index < 0 || index >= tasks.length) return;
    tasks.removeAt(index);
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> _saveCustomStudyTasks(String date, List<String> tasks) async {
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_customTasksField, () => {}) as Map)[date] = tasks;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_customTasksField.$date', tasks);
    try {
      await _db.doc(_studyDoc).update({
        '$_customTasksField.$date': tasks,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      try {
        await _db.doc(_studyDoc).set({
          _customTasksField: {date: tasks},
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }
}
