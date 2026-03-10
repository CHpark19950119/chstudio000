part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Today Doc + History + Archive + Rollover + RestDays
/// ═══════════════════════════════════════════════════════════
extension FirebaseHistoryOps on FirebaseService {

  // ── Today doc (Phase C) ──

  Future<Map<String, dynamic>?> getTodayDoc() async {
    if (_todayCache2 != null && _todayCacheTime2 != null &&
        DateTime.now().difference(_todayCacheTime2!) < const Duration(minutes: 2)) {
      return _todayCache2;
    }
    final result = await _cachedDocGet('today', _todayDoc2);
    if (result != null) {
      _todayCache2 = result;
      _todayCacheTime2 = DateTime.now();
    }
    return result;
  }

  Future<void> updateTodayField(String field, dynamic value) async {
    LocalCacheService().markWrite();
    _todayCache2 ??= {};
    _setNestedValue(_todayCache2!, field, value);
    _todayCacheTime2 = DateTime.now();
    final localData = LocalCacheService().getGeneric('today') ?? {};
    _setNestedValue(localData, field, value);
    await LocalCacheService().saveGeneric('today', localData);
    _db.doc(_todayDoc2).update({
      field: value,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).catchError((e) {
      _db.doc(_todayDoc2).set({
        field: value,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true)).catchError((_) {});
    });
  }

  Future<void> _setTodayDoc(Map<String, dynamic> data) async {
    LocalCacheService().markWrite();
    _todayCache2 = data;
    _todayCacheTime2 = DateTime.now();
    await LocalCacheService().saveGeneric('today', data);
    try {
      await _db.doc(_todayDoc2).set(data).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[FB] setTodayDoc fail: $e');
    }
  }

  void _setNestedValue(Map<String, dynamic> map, String dotPath, dynamic value) {
    if (value is FieldValue) return;
    final parts = dotPath.split('.');
    if (parts.length == 1) {
      map[parts.first] = value;
      return;
    }
    Map<String, dynamic> current = map;
    for (int i = 0; i < parts.length - 1; i++) {
      if (current[parts[i]] is! Map) {
        current[parts[i]] = <String, dynamic>{};
      }
      current = Map<String, dynamic>.from(current[parts[i]] as Map);
      if (i == 0) {
        map[parts[0]] = current;
      } else {
        Map<String, dynamic> nav = map;
        for (int j = 0; j < i; j++) {
          nav = nav[parts[j]] as Map<String, dynamic>;
        }
        nav[parts[i]] = current;
      }
    }
    current[parts.last] = value;
  }

  // ── History (monthly) ──

  Future<Map<String, dynamic>?> getMonthHistory(String month) async {
    return _cachedDocGet('history_$month', 'users/$_uid/history/$month');
  }

  Future<void> appendDayToHistory(String date, Map<String, dynamic> dayData) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    try {
      await _db.doc('users/$_uid/history/$month').set({
        'month': month,
        'days': {day: dayData},
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      await LocalCacheService().removeGeneric('history_$month');
      debugPrint('[FB] appendDayToHistory: $date OK');
    } catch (e) {
      debugPrint('[FB] appendDayToHistory fail: $e');
    }
  }

  Future<void> appendFocusSessionToHistory(String date, Map<String, dynamic> session) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    try {
      await _db.doc('users/$_uid/history/$month').set({
        'month': month,
        'days': {day: {'focusSessions': FieldValue.arrayUnion([session])}},
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      await LocalCacheService().removeGeneric('history_$month');
    } catch (e) {
      debugPrint('[FB] appendFocusSession fail: $e');
    }
  }

  Future<void> _recalculateMonthSummary(String month) async {
    try {
      final history = await _db.doc('users/$_uid/history/$month')
          .get().timeout(const Duration(seconds: 10));
      if (!history.exists || history.data() == null) return;
      final data = history.data()!;
      final days = data['days'] as Map<String, dynamic>? ?? {};
      final summary = _calculateMonthlySummary(days);
      await _db.doc('users/$_uid/history/$month').update({
        'summary': summary,
        'lastUpdated': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      debugPrint('[FB] recalculateMonthSummary: $month OK');
    } catch (e) {
      debugPrint('[FB] recalculateMonthSummary fail: $e');
    }
  }

  Map<String, dynamic> _calculateMonthlySummary(Map<String, dynamic> days) {
    int totalMinutes = 0;
    Map<String, int> subjectTotals = {};
    int todosCompleted = 0;
    int todosTotal = 0;
    int activeDays = 0;
    int bestMinutes = 0;
    String bestDay = '';

    for (final entry in days.entries) {
      final day = entry.key;
      if (entry.value is! Map) continue;
      final data = Map<String, dynamic>.from(entry.value as Map);

      final st = data['studyTime'];
      if (st is Map && st['total'] is num) {
        final mins = (st['total'] as num).toInt();
        totalMinutes += mins;
        activeDays++;
        if (mins > bestMinutes) { bestMinutes = mins; bestDay = day; }
        final subjects = st['subjects'];
        if (subjects is Map) {
          for (final s in subjects.entries) {
            subjectTotals[s.key.toString()] = (subjectTotals[s.key.toString()] ?? 0) + (s.value as num).toInt();
          }
        }
      }

      final str = data['studyTimeRecords'];
      if (st == null && str is Map) {
        final mins = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
        if (mins > 0) {
          totalMinutes += mins;
          activeDays++;
          if (mins > bestMinutes) { bestMinutes = mins; bestDay = day; }
        }
      }

      final t = data['todos'];
      if (t is List) {
        todosTotal += t.length;
        todosCompleted += t.where((i) => i is Map && i['done'] == true).length;
      }
    }

    return {
      'totalStudyMinutes': totalMinutes,
      'avgDailyMinutes': activeDays > 0 ? (totalMinutes / activeDays).round() : 0,
      'subjectTotals': subjectTotals,
      'bestDay': {'date': bestDay, 'minutes': bestMinutes},
      'todosCompletionRate': todosTotal > 0 ? (todosCompleted / todosTotal) : 0.0,
      'activeDays': activeDays,
    };
  }

  // ── Archive ──

  Future<void> autoArchive() async {
    final prefs = await SharedPreferences.getInstance();
    final today = StudyDateUtils.todayKey();
    final lastArchive = prefs.getString('last_archive_date');
    if (lastArchive == today) return;

    debugPrint('[Archive] starting...');
    final data = await getStudyData();
    if (data == null) return;

    final cutoffDt = DateTime.now().subtract(const Duration(days: 7));
    final cutoff = DateFormat('yyyy-MM-dd').format(cutoffDt);

    final archiveByMonth = <String, Map<String, dynamic>>{};
    final removals = <String, List<String>>{};
    int totalMoved = 0;

    for (final field in _archiveFields) {
      final raw = data[field];
      if (raw is! Map) continue;
      for (final dateKey in Map<String, dynamic>.from(raw).keys) {
        if (dateKey.compareTo(cutoff) < 0) {
          final month = dateKey.length >= 7 ? dateKey.substring(0, 7) : null;
          if (month == null) continue;
          archiveByMonth.putIfAbsent(month, () => {});
          archiveByMonth[month]!.putIfAbsent(field, () => <String, dynamic>{});
          (archiveByMonth[month]![field] as Map<String, dynamic>)[dateKey] = raw[dateKey];
          removals.putIfAbsent(field, () => []).add(dateKey);
          totalMoved++;
        }
      }
    }

    if (archiveByMonth.isEmpty) {
      await prefs.setString('last_archive_date', today);
      debugPrint('[Archive] nothing to move');
      return;
    }

    try {
      for (final entry in archiveByMonth.entries) {
        final month = entry.key;
        await _db.doc('users/$_uid/archive/$month')
            .set(entry.value, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        final historyDays = <String, Map<String, dynamic>>{};
        final archiveData = entry.value;
        final trMap = archiveData['timeRecords'] as Map?;
        final strMap = archiveData['studyTimeRecords'] as Map?;
        final fcMap = archiveData['focusCycles'] as Map?;
        final todosMap = archiveData['todos'] as Map?;
        for (final dateKey in {...?trMap?.keys, ...?strMap?.keys, ...?fcMap?.keys, ...?todosMap?.keys}) {
          if (dateKey.toString().length < 10) continue;
          final day = dateKey.toString().substring(8, 10);
          historyDays.putIfAbsent(day, () => {});
          if (trMap?[dateKey] != null) historyDays[day]!['timeRecords'] = trMap![dateKey];
          if (strMap?[dateKey] != null) {
            historyDays[day]!['studyTimeRecords'] = strMap![dateKey];
            final str = strMap[dateKey];
            if (str is Map) {
              final effMin = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
              historyDays[day]!['studyTime'] = {'total': effMin, 'subjects': {}};
            }
          }
          if (fcMap?[dateKey] != null) historyDays[day]!['focusSessions'] = fcMap![dateKey];
          if (todosMap?[dateKey] != null) {
            final td = todosMap![dateKey];
            if (td is Map) historyDays[day]!['todos'] = td['items'] ?? [];
          }
        }
        if (historyDays.isNotEmpty) {
          await _db.doc('users/$_uid/history/$month').set({
            'month': month,
            'days': historyDays,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
          await LocalCacheService().removeGeneric('history_$month');
        }
        debugPrint('[Archive] $month saved OK (archive + history)');
      }
    } catch (e) {
      debugPrint('[Archive] save failed: $e');
      return;
    }

    try {
      final updates = <String, dynamic>{};
      for (final entry in removals.entries) {
        for (final dateKey in entry.value) {
          updates['${entry.key}.$dateKey'] = FieldValue.delete();
        }
      }
      updates['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      updates['lastDevice'] = 'android';
      await _db.doc(_studyDoc).update(updates)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Archive] study cleanup failed: $e');
      return;
    }

    for (final entry in removals.entries) {
      final field = _studyCache?[entry.key];
      if (field is Map) {
        for (final key in entry.value) {
          field.remove(key);
        }
      }
    }
    _studyCacheTime = DateTime.now();
    if (_studyCache != null) {
      await LocalCacheService().saveStudyData(_studyCache!);
    }

    await prefs.setString('last_archive_date', today);
    debugPrint('[Archive] done: $totalMoved dates moved');
  }

  Future<Map<String, dynamic>?> getArchive(String yearMonth) async {
    final cached = LocalCacheService().getGeneric('archive_$yearMonth');
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final cacheDoc = await _db.doc('users/$_uid/archive/$yearMonth')
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheDoc.exists && cacheDoc.data() != null) {
        LocalCacheService().saveGeneric('archive_$yearMonth', cacheDoc.data()!);
        return cacheDoc.data();
      }
    } catch (_) {}
    try {
      final doc = await _db.doc('users/$_uid/archive/$yearMonth')
          .get().timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric('archive_$yearMonth', doc.data()!);
        return doc.data();
      }
    } catch (e) {
      debugPrint('[FB] getArchive fail: $e');
    }
    return null;
  }

  // ── Rest days ──

  Future<List<String>> getRestDays() async {
    final data = await getStudyData();
    if (data == null || data[_restDaysField] == null) return [];
    final raw = data[_restDaysField] as List<dynamic>;
    return raw.map((e) => e.toString()).toList();
  }

  Future<bool> toggleRestDay(String date) async {
    final days = await getRestDays();
    final isRest = days.contains(date);
    if (isRest) {
      days.remove(date);
    } else {
      days.add(date);
    }
    LocalCacheService().markWrite();
    _studyCache ??= {};
    _studyCache![_restDaysField] = days;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField(_restDaysField, days);
    try {
      await _db.doc(_studyDoc).update({
        _restDaysField: days,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      try {
        await _db.doc(_studyDoc).set({
          _restDaysField: days,
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    return !isRest;
  }

  // ── 4AM Rollover ──

  Future<void> checkDayRollover() async {
    try {
      final todayData = await getTodayDoc();
      if (todayData == null) return;

      final savedDate = todayData['date'] as String?;
      final currentDate = StudyDateUtils.todayKey();

      if (savedDate == null || savedDate == currentDate) return;

      debugPrint('[Rollover] $savedDate -> $currentDate archiving...');

      await appendDayToHistory(savedDate, todayData);
      final month = savedDate.substring(0, 7);
      _recalculateMonthSummary(month); // fire-and-forget

      final newToday = <String, dynamic>{
        'date': currentDate,
        'timeRecords': <String, dynamic>{},
        'studyTime': {'total': 0, 'subjects': <String, dynamic>{}},
        'todos': <Map<String, dynamic>>[],
        'orderData': todayData['orderData'] ?? {},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      };
      await _setTodayDoc(newToday);

      debugPrint('[Rollover] archiving done');
    } catch (e) {
      debugPrint('[Rollover] error: $e');
    }
  }
}
