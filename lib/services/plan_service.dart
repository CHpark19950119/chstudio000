/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — Plan · Feedback · Growth Firestore Service
/// study 문서에서 읽기/쓰기
/// ═══════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/plan_models.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';

class PlanService {
  static final PlanService _instance = PlanService._internal();
  factory PlanService() => _instance;
  PlanService._internal();

  final _db = FirebaseFirestore.instance;
  String get _planDoc => FirebaseService.planDocPath;

  // 캐시
  StudyPlan? _cachedPlan;
  DateTime? _planCacheTime;
  GrowthMetrics? _cachedGrowth;
  DateTime? _growthCacheTime;

  // ═══════════════════════════════════════════
  //  학습 계획 (StudyPlan) CRUD
  // ═══════════════════════════════════════════

  Future<StudyPlan?> getStudyPlan({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedPlan != null &&
        _planCacheTime != null &&
        DateTime.now().difference(_planCacheTime!) <
            const Duration(minutes: 5)) {
      return _cachedPlan;
    }

    try {
      // 새 plan 문서에서 먼저 시도
      final data = await FirebaseService().getPlanData();
      if (data == null || data['studyPlan'] == null) return null;

      _cachedPlan = StudyPlan.fromMap(
          Map<String, dynamic>.from(data['studyPlan'] as Map));
      _planCacheTime = DateTime.now();
      return _cachedPlan;
    } catch (e) {
      debugPrint('[PlanService] getStudyPlan 에러: $e');
      return null;
    }
  }

  Future<void> saveStudyPlan(StudyPlan plan) async {
    final data = plan.toMap();
    data['updatedAt'] = DateTime.now().toIso8601String();

    try {
      await _db.doc(_planDoc).update({
        'studyPlan': data,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      });
    } catch (e) {
      await _db.doc(_planDoc).set({
        'studyPlan': data,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true));
    }

    _cachedPlan = plan;
    _planCacheTime = DateTime.now();
  }

  Future<void> updatePeriodStatus(String periodId, String status) async {
    final plan = await getStudyPlan();
    if (plan == null) return;

    final periods = plan.periods.map((p) {
      if (p.id == periodId) {
        return PlanPeriodDyn(
          id: p.id,
          name: p.name,
          start: p.start,
          end: p.end,
          goal: p.goal,
          totalDays: p.totalDays,
          status: status,
          subPeriods: p.subPeriods,
          subjects: p.subjects,
        );
      }
      return p;
    }).toList();

    await saveStudyPlan(StudyPlan(
      version: plan.version,
      title: plan.title,
      updatedBy: 'app',
      annualGoals: plan.annualGoals,
      periods: periods,
      ddays: plan.ddays,
      strategy: plan.strategy,
      scenarios: plan.scenarios,
    ));
  }

  void invalidatePlanCache() {
    _cachedPlan = null;
    _planCacheTime = null;
  }

  // ═══════════════════════════════════════════
  //  일간 피드백 (DailyFeedback) CRUD
  // ═══════════════════════════════════════════

  static String _todayDate() => StudyDateUtils.todayKey();

  Future<DailyFeedback?> getDailyFeedback(String date) async {
    try {
      final data = await FirebaseService().getPlanData();
      if (data == null) return null;

      final feedbacks =
          data['dailyFeedback'] as Map<String, dynamic>?;
      if (feedbacks == null || feedbacks[date] == null) return null;

      return DailyFeedback.fromMap(
          Map<String, dynamic>.from(feedbacks[date] as Map));
    } catch (e) {
      debugPrint('[PlanService] getDailyFeedback 에러: $e');
      return null;
    }
  }

  Future<DailyFeedback?> getTodayFeedback() async {
    return getDailyFeedback(_todayDate());
  }

  Future<void> saveDailyFeedback(DailyFeedback feedback) async {
    final map = feedback.toMap();
    if (map['createdAt'] == null) {
      map['createdAt'] = DateTime.now().toIso8601String();
    }

    try {
      await _db.doc(_planDoc).update({
        'dailyFeedback.${feedback.date}': map,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      });
    } catch (e) {
      await _db.doc(_planDoc).set({
        'dailyFeedback': {feedback.date: map},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true));
    }
  }

