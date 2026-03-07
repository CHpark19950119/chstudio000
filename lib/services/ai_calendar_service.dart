import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'firebase_service.dart';
import '../utils/study_date_utils.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — N1: AI 캘린더 연동 대시보드
/// ═══════════════════════════════════════════════════════════
///
/// v8.11: Anthropic API 실제 호출 → 풍부한 코칭 메시지
///        D-day 다중 표시 (시험 + 마일스톤 + 주간목표)

class AiCalendarService {
  static final AiCalendarService _instance = AiCalendarService._internal();
  factory AiCalendarService() => _instance;
  AiCalendarService._internal();

  final _db = FirebaseFirestore.instance;
  static const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
  String get _calendarDoc => FirebaseService.calendarDocPath; // → study 문서

  // API 키 (웹앱과 동일 — char code 난독화)
  static const List<int> _keyData = [115,107,45,97,110,116,45,97,112,105,48,51,45,70,89,95,55,56,115,80,81,52,45,66,106,103,76,67,54,114,105,101,74,56,73,120,68,113,85,105,113,75,77,66,113,85,82,70,114,76,112,69,65,101,81,115,45,113,115,66,49,77,108,87,106,111,84,97,76,112,68,88,56,90,108,74,52,117,82,120,81,72,65,52,57,55,108,81,90,88,98,80,110,110,122,68,57,73,65,45,120,52,106,76,57,81,65,65];
  static String get _apiKey => String.fromCharCodes(_keyData);
  static String get apiKey => _apiKey; // Todo 통계 AI 분석용

  // 캐시
  CalendarDashboard? _cached;
  DateTime? _lastFetch;
  String? _cachedCoaching;
  DateTime? _lastCoachingFetch;

  /// 대시보드 데이터 가져오기 (5분 캐시)
  Future<CalendarDashboard> getDashboard() async {
    if (_cached != null && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return _cached!;
    }

    final dashboard = await _buildDashboard();
    _cached = dashboard;
    _lastFetch = DateTime.now();
    return dashboard;
  }

  /// 캐시 무효화
  void invalidate() {
    _cached = null;
    _lastFetch = null;
  }

  // ═══════════════════════════════════════════
  //  대시보드 구성
  // ═══════════════════════════════════════════

  Future<CalendarDashboard> _buildDashboard() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    final events = <CalendarEvent>[];
    final memos = <String>[];
    String coaching = '';

    // ── 1. 시험 D-Day (메인) ──
    final examDate = DateTime(2026, 3, 7);
    final dDay = examDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    events.add(CalendarEvent(
      date: '2026-03-07',
      title: '5급 PSAT 시험',
      type: EventType.exam,
      dDay: dDay,
      emoji: '🎯',
      importance: EventImportance.critical,
    ));

    // ── 2. 추가 D-Day 이벤트 (하드코딩 + Firebase) ──
    _addMilestoneEvents(events, now);

    // ── 3. Firebase plan-data 파싱 ──
    try {
      final planEvents = await _parsePlanData(now);
      events.addAll(planEvents);
    } catch (e) {
      debugPrint('[AiCalendar] plan-data 파싱 실패: $e');
    }

    // ── 4. 웹앱 메모 읽기 ──
    try {
      final fetchedMemos = await _fetchMemos(today);
      memos.addAll(fetchedMemos);
    } catch (e) {
      debugPrint('[AiCalendar] 메모 읽기 실패: $e');
    }

    // ── 5. AI API 코칭 메시지 (Anthropic) ──
    try {
      coaching = await _getAiCoaching(now, dDay);
    } catch (e) {
      debugPrint('[AiCalendar] AI 코칭 실패 → fallback: $e');
      try {
        coaching = await _generateFallbackCoaching(now, dDay);
      } catch (e2) {
        debugPrint('[AiCalendar] Fallback 코칭도 실패: $e2');
        coaching = dDay > 0 ? '시험까지 D-$dDay! 오늘도 화이팅!' : '오늘도 최선을 다하세요!';
      }
    }

    // 중요도순 정렬
    events.sort((a, b) {
      final ai = a.importance.index;
      final bi = b.importance.index;
      if (ai != bi) return ai.compareTo(bi);
      return (a.dDay ?? 999).compareTo(b.dDay ?? 999);
    });

    // 숨긴 일정 필터링
    final hidden = await _getHiddenEvents();
    events.removeWhere((e) => hidden.contains(e.title));

