import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/plan_models.dart';
import '../utils/study_date_utils.dart';
import 'local_cache_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  FirebaseFirestore get _db => firestore;

  static const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
  String get uid => _uid;

  // ═══════════════════════════════════════════════════════════
  //  단일 study 문서 — 모든 데이터를 1개 문서에 저장
  //  (Phase B 분리 실험 → 역마이그레이션 후 원복)
  // ═══════════════════════════════════════════════════════════

  static const String _studyDoc     = 'users/$_uid/data/study';
  static const String _liveFocusDoc = 'users/$_uid/data/liveFocus'; // liveFocus만 별도 유지

  // ★ 역마이그레이션 소스 (읽기 전용 — 데이터 복구용)
  static const String _focusDocOld     = 'users/$_uid/data/focus';
  static const String _orderDocOld     = 'users/$_uid/data/order';
  static const String _todosDocOld     = 'users/$_uid/data/todos';
  static const String _metaDocOld      = 'users/$_uid/data/meta';
  static const String _planDocOld      = 'users/$_uid/data/plan';
  static const String _calendarDocOld  = 'users/$_uid/data/calendar';
  static const String _diariesDocOld   = 'users/$_uid/data/diaries';

  // 외부 서비스가 참조하는 경로 — 전부 study 문서를 가리킴
  static String get studyDocPath    => _studyDoc;
  static String get focusDocPath    => _studyDoc;
  static String get orderDocPath    => _studyDoc;
  static String get todosDocPath    => _studyDoc;
  static String get planDocPath     => _studyDoc;
  static String get calendarDocPath => _studyDoc;
  static String get diariesDocPath  => _studyDoc;
  static String get metaDocPath     => _studyDoc;

  // ═══════════════════════════════════════════════════════════
  //  Today + Monthly History 아키텍처 (Phase C)
  // ═══════════════════════════════════════════════════════════
  static const String _todayDoc2 = 'users/$_uid/data/today';
  static const String _creatureDoc = 'users/$_uid/data/creature';
  // history: users/{uid}/history/{yyyy-MM}

  static const String _mindDoc = 'users/$_uid/data/mind';
  static const String _settingsDoc = 'users/$_uid/data/settings';
  static const String _alarmSettingsDoc = 'users/$_uid/settings/alarm';
  static const String _focusModeDoc = 'users/$_uid/settings/focusMode';
  static const String _appUsageCol = 'users/$_uid/appUsageStats';
  static const String _locationHistoryCol = 'users/$_uid/locationHistory';
  static const String _knownPlacesDoc = 'users/$_uid/data/knownPlaces';
  static const String _behaviorTimelineCol = 'users/$_uid/behaviorTimeline';
  static const String _nfcTagsDoc = 'users/$_uid/settings/nfcTags';
  static const String _nfcEventsCol = 'users/$_uid/nfcEvents';
  static const String _sleepSettingsDoc = 'users/$_uid/settings/sleep';
  static const String _sleepRecordsCol = 'users/$_uid/sleepRecords';
  static const String _memosCol = 'users/$_uid/memos';

  static const String _timeRecordsField = 'timeRecords';
  static const String _studyTimeRecordsField = 'studyTimeRecords';
  static const String _focusCyclesField = 'focusCycles';

  // ═══════════════════════════════════════════════════════════
  //  인메모리 캐시: study 문서 1개
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic>? _studyCache;
  DateTime? _studyCacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  /// study 문서 로드 — 로컬 퍼스트 하이브리드
  /// 1) 인메모리 → 2) SharedPreferences → 3) Firestore 캐시 → 4) 서버
  /// 2/3에서 반환 시 백그라운드로 서버 갱신 (화면 블로킹 없음)
  Future<Map<String, dynamic>?> getStudyData() async {
    // 1) 인메모리 캐시 (5분 TTL)
    if (_studyCache != null && _studyCacheTime != null &&
        DateTime.now().difference(_studyCacheTime!) < _cacheTtl) {
      return _studyCache;
    }

    // 2) SharedPreferences 로컬 캐시 (즉시 반환)
    final localCache = LocalCacheService();
    final localData = localCache.getStudyData();
    if (localData != null) {
      _studyCache = localData;
      _studyCacheTime = DateTime.now();
      debugPrint('[FB] study: SharedPrefs hit (${localData.length} fields)');
      _refreshStudyInBackground(); // 백그라운드 갱신 (결과 안 기다림)
      return localData;
    }

    // 3) Firestore 로컬 캐시
    try {
      final localDoc = await _db.doc(_studyDoc)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (localDoc.exists && localDoc.data() != null) {
        final data = localDoc.data()!;
        _studyCache = data; _studyCacheTime = DateTime.now();
        debugPrint('[FB] study: Firestore cache hit (${data.length} fields)');
        localCache.saveStudyData(data); // 로컬에도 저장
        _refreshStudyInBackground();
        return data;
      }
    } catch (e) {
      debugPrint('[FB] study Firestore cache miss: $e');
    }

    // 4) stale 인메모리 캐시라도 반환
    if (_studyCache != null) {
      debugPrint('[FB] study: stale cache (${_studyCache!.length} fields)');
      _refreshStudyInBackground();
      return _studyCache;
    }

    // 5) 서버 fallback (최초 실행 — 모든 캐시 없음)
    try {
      final doc = await _db.doc(_studyDoc).get()
          .timeout(const Duration(seconds: 15));
      final data = doc.data();
      if (data != null) {
        _studyCache = data; _studyCacheTime = DateTime.now();
        await localCache.saveStudyData(data);
        debugPrint('[FB] study: server OK (${data.length} fields)');
      }
      return data;
    } catch (e) {
      debugPrint('[FB] study server fail: $e');
      return null;
    }
  }

  /// 백그라운드 Firebase 갱신 (화면 블로킹 없음)
  bool _refreshingStudy = false;
  void _refreshStudyInBackground() {
    if (_refreshingStudy) return;
    _refreshingStudy = true;
    Future(() async {
      try {
        // write 보호 중이면 스킵 (방금 입력한 데이터 덮어쓰기 방지)
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[FB] bg refresh skip: write-protected');
          _refreshingStudy = false;
          return;
        }
        final doc = await _db.doc(_studyDoc).get()
            .timeout(const Duration(seconds: 15));
        if (doc.exists && doc.data() != null) {
          if (LocalCacheService().isWriteProtected()) {
            debugPrint('[FB] bg refresh skip after fetch: write-protected');
            return;
          }
          final data = doc.data()!;
          _studyCache = data;
          _studyCacheTime = DateTime.now();
          await LocalCacheService().saveStudyData(data);
          debugPrint('[FB] background refresh OK (${data.length} fields)');
        }
      } catch (e) {
        debugPrint('[FB] background refresh fail: $e');
        // 실패해도 아무 일 없음 — 이미 로컬 데이터로 화면 표시 중
      } finally {
        _refreshingStudy = false;
      }
    });
  }

  // ★ 하위 호환 별칭 — 전부 getStudyData() 위임
  Future<Map<String, dynamic>?> getFocusData() => getStudyData();
  Future<Map<String, dynamic>?> getOrderData() => getStudyData();
  Future<Map<String, dynamic>?> getTodosData() => getStudyData();
  Future<Map<String, dynamic>?> getMetaData() => getStudyData();
  Future<Map<String, dynamic>?> getPlanData() => getStudyData();
  Future<Map<String, dynamic>?> getCalendarData() => getStudyData();
  Future<Map<String, dynamic>?> getDiariesData() => getStudyData();

  /// 캐시 무효화 — 비활성화됨 (캐시 파괴 방지)
  /// 절대 인메모리 캐시를 날리지 않음. write 후에는 캐시를 직접 갱신할 것.
  void invalidateCache() {
    debugPrint('[FB] invalidateCache 호출됨 — 무시 (캐시 보호)');
  }
  void invalidateFocusCache() {}
  void invalidateOrderCache() {}
  void invalidateTodosCache() {}
  void invalidateMetaCache() {}

  /// 스트림에서 캐시 갱신
  void updateCacheFromStream(Map<String, dynamic> data) {
    _studyCache = data;
    _studyCacheTime = DateTime.now();
    LocalCacheService().saveStudyData(data); // 로컬에도 저장
  }

  /// todos 캐시 즉시 갱신
  void updateTodosCache(String date, Map<String, dynamic> todoMap) {
    LocalCacheService().markWrite(); // ★ write 보호 (스트림 덮어쓰기 방지)
    _studyCache ??= {};
    (_studyCache!.putIfAbsent('todos', () => {}) as Map)[date] = todoMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('todos.$date', todoMap);
  }

  /// order 캐시 즉시 갱신
  void updateOrderCache(Map<String, dynamic> orderDataMap) {
    LocalCacheService().markWrite(); // ★ write 보호
    _studyCache ??= {};
    _studyCache!['orderData'] = orderDataMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('orderData', orderDataMap);
  }

  // ═══════════════════════════════════════════════════════════
  //  역마이그레이션: 분리된 문서 → study 문서로 합침
  // ═══════════════════════════════════════════════════════════

  Future<void> runReverseMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('reverse_migration_v2_done') == true) return;

    debugPrint('[ReverseMigration] 시작...');
    try {
      final mergeFields = <String, dynamic>{};
      const t = Duration(seconds: 5);

      // ★ 모든 분리 문서를 병렬로 읽기 — 로컬 캐시 → 서버 순서
      Future<Map<String, dynamic>?> _safeGet(String path) async {
        // 1) 로컬 캐시 먼저 (빠름, 네트워크 불필요)
        try {
          final cached = await _db.doc(path)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (cached.exists && cached.data() != null) {
            debugPrint('[ReverseMigration] $path 로컬 캐시 OK');
            return cached.data();
          }
        } catch (_) {}
        // 2) 서버 (5초 타임아웃)
        try {
          final snap = await _db.doc(path).get().timeout(t);
          if (snap.exists) return snap.data();
        } catch (e) {
          debugPrint('[ReverseMigration] $path 실패: $e');
        }
        return null;
      }
      final results = await Future.wait([
        _safeGet(_focusDocOld),
        _safeGet(_orderDocOld),
        _safeGet(_todosDocOld),
        _safeGet(_metaDocOld),
        _safeGet(_planDocOld),
        _safeGet(_calendarDocOld),
        _safeGet(_diariesDocOld),
      ]).timeout(const Duration(seconds: 8), onTimeout: () {
        debugPrint('[ReverseMigration] 전체 병렬 읽기 타임아웃');
        return List<Map<String, dynamic>?>.filled(7, null);
      });

      // focus → focusCycles
      if (results[0] != null) {
        if (results[0]!['focusCycles'] != null) mergeFields['focusCycles'] = results[0]!['focusCycles'];
        debugPrint('[ReverseMigration] focus OK');
      }
      // order → orderData
      if (results[1] != null) {
        if (results[1]!['orderData'] != null) mergeFields['orderData'] = results[1]!['orderData'];
        debugPrint('[ReverseMigration] order OK');
      }
      // todos → todos
      if (results[2] != null) {
        if (results[2]!['todos'] != null) mergeFields['todos'] = results[2]!['todos'];
        debugPrint('[ReverseMigration] todos OK');
      }
      // meta → progressGoals, restDays, streak
      if (results[3] != null) {
        for (final key in ['progressGoals', 'restDays', 'streak']) {
          if (results[3]![key] != null) mergeFields[key] = results[3]![key];
        }
        debugPrint('[ReverseMigration] meta OK');
      }
      // plan → studyPlan, dailyFeedback, etc.
      if (results[4] != null) {
        for (final key in ['studyPlan', 'dailyFeedback', 'weeklyReview',
            'growthMetrics', 'customStudyTasks', 'customDayPlans']) {
          if (results[4]![key] != null) mergeFields[key] = results[4]![key];
        }
        debugPrint('[ReverseMigration] plan OK');
      }
      // calendar → calendarEvents, dailyMemos, etc.
      if (results[5] != null) {
        for (final key in ['calendarEvents', 'dailyMemos', 'pinnedMemos',
            'planSchedule', 'planMilestones']) {
          if (results[5]![key] != null) mergeFields[key] = results[5]![key];
        }
        debugPrint('[ReverseMigration] calendar OK');
      }
      // diaries → dayDiaries, journals
      if (results[6] != null) {
        for (final key in ['dayDiaries', 'journals']) {
          if (results[6]![key] != null) mergeFields[key] = results[6]![key];
        }
        debugPrint('[ReverseMigration] diaries OK');
      }

      // study 문서에 합침
      if (mergeFields.isNotEmpty) {
        mergeFields['lastModified'] = DateTime.now().millisecondsSinceEpoch;
        mergeFields['lastDevice'] = 'android';
        await _db.doc(_studyDoc).set(mergeFields, SetOptions(merge: true));
        debugPrint('[ReverseMigration] study 문서에 ${mergeFields.keys.toList()} 합침 완료');
      }

      // ★ 영구 삭제 대상 필드 제거 (AI 관련 + 대용량)
      try {
        final banned = ['chatHistory', 'aiArchive', '_cachedAdvice',
                        'dailyStoryCache', 'dayImages', '_migratedAt', '_phaseBCleanedAt'];
        final deleteMap = <String, dynamic>{};
        for (final key in banned) {
          deleteMap[key] = FieldValue.delete();
        }
        await _db.doc(_studyDoc).update(deleteMap).timeout(const Duration(seconds: 5));
        debugPrint('[ReverseMigration] 금지 필드 삭제 완료');
      } catch (e) {
        debugPrint('[ReverseMigration] 금지 필드 삭제 실패 (무시): $e');
      }

      // 합침 성공 시 플래그 저장 + 캐시 갱신 (서버 재읽기 불필요)
      final merged = mergeFields.keys.toList();
      debugPrint('[ReverseMigration] 합침 결과: $merged');
      if (merged.isNotEmpty) {
        await prefs.setBool('reverse_migration_v2_done', true);
        await prefs.reload();
        // ★ 캐시를 비우지 않고 합친 데이터로 갱신 (서버 타임아웃 방지)
        _studyCache ??= {};
        mergeFields.forEach((k, v) {
          if (k != 'lastModified' && k != 'lastDevice') {
            _studyCache![k] = v;
          }
        });
        _studyCacheTime = DateTime.now();
        debugPrint('[ReverseMigration] 완료! 캐시 갱신됨 (${_studyCache!.length} fields)');
      } else {
        debugPrint('[ReverseMigration] 합칠 데이터 없음 — 다음 시작 시 재시도');
      }
    } catch (e, st) {
      debugPrint('[ReverseMigration] 에러: $e\n$st');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  timeRecords (study 문서 — 유지)
  // ═══════════════════════════════════════════════════════════

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
    // ★ write 보호 마킹 (3초간 스트림/백그라운드 갱신 차단)
    LocalCacheService().markWrite();
    // ★ 캐시 먼저 갱신 (네트워크 무관)
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_timeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    // ★ 로컬 캐시도 갱신
    LocalCacheService().updateStudyField('$_timeRecordsField.$date', recordMap);
    // ★ fire-and-forget: study doc
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
    // ★ Phase C: today 문서에도 timeRecords 동기화
    if (date == StudyDateUtils.todayKey()) {
      updateTodayField('timeRecords', recordMap);
    }
  }

  Future<void> deleteTimeRecord(String date) async {
    // ★ 캐시 먼저 갱신 (네트워크 무관)
    (_studyCache?[_timeRecordsField] as Map?)?.remove(date);
    _studyCacheTime = DateTime.now();
    // ★ 로컬 캐시 갱신
    if (_studyCache != null) LocalCacheService().saveStudyData(_studyCache!);
    // ★ fire-and-forget
    _db.doc(_studyDoc).update({
      '$_timeRecordsField.$date': FieldValue.delete(),
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).catchError((_) {});
  }

  // ═══════════════════════════════════════════════════════════
  //  studyTimeRecords (study 문서 — 유지)
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, StudyTimeRecord>> getStudyTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_studyTimeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_studyTimeRecordsField] as Map);
    return raw.map((date, value) => MapEntry(
          date, StudyTimeRecord.fromMap(date, Map<String, dynamic>.from(value as Map))));
  }

  Future<void> updateStudyTimeRecord(
      String date, StudyTimeRecord record) async {
    if (record.effectiveMinutes == 0 && record.totalMinutes == 0) return;
    final recordMap = record.toMap();
    // ★ write 보호 마킹
    LocalCacheService().markWrite();
    // ★ 캐시 먼저 갱신 (네트워크 무관)
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_studyTimeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    // ★ 로컬 캐시도 갱신
    LocalCacheService().updateStudyField('$_studyTimeRecordsField.$date', recordMap);
    // ★ fire-and-forget: study doc
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
    // ★ Phase C: today 문서에 studyTime 동기화 (effectiveMinutes 기준)
    if (date == StudyDateUtils.todayKey()) {
      updateTodayField('studyTime.total', record.effectiveMinutes);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  focusCycles (study 문서)
  // ═══════════════════════════════════════════════════════════

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
    // ★ 캐시 먼저 갱신 (네트워크 무관)
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_focusCyclesField, () => {}) as Map)[date] = cyclesList;
    _studyCacheTime = DateTime.now();
    // ★ 로컬 캐시도 갱신
    LocalCacheService().updateStudyField('$_focusCyclesField.$date', cyclesList);
    // ★ fire-and-forget
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

    // ★ 7일 이전 focusCycles 자동 정리
    _cleanOldFocusCycles();
  }

  Future<void> overwriteFocusCycles(String date, List<FocusCycle> cycles) async {
    final cyclesList = cycles.map((c) => c.toMap()).toList();
    // ★ 캐시 먼저 갱신
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

  /// 7일 이전 focusCycles 자동 삭제
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
        // 캐시에서도 제거
        final cached = _studyCache?[_focusCyclesField];
        if (cached is Map) {
          for (final key in keysToDelete.keys) {
            final dateKey = key.replaceFirst('$_focusCyclesField.', '');
            (cached as Map).remove(dateKey);
          }
        }
        debugPrint('[FocusClean] ${keysToDelete.length}개 오래된 날짜 삭제');
      }
    } catch (e) {
      debugPrint('[FocusClean] 정리 실패 (무시): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  liveFocus (별도 문서 — 유지)
  // ═══════════════════════════════════════════════════════════

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

  Stream<Map<String, dynamic>?> watchLiveFocus() {
    return _db.doc(_liveFocusDoc).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return snap.data();
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  저널 (study 문서)
  // ═══════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getJournals() async {
    final data = await getStudyData();
    if (data == null || data['journals'] == null) return [];
    final raw = data['journals'] as List<dynamic>;
    return raw
        .map((j) => Map<String, dynamic>.from(j as Map))
        .toList();
  }

  // ─── 범용 캐시 헬퍼 ───

  Future<Map<String, dynamic>?> _cachedDocGet(String cacheKey, String docPath) async {
    // 1) 로컬 캐시
    final cached = LocalCacheService().getGeneric(cacheKey);
    if (cached != null) {
      _bgRefreshDoc(cacheKey, docPath);
      return cached;
    }
    // 2) Firestore 캐시 (3초)
    try {
      final doc = await _db.doc(docPath)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        _bgRefreshDoc(cacheKey, docPath);
        return doc.data();
      }
    } catch (_) {}
    // 3) 서버 (10초)
    try {
      final doc = await _db.doc(docPath).get().timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  void _bgRefreshDoc(String cacheKey, String docPath) {
    Future(() async {
      try {
        final doc = await _db.doc(docPath).get().timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        }
      } catch (_) {}
    });
  }

  // ─── 알람 설정 ───

  Future<AlarmSettings> getAlarmSettings() async {
    final data = await _cachedDocGet('alarm', _alarmSettingsDoc);
    if (data == null) return AlarmSettings();
    return AlarmSettings.fromMap(data);
  }

  Future<void> saveAlarmSettings(AlarmSettings settings) async {
    try {
      await _db.doc(_alarmSettingsDoc).set(settings.toMap()).timeout(const Duration(seconds: 5));
      LocalCacheService().saveGeneric('alarm', settings.toMap());
    } catch (_) {}
  }

  // ─── 집중모드 설정 ───

  Future<FocusModeConfig> getFocusModeConfig() async {
    final doc = await _db.doc(_focusModeDoc).get();
    if (!doc.exists) return FocusModeConfig();
    return FocusModeConfig.fromMap(doc.data()!);
  }

  Future<void> saveFocusModeConfig(FocusModeConfig config) async {
    await _db.doc(_focusModeDoc).set(config.toMap());
  }

  // ─── 앱 사용 통계 ───

  Future<void> saveAppUsageStats(
      String date, List<AppUsageStat> stats) async {
    await _db.collection(_appUsageCol).doc(date).set({
      'date': date,
      'stats': stats.map((s) => s.toMap()).toList(),
      '_updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── 위치 기록 ───

  Future<void> saveLocationRecord(
      String date, LocationRecord record) async {
    await _db.collection(_locationHistoryCol).doc(date).set({
      'date': date,
      'records': FieldValue.arrayUnion([record.toMap()]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<LocationRecord>> getLocationRecords(String date) async {
    // ★ 1) 로컬 캐시 먼저
    final cached = LocalCacheService().getGeneric('locRec_$date');
    if (cached != null && cached['records'] is List) {
      _refreshLocationRecordsInBackground(date);
      return (cached['records'] as List)
          .map((r) => LocationRecord.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    }
    // ★ 2) Firestore 캐시 (3초)
    try {
      final cacheDoc = await _db.collection(_locationHistoryCol).doc(date)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheDoc.exists && cacheDoc.data() != null) {
        final raw = cacheDoc.data()!['records'] as List<dynamic>?;
        if (raw != null) {
          LocalCacheService().saveGeneric('locRec_$date', {'records': raw});
          _refreshLocationRecordsInBackground(date);
          return raw.map((r) => LocationRecord.fromMap(r as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    // ★ 3) 서버 (10초 타임아웃)
    try {
      final doc = await _db.collection(_locationHistoryCol).doc(date)
          .get().timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) return [];
      final raw = doc.data()!['records'] as List<dynamic>?;
      if (raw == null) return [];
      LocalCacheService().saveGeneric('locRec_$date', {'records': raw});
      return raw.map((r) => LocationRecord.fromMap(r as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[FB] getLocationRecords fail: $e');
      return [];
    }
  }

  void _refreshLocationRecordsInBackground(String date) {
    Future(() async {
      try {
        final doc = await _db.collection(_locationHistoryCol).doc(date)
            .get().timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          final raw = doc.data()!['records'] as List<dynamic>?;
          if (raw != null) {
            LocalCacheService().saveGeneric('locRec_$date', {'records': raw});
          }
        }
      } catch (_) {}
    });
  }

  // ─── 등록 장소 ───

  Future<void> saveKnownPlaces(List<KnownPlace> places) async {
    await _db.doc(_knownPlacesDoc).set({
      'places': places.map((p) => p.toMap()).toList(),
      '_updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<KnownPlace>> getKnownPlaces() async {
    // ★ 1) 로컬 캐시 먼저
    final cached = LocalCacheService().getGeneric('knownPlaces');
    if (cached != null && cached['places'] is List) {
      _refreshKnownPlacesInBackground();
      return (cached['places'] as List)
          .map((p) => KnownPlace.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
    }
    // ★ 2) 서버 (10초 타임아웃)
    try {
      final doc = await _db.doc(_knownPlacesDoc).get()
          .timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) return [];
      final raw = doc.data()!['places'] as List<dynamic>?;
      if (raw == null) return [];
      LocalCacheService().saveGeneric('knownPlaces', {'places': raw});
      return raw.map((p) => KnownPlace.fromMap(p as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[FB] getKnownPlaces fail: $e');
      return [];
    }
  }

  void _refreshKnownPlacesInBackground() {
    Future(() async {
      try {
        final doc = await _db.doc(_knownPlacesDoc).get()
            .timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          final raw = doc.data()!['places'] as List<dynamic>?;
          if (raw != null) {
            LocalCacheService().saveGeneric('knownPlaces', {'places': raw});
          }
        }
      } catch (_) {}
    });
  }

  // ─── 행동 타임라인 ───

  Future<void> saveBehaviorTimeline(
      String date, BehaviorTimelineEntry entry) async {
    await _db.collection(_behaviorTimelineCol).doc(date).set({
      'date': date,
      'entries': FieldValue.arrayUnion([entry.toMap()]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<BehaviorTimelineEntry>> getBehaviorTimeline(
      String date) async {
    // ★ 1) 로컬 캐시 먼저
    final cached = LocalCacheService().getGeneric('timeline_$date');
    if (cached != null && cached['entries'] is List) {
      _refreshBehaviorTimelineInBackground(date);
      return (cached['entries'] as List)
          .map((e) => BehaviorTimelineEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    // ★ 2) Firestore 캐시 (3초)
    try {
      final cacheDoc = await _db.collection(_behaviorTimelineCol).doc(date)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheDoc.exists && cacheDoc.data() != null) {
        final raw = cacheDoc.data()!['entries'] as List<dynamic>?;
        if (raw != null) {
          LocalCacheService().saveGeneric('timeline_$date', {'entries': raw});
          _refreshBehaviorTimelineInBackground(date);
          return raw.map((e) => BehaviorTimelineEntry.fromMap(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    // ★ 3) 서버 (10초 타임아웃)
    try {
      final doc = await _db.collection(_behaviorTimelineCol).doc(date)
          .get().timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) return [];
      final raw = doc.data()!['entries'] as List<dynamic>?;
      if (raw == null) return [];
      LocalCacheService().saveGeneric('timeline_$date', {'entries': raw});
      return raw.map((e) => BehaviorTimelineEntry.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[FB] getBehaviorTimeline fail: $e');
      return [];
    }
  }

  void _refreshBehaviorTimelineInBackground(String date) {
    Future(() async {
      try {
        final doc = await _db.collection(_behaviorTimelineCol).doc(date)
            .get().timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          final raw = doc.data()!['entries'] as List<dynamic>?;
          if (raw != null) {
            LocalCacheService().saveGeneric('timeline_$date', {'entries': raw});
          }
        }
      } catch (_) {}
    });
  }

  // ─── NFC 태그 CRUD ───

  Future<void> saveNfcTags(List<NfcTagConfig> tags) async {
    final data = {'tags': tags.map((t) => t.toMap()).toList()};
    await _db.doc(_nfcTagsDoc).set({
      ...data,
      '_updatedAt': FieldValue.serverTimestamp(),
    });
    LocalCacheService().saveGeneric('nfcTags', data);
  }

  Future<List<NfcTagConfig>> getNfcTags() async {
    final data = await _cachedDocGet('nfcTags', _nfcTagsDoc);
    if (data == null) return [];
    final raw = data['tags'] as List<dynamic>?;
    if (raw == null) return [];
    return raw.map((t) => NfcTagConfig.fromMap(t as Map<String, dynamic>)).toList();
  }

  Future<void> saveNfcEvent(String date, NfcEvent event) async {
    await _db.collection(_nfcEventsCol).doc(date).set({
      'date': date,
      'events': FieldValue.arrayUnion([event.toMap()]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // arrayUnion이라 결과 계산 불가 → 캐시 무효화 (다음 읽기 시 서버에서 새로 로드)
    await LocalCacheService().removeGeneric('nfcEvents_$date');
  }

  Future<List<NfcEvent>> getNfcEvents(String date) async {
    final data = await _cachedDocGet('nfcEvents_$date', '$_nfcEventsCol/$date');
    if (data == null) return [];
    final raw = data['events'] as List<dynamic>?;
    if (raw == null) return [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return NfcEvent(
        id: m['id'] ?? '',
        date: m['date'] ?? '',
        timestamp: m['timestamp'] ?? '',
        role: NfcTagRole.values.firstWhere(
          (r) => r.name == (m['role'] ?? 'wake'),
          orElse: () => NfcTagRole.wake,
        ),
        tagName: m['tagName'] ?? '',
        action: m['action'] as String?,
      );
    }).toList();
  }

  // ══════════════════════════════════════════
  //  v8.5: 수면 관리
  // ══════════════════════════════════════════

  Future<SleepSettings> getSleepSettings() async {
    final data = await _cachedDocGet('sleepSettings', _sleepSettingsDoc);
    if (data == null) return SleepSettings();
    return SleepSettings.fromMap(data);
  }

  Future<void> saveSleepSettings(SleepSettings settings) async {
    await _db.doc(_sleepSettingsDoc).set(settings.toMap());
    LocalCacheService().saveGeneric('sleepSettings', settings.toMap());
  }

  Future<void> saveSleepRecord(String date, SleepRecord record) async {
    await _db.collection(_sleepRecordsCol).doc(date).set({
      ...record.toMap(),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<SleepRecord?> getSleepRecord(String date) async {
    final doc = await _db.collection(_sleepRecordsCol).doc(date).get();
    if (!doc.exists || doc.data() == null) return null;
    return SleepRecord.fromMap(date, doc.data()!);
  }

  // ─── F2: 메모 CRUD ───

  Future<void> saveMemo(Memo memo) async {
    await _db.collection(_memosCol).doc(memo.id).set({
      ...memo.toMap(),
      '_updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMemo(String memoId) async {
    await _db.collection(_memosCol).doc(memoId).delete();
  }

  Future<List<Memo>> getMemos({bool includeCompleted = false}) async {
    Query<Map<String, dynamic>> q = _db.collection(_memosCol)
        .orderBy('pinned', descending: true);
    final snap = await q.get();
    final memos = snap.docs
        .map((d) => Memo.fromMap(d.data()))
        .toList();
    if (!includeCompleted) {
      memos.removeWhere((m) => m.completed);
    }
    memos.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return memos;
  }

  Stream<List<Memo>> watchMemos() {
    return _db.collection(_memosCol)
        .snapshots()
        .map((snap) {
          final memos = snap.docs
              .map((d) => Memo.fromMap(d.data()))
              .where((m) => !m.completed)
              .toList();
          memos.sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return memos;
        });
  }

  // ─── 실시간 스트림 (study 문서) ───

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchStudyData() {
    return _db.doc(_studyDoc).snapshots().map((snap) {
      if (snap.exists && snap.data() != null) {
        // write 보호 중이면 캐시 갱신만 스킵 (snap 자체는 항상 반환)
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[Stream] write-protected, skip cache update (snap still passed)');
          return snap;
        }
        _studyCache = snap.data();
        _studyCacheTime = DateTime.now();
        // ★ SharedPrefs에도 저장 (다음 앱 시작 시 즉시 로딩)
        LocalCacheService().saveStudyData(snap.data()!);
      }
      return snap;
    });
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  // ═══════════════════════════════════════════════════════════
  //  progressGoals (study 문서)
  // ═══════════════════════════════════════════════════════════

  static const String _progressGoalsField = 'progressGoals';

  Future<List<ProgressGoal>> getProgressGoals() async {
    final data = await getStudyData();
    if (data == null || data[_progressGoalsField] == null) return [];
    final raw = data[_progressGoalsField] as List<dynamic>;
    return raw
        .map((g) => ProgressGoal.fromMap(Map<String, dynamic>.from(g as Map)))
        .toList();
  }

  Future<void> saveProgressGoals(List<ProgressGoal> goals) async {
    final goalsList = goals.map((g) => g.toMap()).toList();
    try {
      await _db.doc(_studyDoc).update({
        _progressGoalsField: goalsList,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      try {
        await _db.doc(_studyDoc).set({
          _progressGoalsField: goalsList,
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    // ★ 캐시 즉시 갱신
    _studyCache ??= {};
    _studyCache![_progressGoalsField] = goalsList;
    _studyCacheTime = DateTime.now();
  }

  Future<void> addProgressGoal(ProgressGoal goal) async {
    final goals = await getProgressGoals();
    goals.add(goal);
    await saveProgressGoals(goals);
  }

  Future<void> updateProgressGoal(ProgressGoal updated) async {
    final goals = await getProgressGoals();
    final idx = goals.indexWhere((g) => g.id == updated.id);
    if (idx >= 0) {
      goals[idx] = updated;
    } else {
      goals.add(updated);
    }
    await saveProgressGoals(goals);
  }

  Future<void> deleteProgressGoal(String goalId) async {
    final goals = await getProgressGoals();
    goals.removeWhere((g) => g.id == goalId);
    await saveProgressGoals(goals);
  }

  Stream<List<ProgressGoal>> watchProgressGoals() {
    // ★ 별도 snapshots() 대신 watchStudyData() 스트림 재활용 (gRPC 중복 방지)
    return watchStudyData().map((snap) {
      final data = snap.data();
      if (data == null || data[_progressGoalsField] == null) return [];
      final raw = data[_progressGoalsField] as List<dynamic>;
      return raw
          .map(
              (g) => ProgressGoal.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList();
    });
  }

  // ─── 날짜 기록 이관 ───

  Future<void> migrateDateRecords({
    required String fromDate,
    required String toDate,
    Map<String, String?>? timeRecordOverrides,
  }) async {
    final data = await getStudyData();
    if (data == null) return;

    final batch = <String, dynamic>{};

    // 1) timeRecords 이관
    final trRaw = data[_timeRecordsField] is Map ? Map<String, dynamic>.from(data[_timeRecordsField] as Map) : null;
    if (trRaw != null && trRaw[fromDate] != null) {
      final fromTr = Map<String, dynamic>.from(trRaw[fromDate] as Map);
      if (timeRecordOverrides != null) {
        for (final entry in timeRecordOverrides.entries) {
          if (entry.value != null) {
            fromTr[entry.key] = entry.value;
          } else {
            fromTr.remove(entry.key);
          }
        }
      }
      batch['$_timeRecordsField.$toDate'] = fromTr;
      batch['$_timeRecordsField.$fromDate'] = FieldValue.delete();
    }

    // 2) studyTimeRecords 이관
    final strRaw = data[_studyTimeRecordsField] is Map ? Map<String, dynamic>.from(data[_studyTimeRecordsField] as Map) : null;
    if (strRaw != null && strRaw[fromDate] != null) {
      batch['$_studyTimeRecordsField.$toDate'] = strRaw[fromDate];
      batch['$_studyTimeRecordsField.$fromDate'] = FieldValue.delete();
    }

    if (batch.isNotEmpty) {
      batch['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      batch['lastDevice'] = 'android';
      try {
        await _db.doc(_studyDoc).update(batch).timeout(const Duration(seconds: 5));
      } catch (_) {}
      _studyCache = null; _studyCacheTime = null; // 1회성 이관이므로 캐시 리셋
    }

    // 3) focusCycles 이관 (study 문서)
    final fcRaw = data[_focusCyclesField] is Map ? Map<String, dynamic>.from(data[_focusCyclesField] as Map) : null;
    if (fcRaw != null && fcRaw[fromDate] != null) {
      try {
        await _db.doc(_studyDoc).update({
          '$_focusCyclesField.$toDate': fcRaw[fromDate],
          '$_focusCyclesField.$fromDate': FieldValue.delete(),
        }).timeout(const Duration(seconds: 5));
      } catch (_) {}
      _studyCache = null; _studyCacheTime = null; // 1회성 이관
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  데일리 일기 CRUD — users/{uid}/dailyDiary/{date}
  // ═══════════════════════════════════════════════════════════

  String get _diaryCol => 'users/$_uid/dailyDiary';

  Future<void> saveDailyDiary(DailyDiary diary) async {
    await _db.collection(_diaryCol).doc(diary.date).set(diary.toMap());
  }

  Future<DailyDiary?> getDailyDiary(String date) async {
    final doc = await _db.collection(_diaryCol).doc(date).get();
    if (!doc.exists || doc.data() == null) return null;
    return DailyDiary.fromMap(doc.data()!);
  }

  Future<void> deleteDailyDiary(String date) async {
    await _db.collection(_diaryCol).doc(date).delete();
  }

  Future<List<DailyDiary>> getRecentDiaries({int days = 7}) async {
    final snap = await _db.collection(_diaryCol)
        .orderBy('date', descending: true)
        .limit(days)
        .get();
    return snap.docs
        .where((d) => d.data().isNotEmpty)
        .map((d) => DailyDiary.fromMap(d.data()))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  //  쉬는날 CRUD (study 문서)
  // ═══════════════════════════════════════════════════════════

  static const String _restDaysField = 'restDays';

  Future<List<String>> getRestDays() async {
    final data = await getMetaData();
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
    // ★ 캐시 즉시 갱신
    _studyCache ??= {};
    _studyCache![_restDaysField] = days;
    _studyCacheTime = DateTime.now();
    return !isRest;
  }

  Future<bool> isRestDay(String date) async {
    final days = await getRestDays();
    return days.contains(date);
  }

  Stream<List<String>> watchRestDays() {
    // ★ 별도 snapshots() 대신 watchStudyData() 스트림 재활용 (gRPC 중복 방지)
    return watchStudyData().map((snap) {
      final data = snap.data();
      if (data == null || data[_restDaysField] == null) return <String>[];
      final raw = data[_restDaysField] as List<dynamic>;
      return raw.map((e) => e.toString()).toList();
    });
  }

  // ═══════════════════════════════════════════════════
  // ORDER PORTAL — Generic field access
  // ═══════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getData() async => getStudyData();

  /// 필드 업데이트 — 전부 study 문서에 write
  Future<void> updateField(String field, dynamic value) async {
    // ★ write 보호 마킹
    LocalCacheService().markWrite();
    // ★ 캐시 먼저 갱신
    _studyCache ??= {};
    final parts = field.split('.');
    if (parts.length == 1) {
      _studyCache![field] = value;
    } else {
      Map<String, dynamic> current = _studyCache!;
      for (int i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] == null || current[parts[i]] is! Map) {
          current[parts[i]] = <String, dynamic>{};
        }
        current = current[parts[i]] as Map<String, dynamic>;
      }
      current[parts.last] = value;
    }
    _studyCacheTime = DateTime.now();
    // ★ 로컬 캐시도 갱신
    LocalCacheService().updateStudyField(field, value);
    // ★ fire-and-forget: study doc
    _db.doc(_studyDoc).update({
      field: value,
      'lastModified': FieldValue.serverTimestamp(),
      'lastDevice': 'android',
    }).catchError((e) {
      _db.doc(_studyDoc).set({
        field: value,
        'lastModified': FieldValue.serverTimestamp(),
        'lastDevice': 'android',
      }, SetOptions(merge: true)).catchError((_) {});
    });
    // ★ Phase C: orderData → today 문서에도 동기화
    if (field.startsWith('orderData')) {
      updateTodayField(field, value);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  커스텀 학습과제 CRUD (study 문서)
  // ═══════════════════════════════════════════════════════════

  static const String _customTasksField = 'customStudyTasks';

  Future<List<String>> getCustomStudyTasks(String date) async {
    final data = await getPlanData();
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
    if (index >= 0 && index < tasks.length) {
      tasks[index] = newTask;
      await _saveCustomStudyTasks(date, tasks);
    }
  }

  Future<void> deleteCustomStudyTask(String date, int index) async {
    final tasks = await getCustomStudyTasks(date);
    if (index >= 0 && index < tasks.length) {
      tasks.removeAt(index);
      await _saveCustomStudyTasks(date, tasks);
    }
  }

  Future<void> _saveCustomStudyTasks(String date, List<String> tasks) async {
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

  // ═══════════════════════════════════════════════════════════
  //  한줄 일기 (study 문서)
  // ═══════════════════════════════════════════════════════════

  static const String _dayDiariesField = 'dayDiaries';

  Future<void> saveDayDiary(String date, String content) async {
    try {
      await _db.doc(_studyDoc).update({
        '$_dayDiariesField.$date': content,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      try {
        await _db.doc(_studyDoc).set({
          _dayDiariesField: {date: content},
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  Future<String?> getDayDiary(String date) async {
    final data = await getDiariesData();
    if (data == null || data[_dayDiariesField] == null) return null;
    final all = Map<String, dynamic>.from(data[_dayDiariesField] as Map);
    return all[date] as String?;
  }

  Future<Map<String, String>> getAllDayDiaries() async {
    final data = await getDiariesData();
    if (data == null || data[_dayDiariesField] == null) return {};
    final all = Map<String, dynamic>.from(data[_dayDiariesField] as Map);
    return all.map((k, v) => MapEntry(k, v.toString()));
  }

  // ═══════════════════════════════════════════════════════════
  //  자동 아카이브 — study 문서를 항상 50KB 이하로 유지
  //  7일 이전 데이터 → users/{uid}/archive/{yyyy-MM} 로 이동
  // ═══════════════════════════════════════════════════════════

  static const _archiveFields = [
    'timeRecords', 'studyTimeRecords', 'focusCycles', 'todos',
  ];

  /// 매일 앱 시작 시 백그라운드 실행 — 7일 이전 데이터를 월별 아카이브로 이동
  Future<void> autoArchive() async {
    final prefs = await SharedPreferences.getInstance();
    final today = StudyDateUtils.todayKey();
    final lastArchive = prefs.getString('last_archive_date');
    // 하루에 한 번만 실행
    if (lastArchive == today) return;

    debugPrint('[Archive] 시작...');
    final data = await getStudyData();
    if (data == null) return;

    final cutoffDt = DateTime.now().subtract(const Duration(days: 7));
    final cutoff = DateFormat('yyyy-MM-dd').format(cutoffDt);

    // 아카이브 대상 수집
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
      debugPrint('[Archive] 이동할 데이터 없음');
      return;
    }

    // 1) 월별 아카이브 + history 문서에 동시 저장
    try {
      for (final entry in archiveByMonth.entries) {
        final month = entry.key;
        // archive 문서 (기존)
        await _db.doc('users/$_uid/archive/$month')
            .set(entry.value, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        // history 문서에도 저장 (캘린더 호환)
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
          // history 캐시 무효화
          await LocalCacheService().removeGeneric('history_$month');
        }
        debugPrint('[Archive] $month 저장 OK (archive + history)');
      }
    } catch (e) {
      debugPrint('[Archive] 아카이브 저장 실패 — 중단: $e');
      return; // ★ 아카이브 저장 실패 시 study 문서 삭제하지 않음 (데이터 보호)
    }

    // 2) study 문서에서 오래된 키 삭제
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
      debugPrint('[Archive] study 정리 실패: $e');
      // 아카이브에는 이미 저장됨 — 다음 실행 시 재시도
      return;
    }

    // 3) 인메모리 + 로컬 캐시 동기화
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
    debugPrint('[Archive] 완료: $totalMoved개 날짜 → 월별 아카이브 이동');
  }

  /// 월별 아카이브 로드 (통계/캘린더 화면 전용)
  Future<Map<String, dynamic>?> getArchive(String yearMonth) async {
    // 1) 로컬 캐시
    final cached = LocalCacheService().getGeneric('archive_$yearMonth');
    if (cached != null && cached.isNotEmpty) return cached;

    // 2) Firestore 캐시
    try {
      final cacheDoc = await _db.doc('users/$_uid/archive/$yearMonth')
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheDoc.exists && cacheDoc.data() != null) {
        LocalCacheService().saveGeneric('archive_$yearMonth', cacheDoc.data()!);
        return cacheDoc.data();
      }
    } catch (_) {}

    // 3) 서버
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

  /// study 문서 + history 합산 투두 완료율 (통계 전용)
  Future<Map<String, double>> getCompletionHistoryExtended({int days = 30}) async {
    final result = <String, double>{};

    // 1) today doc (오늘 todos)
    final todayData = await getTodayDoc();
    if (todayData != null) {
      final todayTodos = todayData['todos'];
      if (todayTodos is List) {
        int total = todayTodos.length;
        int done = todayTodos.where((t) => t is Map && t['done'] == true).length;
        if (total > 0) {
          result[todayData['date'] ?? StudyDateUtils.todayKey()] = done / total;
        }
      }
    }

    // 2) history에서 추가 로드
    final now = DateTime.now();
    final startDt = now.subtract(Duration(days: days));
    final months = <String>{};
    var cursor = DateTime(startDt.year, startDt.month);
    while (cursor.isBefore(now) || (cursor.month == now.month && cursor.year == now.year)) {
      months.add(DateFormat('yyyy-MM').format(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    for (final month in months) {
      final history = await getMonthHistory(month);
      if (history == null) continue;
      final daysMap = history['days'] as Map<String, dynamic>? ?? {};
      for (final entry in daysMap.entries) {
        final dateKey = '$month-${entry.key}';
        if (result.containsKey(dateKey)) continue;
        final dayData = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
        if (dayData == null) continue;
        final todos = dayData['todos'];
        if (todos is List && todos.isNotEmpty) {
          final done = todos.where((t) => t is Map && t['done'] == true).length;
          result[dateKey] = done / todos.length;
        }
      }
    }

    // 3) study doc fallback (마이그레이션 전 호환)
    final studyData = _studyCache;
    if (studyData != null) {
      final todosRaw = studyData['todos'] as Map<String, dynamic>? ?? {};
      for (final entry in todosRaw.entries) {
        if (result.containsKey(entry.key)) continue;
        try {
          final td = TodoDaily.fromMap(Map<String, dynamic>.from(entry.value as Map));
          result[entry.key] = td.completionRate;
        } catch (_) {}
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase C: TODAY 문서 — 홈 화면 전용, 1~2KB
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic>? _todayCache2;
  DateTime? _todayCacheTime2;

  /// today 문서 로드 (로컬 캐시 우선)
  Future<Map<String, dynamic>?> getTodayDoc() async {
    // 인메모리 캐시
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

  /// today 문서에 필드 업데이트
  Future<void> updateTodayField(String field, dynamic value) async {
    LocalCacheService().markWrite();

    // 인메모리 캐시 갱신
    _todayCache2 ??= {};
    _setNestedValue(_todayCache2!, field, value);
    _todayCacheTime2 = DateTime.now();

    // 로컬 캐시 갱신
    final localData = LocalCacheService().getGeneric('today') ?? {};
    _setNestedValue(localData, field, value);
    LocalCacheService().saveGeneric('today', localData);

    // Firebase fire-and-forget
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

  /// today 문서 전체 덮어쓰기
  Future<void> setTodayDoc(Map<String, dynamic> data) async {
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
    // FieldValue는 Firestore 전용 — 캐시에서는 수동 처리
    if (value is FieldValue) return; // increment 등은 캐시에서 처리 불가, 스킵
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
      // re-assign to parent to maintain reference
      if (i == 0) {
        map[parts[0]] = current;
      } else {
        final parent = map;
        Map<String, dynamic> nav = parent;
        for (int j = 0; j < i; j++) {
          nav = nav[parts[j]] as Map<String, dynamic>;
        }
        nav[parts[i]] = current;
      }
    }
    current[parts.last] = value;
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase C: HISTORY 문서 — 월별 아카이브
  // ═══════════════════════════════════════════════════════════

  /// 월별 history 문서 로드
  Future<Map<String, dynamic>?> getMonthHistory(String month) async {
    return _cachedDocGet('history_$month', 'users/$_uid/history/$month');
  }

  /// 특정 날짜의 상세 데이터 추출
  Future<Map<String, dynamic>?> getDayDetail(String date) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    final history = await getMonthHistory(month);
    if (history == null) return null;
    final days = history['days'];
    if (days is Map && days.containsKey(day)) {
      return Map<String, dynamic>.from(days[day] as Map);
    }
    return null;
  }

  /// 월간 summary (통계 화면용)
  Future<Map<String, dynamic>?> getMonthSummary(String month) async {
    final history = await getMonthHistory(month);
    if (history == null) return null;
    final s = history['summary'];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  /// 다중 월 summary 병렬 로드
  Future<Map<String, Map<String, dynamic>>> getMultiMonthSummary(List<String> months) async {
    final result = <String, Map<String, dynamic>>{};
    await Future.wait(months.map((m) async {
      final summary = await getMonthSummary(m);
      if (summary != null) result[m] = summary;
    }));
    return result;
  }

  /// history 문서에 날짜 데이터 추가 (merge)
  Future<void> appendDayToHistory(String date, Map<String, dynamic> dayData) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    try {
      await _db.doc('users/$_uid/history/$month').set({
        'month': month,
        'days': {day: dayData},
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      // history 캐시 무효화
      await LocalCacheService().removeGeneric('history_$month');
      debugPrint('[FB] appendDayToHistory: $date OK');
    } catch (e) {
      debugPrint('[FB] appendDayToHistory fail: $e');
    }
  }

  /// history 문서에 포커스 세션 추가
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

  /// monthly summary 재계산
  Future<void> recalculateMonthSummary(String month) async {
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

      // studyTime
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

      // studyTimeRecords fallback (마이그레이션 데이터)
      final str = data['studyTimeRecords'];
      if (st == null && str is Map) {
        final mins = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
        if (mins > 0) {
          totalMinutes += mins;
          activeDays++;
          if (mins > bestMinutes) { bestMinutes = mins; bestDay = day; }
        }
      }

      // todos
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

  // ═══════════════════════════════════════════════════════════
  //  Phase C: 4AM 자동 아카이빙 (일 전환)
  // ═══════════════════════════════════════════════════════════

  Future<void> checkDayRollover() async {
    try {
      final todayData = await getTodayDoc();
      if (todayData == null) return;

      final savedDate = todayData['date'] as String?;
      final currentDate = StudyDateUtils.todayKey();

      if (savedDate == null || savedDate == currentDate) return;

      debugPrint('[Rollover] $savedDate -> $currentDate 아카이빙...');

      // 1) 어제 데이터를 history에 저장
      await appendDayToHistory(savedDate, todayData);

      // 2) summary 재계산
      final month = savedDate.substring(0, 7);
      recalculateMonthSummary(month); // fire-and-forget

      // 3) today 문서 초기화 (orderData는 유지)
      final newToday = <String, dynamic>{
        'date': currentDate,
        'timeRecords': <String, dynamic>{},
        'studyTime': {'total': 0, 'subjects': <String, dynamic>{}},
        'todos': <Map<String, dynamic>>[],
        'orderData': todayData['orderData'] ?? {},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      };
      await setTodayDoc(newToday);

      debugPrint('[Rollover] 아카이빙 완료');
    } catch (e) {
      debugPrint('[Rollover] error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase C: 마이그레이션 — study doc → today + history
  // ═══════════════════════════════════════════════════════════

  Future<void> migrateToTodayHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('migration_today_history_done') == true) return;

    debugPrint('[Migration-C] Today/History 마이그레이션 시작...');

    final studyData = await getStudyData();
    if (studyData == null) {
      debugPrint('[Migration-C] study 데이터 없음 — 빈 today 생성');
      final currentDate = StudyDateUtils.todayKey();
      await setTodayDoc({
        'date': currentDate,
        'timeRecords': {},
        'studyTime': {'total': 0, 'subjects': {}},
        'todos': [],
        'orderData': {},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      });
      await prefs.setBool('migration_today_history_done', true);
      return;
    }

    final todayKey = StudyDateUtils.todayKey();
    final timeRecords = Map<String, dynamic>.from(studyData['timeRecords'] ?? {});
    final studyTimeRecords = Map<String, dynamic>.from(studyData['studyTimeRecords'] ?? {});
    final todos = studyData['todos'] is Map ? Map<String, dynamic>.from(studyData['todos'] as Map) : <String, dynamic>{};
    final focusCycles = studyData['focusCycles'] is Map ? Map<String, dynamic>.from(studyData['focusCycles'] as Map) : <String, dynamic>{};

    // ── 월별 그룹핑 ──
    final Map<String, Map<String, Map<String, dynamic>>> monthlyDays = {};

    void _ensureDay(String dateKey) {
      if (dateKey.length < 10) return;
      final month = dateKey.substring(0, 7);
      final day = dateKey.substring(8, 10);
      monthlyDays.putIfAbsent(month, () => {});
      monthlyDays[month]!.putIfAbsent(day, () => {});
    }

    // timeRecords
    for (final dateKey in timeRecords.keys) {
      if (dateKey == todayKey) continue; // 오늘은 today 문서로
      _ensureDay(dateKey);
      final month = dateKey.substring(0, 7);
      final day = dateKey.substring(8, 10);
      monthlyDays[month]![day]!['timeRecords'] = timeRecords[dateKey];
    }

    // studyTimeRecords → studyTime
    for (final dateKey in studyTimeRecords.keys) {
      if (dateKey == todayKey) continue;
      _ensureDay(dateKey);
      final month = dateKey.substring(0, 7);
      final day = dateKey.substring(8, 10);
      final str = studyTimeRecords[dateKey];
      if (str is Map) {
        final effMin = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
        monthlyDays[month]![day]!['studyTime'] = {'total': effMin, 'subjects': {}};
        monthlyDays[month]![day]!['studyTimeRecords'] = str; // raw도 보관
      }
    }

    // todos
    for (final dateKey in todos.keys) {
      if (dateKey == todayKey) continue;
      _ensureDay(dateKey);
      final month = dateKey.substring(0, 7);
      final day = dateKey.substring(8, 10);
      final td = todos[dateKey];
      if (td is Map) {
        final items = td['items'] as List? ?? [];
        monthlyDays[month]![day]!['todos'] = items;
      }
    }

    // focusCycles
    for (final dateKey in focusCycles.keys) {
      if (dateKey == todayKey) continue;
      _ensureDay(dateKey);
      final month = dateKey.substring(0, 7);
      final day = dateKey.substring(8, 10);
      monthlyDays[month]![day]!['focusSessions'] = focusCycles[dateKey];
    }

    // ── 월별 history 문서 생성 ──
    for (final month in monthlyDays.keys) {
      final mData = monthlyDays[month]!;
      final summary = _calculateMonthlySummary(
        mData.map((k, v) => MapEntry(k, v as dynamic)),
      );
      try {
        await _db.doc('users/$_uid/history/$month').set({
          'month': month,
          'days': mData,
          'summary': summary,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
        debugPrint('[Migration-C] history/$month 저장 (${mData.length}일)');
      } catch (e) {
        debugPrint('[Migration-C] history/$month 실패: $e');
      }
    }

    // ── today 문서 생성 (오늘 데이터) ──
    final todayTimeRecord = timeRecords[todayKey];
    final todayStudyTime = studyTimeRecords[todayKey];
    final todayTodos = todos[todayKey];
    final todayFocus = focusCycles[todayKey];

    int todayEffMin = 0;
    Map<String, dynamic> todaySubjects = {};
    if (todayStudyTime is Map) {
      todayEffMin = (todayStudyTime['effectiveMinutes'] as num?)?.toInt() ?? 0;
    }

    List<Map<String, dynamic>> todayTodoList = [];
    if (todayTodos is Map) {
      final items = todayTodos['items'] as List? ?? [];
      todayTodoList = items.map((i) => i is Map ? Map<String, dynamic>.from(i) : <String, dynamic>{}).toList();
    }

    final todayDoc = <String, dynamic>{
      'date': todayKey,
      'timeRecords': todayTimeRecord is Map ? Map<String, dynamic>.from(todayTimeRecord as Map) : {},
      'studyTime': {
        'total': todayEffMin,
        'subjects': todaySubjects,
      },
      'activeFocus': null,
      'todos': todayTodoList,
      'orderData': studyData['orderData'] is Map ? Map<String, dynamic>.from(studyData['orderData'] as Map) : {},
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    };

    await setTodayDoc(todayDoc);
    debugPrint('[Migration-C] today 문서 생성 완료');

    await prefs.setBool('migration_today_history_done', true);
    debugPrint('[Migration-C] 마이그레이션 완료!');
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase C 진단
  // ═══════════════════════════════════════════════════════════

  Future<void> diagnosePhaseCData() async {
    debugPrint('=== Phase C 진단 시작 ===');

    // 0) Hive 캐시 상태
    final lc = LocalCacheService();
    final hiveStudy = lc.getStudyData();
    debugPrint('[Diag] Hive study: ${hiveStudy != null ? '${hiveStudy.keys.length} keys' : 'null'}');
    final hiveToday = lc.getGeneric('today');
    debugPrint('[Diag] Hive today: ${hiveToday != null ? 'date=${hiveToday['date']}' : 'null'}');
    debugPrint('[Diag] Hive studyCacheAge: ${lc.getStudyCacheAge()}');

    // helper: cache 먼저, 실패 시 server
    Future<DocumentSnapshot<Map<String, dynamic>>?> _getDoc(String path) async {
      try {
        final doc = await _db.doc(path)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (doc.exists) return doc;
      } catch (_) {}
      try {
        return await _db.doc(path).get().timeout(const Duration(seconds: 8));
      } catch (_) {}
      return null;
    }

    // 1) study doc
    try {
      final studyDoc = await _getDoc(_studyDoc);
      if (studyDoc != null && studyDoc.exists) {
        final data = studyDoc.data()!;
        debugPrint('[Diag] study doc 존재: keys=${data.keys.toList()}');
        final tr = data['timeRecords'];
        if (tr is Map) {
          debugPrint('[Diag] study.timeRecords: ${tr.keys.length}개 날짜');
          final dates = tr.keys.toList()..sort();
          debugPrint('[Diag] timeRecords 최근: ${dates.reversed.take(5).toList()}');
        }
        final str = data['studyTimeRecords'];
        if (str is Map) debugPrint('[Diag] study.studyTimeRecords: ${str.keys.length}개 날짜');
        final fc = data['focusCycles'];
        if (fc is Map) debugPrint('[Diag] study.focusCycles: ${fc.keys.length}개 날짜');
        final todos = data['todos'];
        if (todos is Map) debugPrint('[Diag] study.todos: ${todos.keys.length}개 날짜');
      } else {
        debugPrint('[Diag] study doc 없음!');
      }
    } catch (e) {
      debugPrint('[Diag] study doc 읽기 실패: $e');
    }

    // 2) today doc
    try {
      final todayDoc = await _getDoc(_todayDoc2);
      if (todayDoc != null && todayDoc.exists) {
        final data = todayDoc.data()!;
        debugPrint('[Diag] today doc 존재: date=${data['date']}, keys=${data.keys.toList()}');
        debugPrint('[Diag] today.studyTime=${data['studyTime']}');
        final todos = data['todos'];
        debugPrint('[Diag] today.todos count=${todos is List ? todos.length : 'null(${todos.runtimeType})'}');
      } else {
        debugPrint('[Diag] today doc 없음!');
      }
    } catch (e) {
      debugPrint('[Diag] today doc 읽기 실패: $e');
    }

    // 3) history docs (cache → server)
    try {
      QuerySnapshot<Map<String, dynamic>>? historyCol;
      try {
        historyCol = await _db.collection('users/$_uid/history')
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      historyCol ??= await _db.collection('users/$_uid/history')
          .get().timeout(const Duration(seconds: 8));

      debugPrint('[Diag] history 문서 수: ${historyCol.docs.length}');
      for (final doc in historyCol.docs) {
        final data = doc.data();
        final days = data['days'] as Map?;
        final summary = data['summary'] as Map?;
        debugPrint('[Diag] history/${doc.id}: ${days?.keys.length ?? 0}일, summary=${summary != null}');
      }
    } catch (e) {
      debugPrint('[Diag] history 읽기 실패: $e');
    }

    // 4) migration flag
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final done = prefs.getBool('migration_today_history_done');
      debugPrint('[Diag] migration_today_history_done = $done');
    } catch (e) {
      debugPrint('[Diag] prefs 읽기 실패: $e');
    }

    debugPrint('=== Phase C 진단 끝 ===');
  }

  /// history 문서가 비어있으면 마이그레이션 강제 재실행
  Future<void> ensureHistoryExists() async {
    try {
      // cache 먼저 시도 (오프라인 대응)
      QuerySnapshot<Map<String, dynamic>>? historyDocs;
      try {
        historyDocs = await _db.collection('users/$_uid/history')
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      // cache 없으면 서버
      if (historyDocs == null || historyDocs.docs.isEmpty) {
        try {
          historyDocs = await _db.collection('users/$_uid/history')
              .get().timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (historyDocs == null || historyDocs.docs.isEmpty) {
        debugPrint('[Init] history 비어있음! 마이그레이션 강제 재실행');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('migration_today_history_done');
        await migrateToTodayHistory();
      } else {
        debugPrint('[Init] history 존재: ${historyDocs.docs.length}개 월');
      }
    } catch (e) {
      debugPrint('[Init] ensureHistoryExists error: $e');
    }
  }
}