  Future<void> saveAiDailyAnalysis(
      String date, AiDailyAnalysis analysis) async {
    try {
      await _db.doc(_planDoc).update({
        'dailyFeedback.$date.aiAnalysis': analysis.toMap(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[PlanService] saveAiDailyAnalysis 에러: $e');
    }
  }

  Future<Map<String, DailyFeedback>> getRecentFeedbacks(
      {int days = 7}) async {
    try {
      final data = await FirebaseService().getPlanData();
      if (data == null || data['dailyFeedback'] == null) return {};

      final raw = data['dailyFeedback'] as Map<String, dynamic>;
      final today = _todayDate();
      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(Duration(days: days)));

      final result = <String, DailyFeedback>{};
      for (final entry in raw.entries) {
        if (entry.key.compareTo(cutoff) >= 0 &&
            entry.key.compareTo(today) <= 0) {
          try {
            result[entry.key] = DailyFeedback.fromMap(
                Map<String, dynamic>.from(entry.value as Map));
          } catch (_) {}
        }
      }
      return result;
    } catch (e) {
      debugPrint('[PlanService] getRecentFeedbacks 에러: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════
  //  주간 리뷰 (WeeklyReview) CRUD
  // ═══════════════════════════════════════════

  static String weekIdForDate(DateTime date) {
    final dayOfYear =
        date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final weekNum = ((dayOfYear - date.weekday + 10) / 7).floor();
    return '${date.year}-W${weekNum.toString().padLeft(2, '0')}';
  }

  Future<WeeklyReview?> getWeeklyReview(String weekId) async {
    try {
      final data = await FirebaseService().getPlanData();
      if (data == null) return null;

      final reviews =
          data['weeklyReview'] as Map<String, dynamic>?;
      if (reviews == null || reviews[weekId] == null) return null;

      return WeeklyReview.fromMap(
          Map<String, dynamic>.from(reviews[weekId] as Map));
    } catch (e) {
      debugPrint('[PlanService] getWeeklyReview 에러: $e');
      return null;
    }
  }

  Future<void> saveWeeklyReview(WeeklyReview review) async {
    try {
      await _db.doc(_planDoc).update({
        'weeklyReview.${review.weekId}': review.toMap(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      });
    } catch (e) {
      await _db.doc(_planDoc).set({
        'weeklyReview': {review.weekId: review.toMap()},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true));
    }
  }

  Future<WeeklyStats> buildWeeklyStats(
      String startDate, String endDate) async {
    final fb = FirebaseService();
    final timeRecords = await fb.getTimeRecords();
    final studyRecords = await fb.getStudyTimeRecords();

    int totalMin = 0, maxMin = 0, minMin = 999999;
    int studyDays = 0;
    List<int> wakeMins = [];

    var d = DateTime.parse(startDate);
    final end = DateTime.parse(endDate);

    while (!d.isAfter(end)) {
      final ds = DateFormat('yyyy-MM-dd').format(d);
      final sr = studyRecords[ds];
      final tr = timeRecords[ds];

      if (sr != null && sr.effectiveMinutes > 0) {
        totalMin += sr.effectiveMinutes;
        if (sr.effectiveMinutes > maxMin) maxMin = sr.effectiveMinutes;
        if (sr.effectiveMinutes < minMin) minMin = sr.effectiveMinutes;
        studyDays++;
      }

      if (tr?.wake != null) {
        try {
          final parts = tr!.wake!.split(':');
          wakeMins.add(int.parse(parts[0]) * 60 + int.parse(parts[1]));
        } catch (_) {}
      }

      d = d.add(const Duration(days: 1));
    }

    if (minMin == 999999) minMin = 0;

    String? avgWake;
    if (wakeMins.isNotEmpty) {
      final avg = wakeMins.reduce((a, b) => a + b) ~/ wakeMins.length;
      avgWake =
          '${(avg ~/ 60).toString().padLeft(2, '0')}:${(avg % 60).toString().padLeft(2, '0')}';
    }

    return WeeklyStats(
      totalStudyMin: totalMin,
      avgDailyMin: studyDays > 0 ? totalMin ~/ studyDays : 0,
      maxDailyMin: maxMin,
      minDailyMin: minMin,
      studyDays: studyDays,
      restDays: 7 - studyDays,
      avgWakeTime: avgWake,
    );
  }

  // ═══════════════════════════════════════════
  //  성장 지표 (GrowthMetrics) CRUD
  // ═══════════════════════════════════════════

  Future<GrowthMetrics?> getGrowthMetrics(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedGrowth != null &&
        _growthCacheTime != null &&
        DateTime.now().difference(_growthCacheTime!) <
            const Duration(minutes: 5)) {
      return _cachedGrowth;
    }

    try {
      final data = await FirebaseService().getPlanData();
      if (data == null || data['growthMetrics'] == null) return null;

      _cachedGrowth = GrowthMetrics.fromMap(
          Map<String, dynamic>.from(data['growthMetrics'] as Map));
      _growthCacheTime = DateTime.now();
      return _cachedGrowth;
    } catch (e) {
      debugPrint('[PlanService] getGrowthMetrics 에러: $e');
      return null;
    }
  }

  Future<void> updateDailySnapshot(
      String date, DailySnapshot snapshot) async {
    try {
      await _db.doc(_planDoc).update({
        'growthMetrics.dailySnapshots.$date': snapshot.toMap(),
        'growthMetrics.lastUpdated': DateTime.now().toIso8601String(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      await _db.doc(_planDoc).set({
        'growthMetrics': {
          'dailySnapshots': {date: snapshot.toMap()},
          'lastUpdated': DateTime.now().toIso8601String(),
        },
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    }

    _cachedGrowth = null;
    _growthCacheTime = null;
  }

  Future<void> updateWeeklySnapshot(
      String weekId, WeeklySnapshot snapshot) async {
    try {
      await _db.doc(_planDoc).update({
        'growthMetrics.weeklySnapshots.$weekId': snapshot.toMap(),
        'growthMetrics.lastUpdated': DateTime.now().toIso8601String(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[PlanService] updateWeeklySnapshot 에러: $e');
    }
  }

  Future<void> addGrowthMilestone(GrowthMilestone milestone) async {
    try {
      await _db.doc(_planDoc).update({
        'growthMetrics.milestones':
            FieldValue.arrayUnion([milestone.toMap()]),
        'growthMetrics.lastUpdated': DateTime.now().toIso8601String(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[PlanService] addGrowthMilestone 에러: $e');
    }
  }

  Future<void> updateLongTermInsight(LongTermInsight insight) async {
    try {
      await _db.doc(_planDoc).update({
        'growthMetrics.longTermInsight': insight.toMap(),
        'growthMetrics.lastUpdated': DateTime.now().toIso8601String(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[PlanService] updateLongTermInsight 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  일일 성장 스냅샷 자동 빌드
  // ═══════════════════════════════════════════

  Future<DailySnapshot> buildDailySnapshot(String date) async {
    final fb = FirebaseService();
    final timeRecords = await fb.getTimeRecords();
    final studyRecords = await fb.getStudyTimeRecords();

    final tr = timeRecords[date];
    final sr = studyRecords[date];
    final feedback = await getDailyFeedback(date);

    final effectiveMin = sr?.effectiveMinutes ?? 0;

    final grade = DailyGrade.calculate(
      date: date,
      wakeTime: tr?.wake,
      studyStartTime: tr?.study,
      effectiveMinutes: effectiveMin,
    );

    final taskComp = feedback?.execution?.completionRate ?? 0.0;
    final focusScore = DailyFeedback.focusQualityScore(
        feedback?.selfAssessment?.focusQuality ?? 'fair');

    int streak = 0;
    var d = DateTime.parse(date);
    for (int i = 0; i < 365; i++) {
      final ds = DateFormat('yyyy-MM-dd').format(d);
      final check = studyRecords[ds];
      if (check != null && check.effectiveMinutes >= 60) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    final consistencyScore = (streak / 30.0).clamp(0.0, 1.0) * 100;

    final growthScore = feedback?.calcGrowthScore(
          effectiveMin: effectiveMin,
          wakeOnTime: grade.wakeScore >= 20,
          bedOnTime: tr?.bedTime != null,
        ) ??
        ((effectiveMin / 480.0).clamp(0.0, 1.0) * 30 +
            grade.wakeScore +
            focusScore);

    return DailySnapshot(
      studyMin: effectiveMin,
      grade: grade.grade,
      gradeScore: grade.totalScore,
      taskCompletion: taskComp,
      habitCompletion: 0,
      wakeScore: grade.wakeScore,
      focusScore: focusScore,
      consistencyScore: consistencyScore,
      growthScore: growthScore,
    );
  }

  // ═══════════════════════════════════════════
  //  패턴 탐지
  // ═══════════════════════════════════════════

  Future<List<DetectedPattern>> detectPatterns({int days = 7}) async {
    final fb = FirebaseService();
    final timeRecords = await fb.getTimeRecords();
    final studyRecords = await fb.getStudyTimeRecords();

    final patterns = <DetectedPattern>[];
    final now = DateTime.now();

    final List<_DayData> recentData = [];
    for (int i = 0; i < days; i++) {
      var d = now.subtract(Duration(days: i));
      if (d.hour < 4) d = d.subtract(const Duration(days: 1));
      final ds = DateFormat('yyyy-MM-dd').format(d);
      final tr = timeRecords[ds];
      final sr = studyRecords[ds];
      recentData.add(_DayData(
        date: ds,
        wakeTime: tr?.wake,
        studyMin: sr?.effectiveMinutes ?? 0,
        hasFeedback: false,
      ));
    }

    int lateWakeStreak = 0;
    for (final d in recentData) {
      if (d.wakeTime != null) {
        try {
          final parts = d.wakeTime!.split(':');
          final h = int.parse(parts[0]);
          if (h >= 8) {
            lateWakeStreak++;
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      } else {
        break;
      }
    }
    if (lateWakeStreak >= 3) {
      patterns.add(DetectedPattern(
        type: 'warning',
        code: 'late_wake_streak',
        desc: '기상 지각 ${lateWakeStreak}일 연속',
        severity: lateWakeStreak >= 5 ? 'high' : 'medium',
      ));
    }

    if (recentData.length >= 3) {
      bool declining = true;
      for (int i = 0; i < recentData.length - 1 && i < 3; i++) {
        if (recentData[i].studyMin >= recentData[i + 1].studyMin) {
          declining = false;
          break;
        }
      }
      if (declining && recentData[0].studyMin < recentData[2].studyMin) {
        patterns.add(DetectedPattern(
          type: 'warning',
          code: 'study_declining',
          desc: '순공시간 3일 연속 하락',
          severity: 'medium',
        ));
      }
    }

    int zeroDays = recentData.where((d) => d.studyMin == 0).length;
    if (zeroDays >= 2) {
      patterns.add(DetectedPattern(
        type: 'concern',
        code: 'zero_study_days',
        desc: '최근 ${days}일 중 학습 없는 날 ${zeroDays}일',
        severity: zeroDays >= 3 ? 'high' : 'low',
      ));
    }

    int studyStreak = 0;
    for (final d in recentData) {
      if (d.studyMin >= 60) {
        studyStreak++;
      } else {
        break;
      }
    }
    if (studyStreak >= 7) {
      patterns.add(DetectedPattern(
        type: 'positive',
        code: 'study_streak',
        desc: '${studyStreak}일 연속 공부 중',
        severity: 'none',
      ));
    }

    if (recentData.length >= 7) {
      final weekAvg = recentData.map((d) => d.studyMin).reduce((a, b) => a + b) ~/
          recentData.length;
      if (recentData[0].studyMin > weekAvg + 60) {
        patterns.add(DetectedPattern(
          type: 'positive',
          code: 'above_avg',
          desc: '오늘 순공이 주간 평균보다 1시간+ 많음',
          severity: 'none',
        ));
      }
    }

    return patterns;
  }
}

class _DayData {
  final String date;
  final String? wakeTime;
  final int studyMin;
  final bool hasFeedback;

  _DayData({
    required this.date,
    this.wakeTime,
    this.studyMin = 0,
    this.hasFeedback = false,
  });
}

class DetectedPattern {
  final String type;
  final String code;
  final String desc;
  final String severity;

  DetectedPattern({
    required this.type,
    required this.code,
    required this.desc,
    this.severity = 'low',
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'code': code,
        'desc': desc,
        'severity': severity,
      };
}
