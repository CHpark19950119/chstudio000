part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Peripheral Data (alarm, location, NFC, memos, progress, diary)
/// ═══════════════════════════════════════════════════════════
extension FirebaseDataOps on FirebaseService {

  // ── Location records ──

  Future<void> saveLocationRecord(String date, LocationRecord record) async {
    await _db.collection(_locationHistoryCol).doc(date).set({
      'date': date,
      'records': FieldValue.arrayUnion([record.toMap()]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<LocationRecord>> getLocationRecords(String date) async {
    // 1) local cache
    final cached = LocalCacheService().getGeneric('locRec_$date');
    if (cached != null && cached['records'] is List) {
      _refreshLocationRecordsInBackground(date);
      return (cached['records'] as List)
          .map((r) => LocationRecord.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    }
    // 2) Firestore cache
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
    // 3) server
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

  // ── Behavior timeline ──

  Future<void> saveBehaviorTimeline(String date, BehaviorTimelineEntry entry) async {
    await _db.collection(_behaviorTimelineCol).doc(date).set({
      'date': date,
      'entries': FieldValue.arrayUnion([entry.toMap()]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<BehaviorTimelineEntry>> getBehaviorTimeline(String date) async {
    final cached = LocalCacheService().getGeneric('timeline_$date');
    if (cached != null && cached['entries'] is List) {
      _refreshBehaviorTimelineInBackground(date);
      return (cached['entries'] as List)
          .map((e) => BehaviorTimelineEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
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

  // ── NFC tags/events ──

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

  // ── Memos ──

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

  // ── Progress goals ──

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
    _studyCache ??= {};
    _studyCache![_progressGoalsField] = goalsList;
    _studyCacheTime = DateTime.now();
  }

  Stream<List<ProgressGoal>> watchProgressGoals() {
    return watchStudyData().map((snap) {
      final data = snap.data();
      if (data == null || data[_progressGoalsField] == null) return [];
      final raw = data[_progressGoalsField] as List<dynamic>;
      return raw
          .map((g) => ProgressGoal.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList();
    });
  }

  // ── Daily diary ──

  Future<void> saveDailyDiary(DailyDiary diary) async {
    await _db.collection(_diaryCol).doc(diary.date).set({
      ...diary.toMap(),
      '_updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DailyDiary?> getDailyDiary(String date) async {
    final doc = await _db.collection(_diaryCol).doc(date).get();
    if (!doc.exists || doc.data() == null) return null;
    return DailyDiary.fromMap(doc.data()!);
  }

  Future<void> deleteDailyDiary(String date) async {
    await _db.collection(_diaryCol).doc(date).delete();
  }
}