    return CalendarDashboard(
      todayEvents: events.where((e) => e.date == today).toList(),
      upcomingEvents: events.where((e) =>
          e.date != today && (e.dDay == null || e.dDay! > 0)).take(5).toList(),
      memos: memos,
      coachingMessage: coaching,
      dDay: dDay,
      lastUpdated: now,
    );
  }

  // ═══════════════════════════════════════════
  //  추가 D-Day 이벤트 (마일스톤/주간목표)
  // ═══════════════════════════════════════════

  void _addMilestoneEvents(List<CalendarEvent> events, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    // 고정 마일스톤
    final milestones = <Map<String, dynamic>>[
      {'date': '2026-02-28', 'title': '2차 중간점검', 'emoji': '📋', 'imp': EventImportance.high},
      {'date': '2026-03-01', 'title': '최종 스퍼트 시작', 'emoji': '🔥', 'imp': EventImportance.high},
      {'date': '2026-03-05', 'title': '실전 모의고사', 'emoji': '📝', 'imp': EventImportance.critical},
      {'date': '2026-03-06', 'title': '시험 전날 (컨디션 조절)', 'emoji': '🧘', 'imp': EventImportance.critical},
    ];

    for (final m in milestones) {
      try {
        final mDate = DateFormat('yyyy-MM-dd').parse(m['date'] as String);
        final diff = mDate.difference(today).inDays;
        if (diff < -1 || diff > 21) continue;
        events.add(CalendarEvent(
          date: m['date'] as String,
          title: m['title'] as String,
          type: EventType.milestone,
          dDay: diff,
          emoji: m['emoji'] as String,
          importance: m['imp'] as EventImportance,
        ));
      } catch (_) {}
    }

    // 주간 목표 (매주 일요일)
    final nextSunday = today.add(Duration(days: (7 - today.weekday) % 7));
    if (nextSunday.difference(today).inDays <= 7 && nextSunday.difference(today).inDays > 0) {
      events.add(CalendarEvent(
        date: DateFormat('yyyy-MM-dd').format(nextSunday),
        title: '주간 리뷰 & 계획',
        type: EventType.milestone,
        dDay: nextSunday.difference(today).inDays,
        emoji: '📊',
        importance: EventImportance.normal,
      ));
    }
  }

  // ═══════════════════════════════════════════
  //  AI API 코칭 (Anthropic Claude)
  // ═══════════════════════════════════════════

  Future<String> _getAiCoaching(DateTime now, int dDay) async {
    // 30분 캐시 (API 비용 절약)
    if (_cachedCoaching != null && _lastCoachingFetch != null &&
        now.difference(_lastCoachingFetch!) < const Duration(minutes: 30)) {
      return _cachedCoaching!;
    }

    // 학습 데이터 수집
    final fb = FirebaseService();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday = DateFormat('yyyy-MM-dd').format(
        now.subtract(const Duration(days: 1)));

    final timeRecords = await fb.getTimeRecords()
        .timeout(const Duration(seconds: 5));
    final studyRecords = await fb.getStudyTimeRecords()
        .timeout(const Duration(seconds: 5));

    // 최근 7일 데이터 집계
    final weekData = <String>[];
    int weekTotal = 0, weekDays = 0;
    for (int i = 1; i <= 7; i++) {
      final d = DateFormat('yyyy-MM-dd').format(
          now.subtract(Duration(days: i)));
      final sr = studyRecords[d];
      final tr = timeRecords[d];
      if (sr != null && sr.effectiveMinutes > 0) {
        final g = DailyGrade.calculate(
          date: d, wakeTime: tr?.wake,
          studyStartTime: tr?.study,
          effectiveMinutes: sr.effectiveMinutes);
        weekData.add('$d: 순공${sr.effectiveMinutes ~/ 60}h${sr.effectiveMinutes % 60}m, '
            '기상${tr?.wake ?? "미기록"}, 등급${g.grade}(${g.totalScore.round()}점)');
        weekTotal += sr.effectiveMinutes;
        weekDays++;
      } else {
        weekData.add('$d: 학습 기록 없음');
      }
    }
    final weekAvg = weekDays > 0 ? weekTotal ~/ weekDays : 0;

    // 오늘 현재 상태
    final todayTR = timeRecords[today];
    final todaySR = studyRecords[today];
    final todayMin = todaySR?.effectiveMinutes ?? 0;

    // API 호출
    final prompt = '''당신은 5급 공무원 PSAT 시험을 준비하는 수험생의 AI 코치입니다.
아래 학습 데이터를 분석하고 오늘의 코칭 메시지를 작성하세요.

[현재 상황]
- 날짜: ${DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(now)}
- 시험: 5급 PSAT (2026-03-07), D-$dDay
- 과목: 자료해석, 언어논리, 상황판단, 헌법, 영어

[오늘]
- 기상: ${todayTR?.wake ?? '미기록'}
- 현재 순공: ${todayMin ~/ 60}h${todayMin % 60}m
- 목표: 8시간

[최근 7일]
${weekData.join('\n')}
- 주간 평균: ${weekAvg ~/ 60}h${weekAvg % 60}m/일
- 학습일: $weekDays일/7일

[요청]
3~4문장으로 코칭 메시지를 작성하세요.
- 구체적 데이터 언급 (어제 공부시간, 주간 평균 등)
- D-day 긴장감 반영
- 오늘 집중해야 할 방향 제안
- 격려 + 현실적 조언 균형
- 이모지 1~2개만 사용
- 존댓말 사용''';

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-5-20250929',
          'max_tokens': 300,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'] as List<dynamic>?;
        if (content != null && content.isNotEmpty) {
          final text = content[0]['text'] as String? ?? '';
          if (text.isNotEmpty) {
            _cachedCoaching = text.trim();
            _lastCoachingFetch = now;
            // SP에도 백업 (오프라인 대비)
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('last_ai_coaching', _cachedCoaching!);
            await prefs.setString('last_ai_coaching_date', today);
            return _cachedCoaching!;
          }
        }
      }
      debugPrint('[AiCalendar] API 응답 오류: ${response.statusCode}');
    } catch (e) {
      debugPrint('[AiCalendar] API 호출 실패: $e');
    }

    // API 실패 시 SP 캐시 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('last_ai_coaching');
      final cachedDate = prefs.getString('last_ai_coaching_date');
      if (cached != null && cachedDate == today) {
        return cached;
      }
    } catch (_) {}

    // 최종 fallback
    return _generateFallbackCoaching(now, dDay);
  }

  // ═══════════════════════════════════════════
  //  Fallback 코칭 (API 실패 시)
  // ═══════════════════════════════════════════

  Future<String> _generateFallbackCoaching(DateTime now, int dDay) async {
    final fb = FirebaseService();
    final yesterday = DateFormat('yyyy-MM-dd').format(
        now.subtract(const Duration(days: 1)));
    final today = DateFormat('yyyy-MM-dd').format(now);

    try {
      final timeRecords = await fb.getTimeRecords();
      final studyRecords = await fb.getStudyTimeRecords();
      final yesterdaySR = studyRecords[yesterday];
      final todayTR = timeRecords[today];

      // 7일 평균
      int weekTotal = 0, weekDays = 0;
      for (int i = 1; i <= 7; i++) {
        final d = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
        final sr = studyRecords[d];
        if (sr != null && sr.effectiveMinutes > 0) {
          weekTotal += sr.effectiveMinutes;
          weekDays++;
        }
      }
      final weekAvg = weekDays > 0 ? weekTotal ~/ weekDays : 0;

      final parts = <String>[];

      // D-day 기반
      if (dDay <= 3) {
        parts.add('🔥 시험 D-$dDay! 마지막 점검 단계입니다.');
        parts.add('새로운 내용보다 기출 복습과 실전 감각에 집중하세요.');
      } else if (dDay <= 7) {
        parts.add('📋 시험까지 $dDay일. 마무리 스퍼트 구간입니다.');
        parts.add('약점 과목 최종 보강 + 시간 배분 연습을 병행하세요.');
      } else if (dDay <= 14) {
        parts.add('📊 D-$dDay. 실전 감각을 끌어올릴 시기입니다.');
      } else {
        parts.add('📖 D-$dDay. 꾸준함이 합격의 열쇠입니다.');
      }

      // 어제 성적
      if (yesterdaySR != null && yesterdaySR.effectiveMinutes > 0) {
        final h = yesterdaySR.effectiveMinutes ~/ 60;
        final m = yesterdaySR.effectiveMinutes % 60;
        if (yesterdaySR.effectiveMinutes >= 480) {
          parts.add('어제 ${h}h${m > 0 ? "${m}m" : ""} 달성, 훌륭합니다!');
        } else {
          parts.add('어제 ${h}h${m > 0 ? "${m}m" : ""}. 오늘은 8시간 목표에 도전합시다.');
        }
      }

      // 주간 평균
      if (weekDays >= 3) {
        parts.add('주간 평균 ${weekAvg ~/ 60}h${weekAvg % 60}m. ${weekAvg >= 360 ? "좋은 페이스입니다!" : "조금 더 끌어올려봅시다."}');
      }

      // 기상
      if (todayTR?.wake != null) {
        parts.add('오늘 ${todayTR!.wake} 기상 — ${_wakeComment(todayTR.wake!)}');
      }

      return parts.join(' ');
    } catch (e) {
      return '📖 D-$dDay. 오늘도 집중해서 공부합시다. 화이팅!';
    }
  }

  String _wakeComment(String wake) {
    try {
      final parts = wake.split(':');
      final h = int.parse(parts[0]);
      if (h < 7) return '일찍 일어났네요! 좋은 시작입니다.';
      if (h <= 7) return '목표 달성! 좋습니다.';
      return '내일은 더 일찍 도전해봅시다.';
    } catch (_) {
      return '좋은 아침입니다.';
    }
  }

  // ═══════════════════════════════════════════
  //  Plan Data 파싱
  // ═══════════════════════════════════════════

  Future<List<CalendarEvent>> _parsePlanData(DateTime now) async {
    final events = <CalendarEvent>[];

    try {
      // ★ Phase B: calendar 문서에서 읽기
      final calDoc = await _db.doc(_calendarDoc).get();
      final data = calDoc.data();
      if (data == null) return events;

      // planSchedule
      final planSchedule = data['planSchedule'] as Map<String, dynamic>?;
      if (planSchedule != null) {
        for (final entry in planSchedule.entries) {
          final dateStr = entry.key;
          final plan = entry.value as Map<String, dynamic>?;
          if (plan == null) continue;

          try {
            final eventDate = DateFormat('yyyy-MM-dd').parse(dateStr);
            final diff = eventDate.difference(DateTime(now.year, now.month, now.day)).inDays;
            if (diff < 0 || diff > 7) continue;

            events.add(CalendarEvent(
              date: dateStr,
              title: plan['title'] as String? ?? '학습 계획',
              type: EventType.study,
              dDay: diff,
              emoji: _planEmoji(plan),
              importance: diff == 0 ? EventImportance.high : EventImportance.normal,
              details: _planDetails(plan),
            ));
          } catch (_) {}
        }
      }

      // planMilestones
      final milestones = data['planMilestones'] as List<dynamic>?;
      if (milestones != null) {
        for (final m in milestones) {
          if (m is! Map<String, dynamic>) continue;
          final dateStr = m['date'] as String?;
          if (dateStr == null) continue;

          try {
            final mDate = DateFormat('yyyy-MM-dd').parse(dateStr);
            final diff = mDate.difference(DateTime(now.year, now.month, now.day)).inDays;
            if (diff < -1 || diff > 14) continue;

            events.add(CalendarEvent(
              date: dateStr,
              title: m['title'] as String? ?? '마일스톤',
              type: EventType.milestone,
              dDay: diff,
              emoji: '📌',
              importance: diff <= 1 ? EventImportance.high : EventImportance.normal,
              details: m['description'] as String?,
            ));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AiCalendar] Firebase planSchedule 읽기 실패: $e');
    }

    // 로컬 일정
    try {
      final prefs = await SharedPreferences.getInstance();
      final localEvents = prefs.getString('local_calendar_events');
      if (localEvents != null) {
        final list = jsonDecode(localEvents) as List<dynamic>;
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final dateStr = item['date'] as String?;
          if (dateStr == null) continue;
          try {
            final eDate = DateFormat('yyyy-MM-dd').parse(dateStr);
            final diff = eDate.difference(DateTime(now.year, now.month, now.day)).inDays;
            if (diff < 0 || diff > 7) continue;
            events.add(CalendarEvent(
              date: dateStr,
              title: item['title'] as String? ?? '일정',
              type: EventType.personal,
              dDay: diff,
              emoji: item['emoji'] as String? ?? '📋',
              importance: EventImportance.normal,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}

    return events;
  }

  String _planEmoji(Map<String, dynamic> plan) {
    final subjects = plan['subjects'] as List<dynamic>?;
    if (subjects != null && subjects.isNotEmpty) {
      final first = subjects.first.toString();
      if (first.contains('자료')) return '📊';
      if (first.contains('언어')) return '📝';
      if (first.contains('상황')) return '🧩';
      if (first.contains('헌법')) return '⚖️';
      if (first.contains('영어')) return '🔤';
    }
    return '📖';
  }

  String? _planDetails(Map<String, dynamic> plan) {
    final subjects = plan['subjects'] as List<dynamic>?;
    if (subjects != null && subjects.isNotEmpty) {
      return subjects.join(', ');
    }
    return plan['description'] as String?;
  }

  // ═══════════════════════════════════════════
  //  메모 읽기
  // ═══════════════════════════════════════════

  Future<List<String>> _fetchMemos(String today) async {
    final memos = <String>[];

    try {
      // ★ Phase B: calendar 문서에서 읽기
      final doc = await _db.doc(_calendarDoc).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // dailyMemos
        final dailyMemos = data['dailyMemos'] as Map<String, dynamic>?;
        if (dailyMemos != null && dailyMemos[today] != null) {
          final todayMemos = dailyMemos[today];
          if (todayMemos is List) {
            for (final m in todayMemos) {
              if (m is String && m.isNotEmpty) memos.add(m);
            }
          } else if (todayMemos is String && todayMemos.isNotEmpty) {
            memos.add(todayMemos);
          }
        }

        // pinnedMemos
        final pinned = data['pinnedMemos'] as List<dynamic>?;
        if (pinned != null) {
          for (final m in pinned) {
            if (m is String && m.isNotEmpty) memos.add('📌 $m');
          }
        }
      }
    } catch (e) {
      debugPrint('[AiCalendar] 메모 읽기 실패: $e');
    }

    return memos;
  }

  // ═══════════════════════════════════════════
  //  메모 저장
  // ═══════════════════════════════════════════

  Future<void> addMemo(String memo) async {
    if (memo.trim().isEmpty) return;
    final today = StudyDateUtils.todayKey();

    await _db.doc(_calendarDoc).set({
      'dailyMemos': {
        today: FieldValue.arrayUnion([memo.trim()]),
      },
    }, SetOptions(merge: true));

    invalidate();
  }

  Future<void> addPinnedMemo(String memo) async {
    if (memo.trim().isEmpty) return;

    await _db.doc(_calendarDoc).set({
      'pinnedMemos': FieldValue.arrayUnion([memo.trim()]),
    }, SetOptions(merge: true));

    invalidate();
  }

  Future<void> addLocalEvent({
    required String date,
    required String title,
    String emoji = '📋',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('local_calendar_events');
    final list = raw != null ? jsonDecode(raw) as List<dynamic> : [];
    list.add({'date': date, 'title': title, 'emoji': emoji});
    await prefs.setString('local_calendar_events', jsonEncode(list));
    invalidate();
  }

  /// 로컬 이벤트 삭제 (title 기준)
  Future<void> deleteLocalEvent(String title) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('local_calendar_events');
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    list.removeWhere((e) => e['title'] == title);
    await prefs.setString('local_calendar_events', jsonEncode(list));
    invalidate();
  }

  /// 마일스톤/하드코딩 일정 숨기기 (SP에 숨김 목록 저장)
  Future<void> hideEvent(String title) async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_events') ?? [];
    if (!hidden.contains(title)) {
      hidden.add(title);
      await prefs.setStringList('hidden_events', hidden);
    }
    invalidate();
  }

  /// 일정 삭제 (유형별 분기)
  Future<void> deleteEvent(CalendarEvent event) async {
    switch (event.type) {
      case EventType.study:
        // planSchedule에서 해당 날짜 제거
        try {
          await _db.doc(_calendarDoc).update({
            'planSchedule.${event.date}': FieldValue.delete(),
          });
        } catch (_) {}
        break;
      case EventType.personal:
        // 로컬 저장소에서 제거
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('local_calendar_events');
          if (raw != null) {
            final list = jsonDecode(raw) as List<dynamic>;
            list.removeWhere((item) =>
              item is Map<String, dynamic> &&
              item['date'] == event.date &&
              item['title'] == event.title);
            await prefs.setString('local_calendar_events', jsonEncode(list));
          }
        } catch (_) {}
        break;
      case EventType.exam:
      case EventType.milestone:
        // 하드코딩 일정은 숨기기 처리
        await hideEvent(event.title);
        return; // invalidate already called in hideEvent
    }
    invalidate();
  }

  /// 숨긴 일정 목록 가져오기
  Future<Set<String>> _getHiddenEvents() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('hidden_events') ?? []).toSet();
  }

  /// 숨긴 일정 복원
  Future<void> restoreAllHiddenEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hidden_events');
    invalidate();
  }

  /// 메모 삭제
  Future<void> deleteMemo(String memo) async {
    final today = StudyDateUtils.todayKey();

    await _db.doc(_calendarDoc).set({
      'dailyMemos': {
        today: FieldValue.arrayRemove([memo]),
      },
    }, SetOptions(merge: true));

    invalidate();
  }

  /// 특정 날짜 메모 삭제
  Future<void> deleteMemoForDate(String date, String memo) async {
    await _db.doc(_calendarDoc).set({
      'dailyMemos': {
        date: FieldValue.arrayRemove([memo]),
      },
    }, SetOptions(merge: true));
    invalidate();
  }

  /// 특정 날짜에 메모 추가
  Future<void> addMemoForDate(String date, String memo) async {
    if (memo.trim().isEmpty) return;
    await _db.doc(_calendarDoc).set({
      'dailyMemos': {
        date: FieldValue.arrayUnion([memo.trim()]),
      },
    }, SetOptions(merge: true));
    invalidate();
  }

  /// 특정 날짜의 메모 가져오기
  Future<List<String>> getMemosForDate(String date) async {
    final memos = <String>[];
    try {
      final doc = await _db.doc(_calendarDoc).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final dailyMemos = data['dailyMemos'] as Map<String, dynamic>?;
        if (dailyMemos != null && dailyMemos[date] != null) {
          final dayMemos = dailyMemos[date];
          if (dayMemos is List) {
            for (final m in dayMemos) {
              if (m is String && m.isNotEmpty) memos.add(m);
            }
          }
        }
        // 고정 메모는 모든 날짜에
        final pinned = data['pinnedMemos'] as List<dynamic>?;
        if (pinned != null) {
          for (final m in pinned) {
            if (m is String && m.isNotEmpty) memos.add('📌 $m');
          }
        }
      }
    } catch (_) {}
    return memos;
  }

  /// 월간 전체 이벤트 (범위 제한 없이)
  Future<List<CalendarEvent>> getAllEventsForMonth(int year, int month) async {
    final events = <CalendarEvent>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. 시험 D-Day
    final examDate = DateTime(2026, 3, 7);
    if (examDate.year == year && examDate.month == month) {
      events.add(CalendarEvent(
        date: '2026-03-07', title: '5급 PSAT 시험',
        type: EventType.exam, dDay: examDate.difference(today).inDays,
        emoji: '🎯', importance: EventImportance.critical));
    }

    // 2. 고정 마일스톤
    final milestones = <Map<String, dynamic>>[
      {'date': '2026-02-28', 'title': '2차 중간점검', 'emoji': '📋', 'imp': EventImportance.high},
      {'date': '2026-03-01', 'title': '최종 스퍼트 시작', 'emoji': '🔥', 'imp': EventImportance.high},
      {'date': '2026-03-05', 'title': '실전 모의고사', 'emoji': '📝', 'imp': EventImportance.critical},
      {'date': '2026-03-06', 'title': '시험 전날', 'emoji': '🧘', 'imp': EventImportance.critical},
    ];
    for (final m in milestones) {
      try {
        final d = DateFormat('yyyy-MM-dd').parse(m['date'] as String);
        if (d.year == year && d.month == month) {
          events.add(CalendarEvent(
            date: m['date'] as String, title: m['title'] as String,
            type: EventType.milestone, dDay: d.difference(today).inDays,
            emoji: m['emoji'] as String, importance: m['imp'] as EventImportance));
        }
      } catch (_) {}
    }

    // 2b. ★ 한국 공휴일/명절/중요 날짜
    for (final h in _getKoreanHolidays(year)) {
      if (h['month'] as int == month) {
        final dateStr = '$year-${month.toString().padLeft(2,'0')}-${(h['day'] as int).toString().padLeft(2,'0')}';
        events.add(CalendarEvent(
          date: dateStr, title: h['title'] as String,
          type: EventType.personal,
          dDay: DateTime(year, month, h['day'] as int).difference(today).inDays,
          emoji: h['emoji'] as String,
          importance: (h['isHoliday'] as bool? ?? false) ? EventImportance.high : EventImportance.normal));
      }
    }

    // 2c. ★ 주요 시험일정 (연도별)
    for (final ex in _getExamSchedule(year)) {
      try {
        final d = DateFormat('yyyy-MM-dd').parse(ex['date'] as String);
        if (d.year == year && d.month == month) {
          events.add(CalendarEvent(
            date: ex['date'] as String, title: ex['title'] as String,
            type: EventType.exam,
            dDay: d.difference(today).inDays,
            emoji: '📋', importance: EventImportance.critical));
        }
      } catch (_) {}
    }

    // 3. Firebase planSchedule + planMilestones
    try {
      final doc = await _db.doc(_calendarDoc).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final planSchedule = data['planSchedule'] as Map<String, dynamic>?;
        if (planSchedule != null) {
          for (final entry in planSchedule.entries) {
            try {
              final d = DateFormat('yyyy-MM-dd').parse(entry.key);
              if (d.year != year || d.month != month) continue;
              final plan = entry.value as Map<String, dynamic>?;
              if (plan == null) continue;
              events.add(CalendarEvent(
                date: entry.key,
                title: plan['title'] as String? ?? '학습 계획',
                type: EventType.study,
                dDay: d.difference(today).inDays,
                emoji: _planEmoji(plan),
                importance: EventImportance.normal,
                details: _planDetails(plan)));
            } catch (_) {}
          }
        }
        final ms = data['planMilestones'] as List<dynamic>?;
        if (ms != null) {
          for (final m in ms) {
            if (m is! Map<String, dynamic>) continue;
            final dateStr = m['date'] as String?;
            if (dateStr == null) continue;
            try {
              final d = DateFormat('yyyy-MM-dd').parse(dateStr);
              if (d.year != year || d.month != month) continue;
              events.add(CalendarEvent(
                date: dateStr, title: m['title'] as String? ?? '마일스톤',
                type: EventType.milestone,
                dDay: d.difference(today).inDays,
                emoji: '📌', importance: EventImportance.normal,
                details: m['description'] as String?));
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 3b. ★ 캘린더 이벤트 (식사 기록 등)
    try {
      final doc = await _db.doc(_calendarDoc).get();
      if (doc.exists && doc.data() != null) {
        final calEvents = doc.data()!['calendarEvents'] as Map<String, dynamic>?;
        if (calEvents != null) {
          for (final dateEntry in calEvents.entries) {
            final dateStr = dateEntry.key;
            try {
              final d = DateFormat('yyyy-MM-dd').parse(dateStr);
              if (d.year != year || d.month != month) continue;
              final dayEvents = dateEntry.value as Map<String, dynamic>?;
              if (dayEvents == null) continue;
              for (final ev in dayEvents.values) {
                if (ev is! Map<String, dynamic>) continue;
                // ★ 1-A Fix: 식사 기록 필터링 (meal_photo_service가 저장한 항목 제외)
                final evType = ev['type'] as String? ?? '';
                final evEmoji = ev['emoji'] as String? ?? '';
                final evTitle = ev['title'] as String? ?? '';
                if (evType == 'meal' || evEmoji == '🍽️' ||
                    evTitle.contains('식사') || evTitle.contains('meal')) {
                  continue; // 식사 기록은 이벤트에서 제외
                }
                events.add(CalendarEvent(
                  date: dateStr,
                  title: evTitle.isNotEmpty ? evTitle : '일정',
                  type: EventType.personal,
                  dDay: d.difference(today).inDays,
                  emoji: evEmoji.isNotEmpty ? evEmoji : '📋',
                  importance: EventImportance.normal,
                ));
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 4. 로컬 이벤트
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('local_calendar_events');
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final dateStr = item['date'] as String?;
          if (dateStr == null) continue;
          try {
            final d = DateFormat('yyyy-MM-dd').parse(dateStr);
            if (d.year != year || d.month != month) continue;
            events.add(CalendarEvent(
              date: dateStr, title: item['title'] as String? ?? '일정',
              type: EventType.personal,
              dDay: d.difference(today).inDays,
              emoji: item['emoji'] as String? ?? '📋',
              importance: EventImportance.normal));
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 숨김 처리
    final hidden = await _getHiddenEvents();
    events.removeWhere((e) => hidden.contains(e.title));

    return events;
  }

  /// 월간 메모 날짜별 맵
  Future<Map<String, List<String>>> getAllMemosForMonth(int year, int month) async {
    final result = <String, List<String>>{};
    try {
      final doc = await _db.doc(_calendarDoc).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final dailyMemos = data['dailyMemos'] as Map<String, dynamic>?;
        if (dailyMemos != null) {
          for (final entry in dailyMemos.entries) {
            try {
              final d = DateFormat('yyyy-MM-dd').parse(entry.key);
              if (d.year != year || d.month != month) continue;
              final memos = <String>[];
              if (entry.value is List) {
                for (final m in entry.value) {
                  if (m is String && m.isNotEmpty) memos.add(m);
                }
              }
              if (memos.isNotEmpty) result[entry.key] = memos;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// 고정 메모 삭제
  Future<void> deletePinnedMemo(String memo) async {
    await _db.doc(_calendarDoc).set({
      'pinnedMemos': FieldValue.arrayRemove([memo]),
    }, SetOptions(merge: true));

    invalidate();
  }

  // ═══════════════════════════════════════════
  //  ★ 한국 공휴일/명절 데이터
  // ═══════════════════════════════════════════

  /// 고정 공휴일 (매년 동일) + 연도별 음력 명절
  static List<Map<String, dynamic>> _getKoreanHolidays(int year) {
    final holidays = <Map<String, dynamic>>[
      // ── 고정 공휴일 ──
      {'month': 1, 'day': 1, 'title': '신정', 'emoji': '🎍', 'isHoliday': true},
      {'month': 3, 'day': 1, 'title': '삼일절', 'emoji': '🇰🇷', 'isHoliday': true},
      {'month': 5, 'day': 5, 'title': '어린이날', 'emoji': '🧒', 'isHoliday': true},
      {'month': 6, 'day': 6, 'title': '현충일', 'emoji': '🪖', 'isHoliday': true},
      {'month': 8, 'day': 15, 'title': '광복절', 'emoji': '🇰🇷', 'isHoliday': true},
      {'month': 10, 'day': 3, 'title': '개천절', 'emoji': '🇰🇷', 'isHoliday': true},
      {'month': 10, 'day': 9, 'title': '한글날', 'emoji': '🔤', 'isHoliday': true},
      {'month': 12, 'day': 25, 'title': '크리스마스', 'emoji': '🎄', 'isHoliday': true},
      // ── 기념일 (비공휴일) ──
      {'month': 2, 'day': 14, 'title': '발렌타인데이', 'emoji': '💝', 'isHoliday': false},
      {'month': 3, 'day': 14, 'title': '화이트데이', 'emoji': '🤍', 'isHoliday': false},
      {'month': 5, 'day': 8, 'title': '어버이날', 'emoji': '🌹', 'isHoliday': false},
      {'month': 5, 'day': 15, 'title': '스승의날', 'emoji': '📚', 'isHoliday': false},
    ];

    // ── 음력 명절 (연도별 양력 변환) ──
    if (year == 2025) {
      holidays.addAll([
        {'month': 1, 'day': 28, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 1, 'day': 29, 'title': '설날', 'emoji': '🧧', 'isHoliday': true},
        {'month': 1, 'day': 30, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 5, 'day': 5, 'title': '부처님 오신 날', 'emoji': '🪷', 'isHoliday': true},
        {'month': 10, 'day': 5, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
        {'month': 10, 'day': 6, 'title': '추석', 'emoji': '🌕', 'isHoliday': true},
        {'month': 10, 'day': 7, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
      ]);
    } else if (year == 2026) {
      holidays.addAll([
        {'month': 2, 'day': 16, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 2, 'day': 17, 'title': '설날', 'emoji': '🧧', 'isHoliday': true},
        {'month': 2, 'day': 18, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 5, 'day': 24, 'title': '부처님 오신 날', 'emoji': '🪷', 'isHoliday': true},
        {'month': 9, 'day': 24, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
        {'month': 9, 'day': 25, 'title': '추석', 'emoji': '🌕', 'isHoliday': true},
        {'month': 9, 'day': 26, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
      ]);
    } else if (year == 2027) {
      holidays.addAll([
        {'month': 2, 'day': 6, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 2, 'day': 7, 'title': '설날', 'emoji': '🧧', 'isHoliday': true},
        {'month': 2, 'day': 8, 'title': '설날 연휴', 'emoji': '🧧', 'isHoliday': true},
        {'month': 5, 'day': 13, 'title': '부처님 오신 날', 'emoji': '🪷', 'isHoliday': true},
        {'month': 10, 'day': 14, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
        {'month': 10, 'day': 15, 'title': '추석', 'emoji': '🌕', 'isHoliday': true},
        {'month': 10, 'day': 16, 'title': '추석 연휴', 'emoji': '🌕', 'isHoliday': true},
      ]);
    }
    return holidays;
  }

  /// 주요 시험 일정
  static List<Map<String, String>> _getExamSchedule(int year) {
    if (year == 2026) {
      return [
        {'date': '2026-03-07', 'title': '5급 PSAT'},
        {'date': '2026-04-05', 'title': '국가직 7급 필기'},
        {'date': '2026-06-13', 'title': '지방직 7급 필기'},
        {'date': '2026-06-28', 'title': '국회8급 필기'},
        {'date': '2026-07-12', 'title': '입법고시 1차'},
      ];
    }
    return [];
  }
}

// ═══════════════════════════════════════════
//  데이터 모델
// ═══════════════════════════════════════════

enum EventType { exam, study, milestone, personal }
enum EventImportance { critical, high, normal, low }

class CalendarEvent {
  final String date;
  final String title;
  final EventType type;
  final int? dDay;
  final String emoji;
  final EventImportance importance;
  final String? details;

  CalendarEvent({
    required this.date,
    required this.title,
    required this.type,
    this.dDay,
    required this.emoji,
    required this.importance,
    this.details,
  });
}

class CalendarDashboard {
  final List<CalendarEvent> todayEvents;
  final List<CalendarEvent> upcomingEvents;
  final List<String> memos;
  final String coachingMessage;
  final int dDay;
  final DateTime lastUpdated;

  CalendarDashboard({
    required this.todayEvents,
    required this.upcomingEvents,
    required this.memos,
    required this.coachingMessage,
    required this.dDay,
    required this.lastUpdated,
  });
}