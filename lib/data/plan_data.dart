/// ═══════════════════════════════════════════════════════════════
/// 학습 계획 데이터 — 2차 중간평가(2/28) 결과 반영 v4.0
/// Firebase 연동 없이 정적 데이터로 관리 (plan 변경 시 이 파일 수정)
/// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../models/order_models.dart';

// ═══════════════════════════════════════════════
//  모델 클래스
// ═══════════════════════════════════════════════

class PlanDDay {
  final int id;
  final String name;
  final String date;
  final bool enabled;
  final Color color;
  final bool primary;
  const PlanDDay({required this.id, required this.name, required this.date,
    this.enabled = true, this.color = const Color(0xFF6366F1), this.primary = false});
  int get daysLeft {
    final now = DateTime.now();
    final target = DateTime.parse(date);
    return target.difference(DateTime(now.year, now.month, now.day)).inDays;
  }
  bool get isPast => daysLeft < 0;
  String get dDayLabel =>
      daysLeft == 0 ? 'D-Day' : daysLeft > 0 ? 'D-$daysLeft' : 'D+${-daysLeft}';
}

class PlanMilestone {
  final String date;
  final String title;
  final String type;
  const PlanMilestone({required this.date, required this.title, this.type = 'exam'});
}

class PlanSubPeriod {
  final String id, name, start, end;
  final int days;
  final String? instructor;
  final String primaryGoal;
  final List<String> goals, checkpoints;
  const PlanSubPeriod({required this.id, required this.name, required this.start,
    required this.end, required this.days, this.instructor, required this.primaryGoal,
    this.goals = const [], this.checkpoints = const []});
  bool containsDate(String ds) => ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;
}

class PlanSubject {
  final String title, tag;
  final Color color;
  final String? instructor, period;
  final List<String> curriculum;
  const PlanSubject({required this.title, required this.tag, required this.color,
    this.instructor, this.period, this.curriculum = const []});
}

class PlanDailyPlan {
  final String date;
  final String? title, label, tag, coaching, checkpoint;
  final List<String> tasks;
  const PlanDailyPlan({required this.date, this.title, this.label, this.tag,
    this.coaching, this.tasks = const [], this.checkpoint});
}

class PlanEvaluation {
  final String date, title;
  final String? result, strategy;
  final List<String> causes;
  const PlanEvaluation({required this.date, required this.title,
    this.result, this.causes = const [], this.strategy});
}

class PlanScenario {
  final String id, condition, trigger, nextPeriod;
  final List<String> actions;
  const PlanScenario({required this.id, required this.condition, required this.trigger,
    this.actions = const [], required this.nextPeriod});
}

class PlanPeriod {
  final String id, name, start, end, goal;
  final int totalDays;
  final List<PlanSubPeriod> subPeriods;
  final List<PlanSubject> subjects;
  const PlanPeriod({required this.id, required this.name, required this.start,
    required this.end, required this.totalDays, required this.goal,
    this.subPeriods = const [], this.subjects = const []});
  bool containsDate(String ds) => ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;
  PlanSubPeriod? subPeriodForDate(String ds) {
    for (final sp in subPeriods) { if (sp.containsDate(ds)) return sp; }
    return null;
  }
  double progressForDate(String ds) {
    final s = DateTime.parse(start), e = DateTime.parse(end), d = DateTime.parse(ds);
    final total = e.difference(s).inDays;
    if (total <= 0) return 0;
    return (d.difference(s).inDays / total).clamp(0.0, 1.0);
  }
}

// ═══════════════════════════════════════════════
//  정적 데이터 — 2차 중간평가 반영
// ═══════════════════════════════════════════════

class StudyPlanData {
  StudyPlanData._();

  static const String title = '2026년 통합 수험 로드맵 v4.0';
  static const String version = '4.0';
  static const String description = '2차 중간평가 결과 반영 — 7급 1차 합격 + 2차 준비 주목적 전환';

  static const List<String> targets = [
    '7급 외무영사직 1차 합격 (핵심 목표)',
    '7급 2차 전공 완성',
    '경제학 병행 (직렬 변경 대비)',
    '5급 1차 응시 (최대한 점수 확보)',
    '입법고시 1차 응시',
  ];

  static const Map<String, String> annualGoals = {
    'A': '7급 1차 합격: 연간 최우선 핵심 목표',
    'B': '7급 2차 전공 완성: 연중 병행 + 하반기 집중',
    'C': '경제학: 직렬 변경 대비 매일 장기 투입',
    'D': '생활 루틴 안정화: 기상/취침 루틴 3월 3주까지 완성',
  };

  /// ★ 전략 방향 (2차 중간평가 결론)
  static const Map<String, String> strategicDirection = {
    'diagnosis': '시나리오A(5급1차 점수확보) 불가능 판단 — 분기점 가치 사라짐',
    'newPrimary': '7급 1차 합격과 2차 준비를 주 목적으로 전환',
    'economics': '경제학 공부 병행 필수 (직렬 변경 대비)',
    'routine': '안정적인 생활 루틴 선행 확보 (최우선)',
    'rebuild': '5급 1차 이후 전면 리빌딩 개시',
  };

  /// ★ 리빌딩 계획 상세
  static const Map<String, List<String>> rebuildPlan = {
    'macro': [
      '상황판단 커리큘럼 진입 및 PSAT 약점 보완',
      '경제학 인강 수강 및 매일 일정량 학습 루틴화',
      '7급 외무영사직 2차 과목 인강 수강 시작',
    ],
    'micro': [
      '고시닷컴 상황판단 인강 진행 (~6월 초)',
      'PSAT 자료해석/언어논리 약점 분석 (~6월 초)',
      '7급 외무영사직 과목별 공부법 수립',
      '경제학 세부 커리큘럼 확정',
    ],
    'concrete': [
      '3월 3주까지 기상/취침 루틴 완성 (최우선 과제)',
      '학습 및 인식적 문제점 매일 분석 및 교정 루틴',
      '학습 능력 진단에 근거하여 7월까지 2차 투입 시간 결정',
      '경제학은 매일 투입하는 장기 과제로 설정',
    ],
  };

  // ── 태그 ──
  static const Map<String, String> tagLabels = {
    'data': '자료해석', 'lang': '언어논리', 'sit': '상황판단',
    'test': '실전', 'exam': '시험', 'rest': '휴식',
    'econ': '경제학', 'rebuild': '리빌딩', 'routine': '루틴',
  };
  static const Map<String, Color> tagColors = {
    'data': Color(0xFF3B82F6), 'lang': Color(0xFF10B981), 'sit': Color(0xFFF59E0B),
    'test': Color(0xFF8B5CF6), 'exam': Color(0xFFEF4444), 'rest': Color(0xFF64748B),
    'econ': Color(0xFF06B6D4), 'rebuild': Color(0xFFEC4899), 'routine': Color(0xFF84CC16),
  };

  // ── D-Day ──
  static const List<PlanDDay> ddays = [
    PlanDDay(id: 1, name: '입법고시 1차', date: '2026-02-28', color: Color(0xFF8B5CF6)),
    PlanDDay(id: 2, name: '5급 1차 PSAT', date: '2026-03-07', color: Color(0xFF3B82F6)),
    PlanDDay(id: 3, name: '국회 8급 필기', date: '2026-03-21', color: Color(0xFF6366F1)),
    PlanDDay(id: 4, name: '7급 1차 PSAT', date: '2026-07-18', color: Color(0xFF22C55E), primary: true),
    PlanDDay(id: 5, name: '지방직 7급', date: '2026-10-31', color: Color(0xFFF59E0B)),
  ];

  // ── 마일스톤 ──
  static const List<PlanMilestone> milestones = [
    PlanMilestone(date: '2026-02-28', title: '입법고시 1차', type: 'exam'),
    PlanMilestone(date: '2026-02-28', title: '★ 2차 중간평가 · 전략 전환', type: 'milestone'),
    PlanMilestone(date: '2026-03-07', title: '5급 공채 1차', type: 'exam'),
    PlanMilestone(date: '2026-03-15', title: '기상/취침 루틴 1차 목표', type: 'milestone'),
    PlanMilestone(date: '2026-03-21', title: '국회 8급 필기', type: 'exam'),
    PlanMilestone(date: '2026-03-22', title: '★ 리빌딩 본격 개시', type: 'milestone'),
    PlanMilestone(date: '2026-06-15', title: '7급 1차 준비도 점검', type: 'milestone'),
    PlanMilestone(date: '2026-07-18', title: '7급 1차 PSAT', type: 'exam'),
    PlanMilestone(date: '2026-10-31', title: '지방직 7급 필기', type: 'exam'),
  ];

  // ═══ 기간 (Period) A ~ D ═══

  static final List<PlanPeriod> periods = [
    PlanPeriod(id: 'A', name: '5급 1차 PSAT 집중', start: '2026-02-01', end: '2026-03-07', totalDays: 35,
      goal: 'PSAT 구조 완성 + 약점 식별, 기출 아카이브 구축',
      subPeriods: const [
        PlanSubPeriod(id: 'A-1', name: '자료해석 초집중', start: '2026-02-01', end: '2026-02-10', days: 10, instructor: '조훈',
          primaryGoal: '조훈 강사 커리큘럼 1회독 완주', goals: ['단권화 핵심 문제 + 특강자료 흡수', '개인 약점 유형 정리']),
        PlanSubPeriod(id: 'A-2', name: '전략수정: 자해+언논 올인', start: '2026-02-10', end: '2026-02-20', days: 10, instructor: '조훈/신성우',
          primaryGoal: '자료해석 문제집+기출 병행, 언어논리 첫 90분 루틴 정착'),
        PlanSubPeriod(id: 'A-3', name: '자해·언논 집중 마무리', start: '2026-02-20', end: '2026-02-28', days: 8, instructor: '조훈/신성우',
          primaryGoal: '기출 아카이브 완성 + 2차 중간평가'),
        PlanSubPeriod(id: 'A-4', name: '기출 집중 풀이', start: '2026-03-01', end: '2026-03-07', days: 7,
          primaryGoal: '기출 세트 매일 풀이, 시간 배분 고정 훈련'),
      ],
      subjects: const [
        PlanSubject(title: '📊 자료해석', tag: 'data', color: Color(0xFF3B82F6), instructor: '조훈'),
        PlanSubject(title: '📖 언어논리', tag: 'lang', color: Color(0xFF10B981), instructor: '신성우'),
        PlanSubject(title: '🧩 상황판단', tag: 'sit', color: Color(0xFFF59E0B), instructor: '이지은', period: '보류'),
      ],
    ),

    PlanPeriod(id: 'B', name: '리빌딩 + 기초 확립', start: '2026-03-08', end: '2026-06-15', totalDays: 99,
      goal: '생활 루틴 안정화 + 상황판단 진입 + 경제학 루틴 + 7급 2차 인강 착수',
      subPeriods: const [
        PlanSubPeriod(id: 'B-1', name: '루틴 복구 + 자기반성', start: '2026-03-08', end: '2026-03-22', days: 14,
          primaryGoal: '기상/취침 루틴 안정화, 학습 문제점 분석 루틴 정착',
          goals: ['기상 목표시간 확립 → 3주 내 완성', '매일 학습/인식 문제점 분석', '경제학 입문 인강 착수 (매일 1시간)', '상황판단 기초 인강 착수'],
          checkpoints: ['기상 루틴 정착률 80%+', '경제학 매일 1시간 투입', '자기반성 기록 매일 작성']),
        PlanSubPeriod(id: 'B-2', name: '상황판단 + PSAT 약점 보완', start: '2026-03-22', end: '2026-05-15', days: 54,
          primaryGoal: '상황판단 커리큘럼 완주 + 자해/언논 약점 분석 완료',
          goals: ['고시닷컴 상황판단 인강 전체 수강', '자해/언논 약점 재분석', '경제학 매일 1시간', '7급 과목별 공부법 수립']),
        PlanSubPeriod(id: 'B-3', name: '7급 2차 인강 착수', start: '2026-05-15', end: '2026-06-15', days: 31,
          primaryGoal: '7급 2차 주요 과목 인강 착수 + 경제학 진행',
          goals: ['국제법/국제정치학 인강 1회독 착수', '경제학 기본서 1회독 진행', '시간 배분 결정']),
      ],
      subjects: const [
        PlanSubject(title: '🧩 상황판단', tag: 'sit', color: Color(0xFFF59E0B), instructor: '이지은',
          curriculum: ['기초과정', '기본과정', '유형별과정', '기출분석']),
        PlanSubject(title: '💰 경제학', tag: 'econ', color: Color(0xFF06B6D4),
          period: '매일 1시간 장기 투입', curriculum: ['입문 인강', '기본서 1회독', '문제풀이']),
        PlanSubject(title: '📚 국제법', tag: 'law', color: Color(0xFF8B5CF6)),
        PlanSubject(title: '🌍 국제정치학', tag: 'politics', color: Color(0xFFEC4899)),
      ],
    ),

    const PlanPeriod(id: 'C', name: '7급 1차 PSAT 파이널', start: '2026-06-15', end: '2026-07-18', totalDays: 33,
      goal: '7급 1차 합격 — PSAT 집중, 모의고사 실전 훈련',
      subPeriods: [
        PlanSubPeriod(id: 'C-1', name: 'PSAT 모의고사 훈련', start: '2026-06-15', end: '2026-07-05', days: 20,
          primaryGoal: '모의고사 실전 응시 + 문제 풀이 경험 극대화',
          goals: ['모의고사 신청 및 실전 응시', '최대한 많은 문풀 경험 축적', '각 과목당 단권화 자료 완성']),
        PlanSubPeriod(id: 'C-2', name: '최종 점검 + 컨디션', start: '2026-07-05', end: '2026-07-18', days: 13,
          primaryGoal: '취약 유형 최종 보완 + 컨디션 최적화'),
      ],
    ),

    const PlanPeriod(id: 'D', name: '7급 2차 전공 심화', start: '2026-07-19', end: '2026-10-15', totalDays: 88,
      goal: '7급 2차 전공 최종 완성 + 경제학 실력 확립'),
  ];

  // ═══ 일일 계획 ═══
  static const List<PlanDailyPlan> dailyPlans = [
    PlanDailyPlan(date: '2026-02-28', title: '★ 2차 중간평가 · 전략 전환', label: 'D-7', tag: 'exam',
      coaching: '2차 중간평가일. 5급 시나리오A 불가 → 7급 주 목적 전환.',
      tasks: ['2차 중간평가 수행', '전략 방향 전환 확정', '입법고시 1차 응시'],
      checkpoint: '★ 2차 중간평가 · 전략 전환점'),
    PlanDailyPlan(date: '2026-03-01', title: '자해 기출 종합 1', label: 'D-6', tag: 'data'),
    PlanDailyPlan(date: '2026-03-02', title: '언논 기출+리트 1', label: 'D-5', tag: 'lang'),
    PlanDailyPlan(date: '2026-03-03', title: '자해 기출 종합 2', label: 'D-4', tag: 'data'),
    PlanDailyPlan(date: '2026-03-04', title: '언논 기출+리트 2', label: 'D-3', tag: 'lang'),
    PlanDailyPlan(date: '2026-03-05', title: '최종 점검', label: 'D-2', tag: 'data'),
    PlanDailyPlan(date: '2026-03-06', title: '시험 전날', label: 'D-1', tag: 'rest', checkpoint: '컨디션 최적화'),
    PlanDailyPlan(date: '2026-03-07', title: '5급 1차 시험', label: 'D-Day', tag: 'exam', checkpoint: '5급 1차 완료 → 리빌딩 개시'),
    PlanDailyPlan(date: '2026-03-08', title: '리빌딩 D-1: 루틴 설계', tag: 'rebuild',
      coaching: '리빌딩 첫날. 기상/취침 목표 시간 확정, 경제학 인강 탐색.',
      tasks: ['기상/취침 목표 시간 설정', '경제학 인강 커리 선정', '상황판단 인강 신청'],
      checkpoint: '★ 리빌딩 개시'),
    PlanDailyPlan(date: '2026-03-09', title: '경제학 입문 시작', tag: 'econ', tasks: ['경제학 인강 1시간', '상황판단 기초 1강']),
    PlanDailyPlan(date: '2026-03-10', title: '상황판단 기초 + 루틴', tag: 'sit', tasks: ['상황판단 기초 2강', '경제학 인강 1시간']),
    PlanDailyPlan(date: '2026-03-15', title: '루틴 1차 점검', tag: 'routine', checkpoint: '기상/취침 루틴 1차 목표'),
    PlanDailyPlan(date: '2026-03-22', title: 'B-1 완료 점검', tag: 'rebuild', checkpoint: 'B-1 완료 · 루틴 정착률 확인'),
  ];

  // ═══ 평가 ═══
  static const List<PlanEvaluation> evaluations = [
    PlanEvaluation(date: '2026-02-15', title: '기간A 중간점검', result: '계획 달성 실패',
      causes: ['절대적 공부량 부족', '1월말~2월초 긴 휴식 발생', '잦은 늦잠으로 오전 활용 실패'],
      strategy: '상황판단 보류 → 자료해석·언어논리 2과목 올인'),
    PlanEvaluation(date: '2026-02-28', title: '★ 2차 중간평가', result: '시나리오A 불가 → 전략 전환',
      causes: ['상황판단 완전 배제, 언논/자해 집중 중', '5급 D-7: 기출분석 및 진도 부족',
        '기상/취침 등 기본 생활 루틴 확보 미미', '준비 계획의 구체성 결여', '전반적인 리빌딩 필요'],
      strategy: '7급 1차 합격 + 2차 준비 주 목적 전환, 경제학 병행, 생활 루틴 선행 확보'),
    PlanEvaluation(date: '2026-03-22', title: 'B-1 루틴 정착 점검'),
    PlanEvaluation(date: '2026-04-10', title: '5급 1차 성적 분석'),
    PlanEvaluation(date: '2026-06-15', title: '7급 1차 준비도 점검'),
    PlanEvaluation(date: '2026-08-19', title: '7급 1차 결과 기반 진로 결정'),
  ];

  // ═══ 시나리오 ═══
  static const List<PlanScenario> scenarios = [
    PlanScenario(id: 'CASE_A', condition: '5급 1차 성적 우수 (비현실적)', trigger: '5급 평균 85+',
      actions: ['7급 2차 비중 확대', '직렬 확장 검토'], nextPeriod: 'B (강화)'),
    PlanScenario(id: 'CASE_B', condition: '5급 1차 성적 저조 (예상)', trigger: '5급 기대 미달',
      actions: ['PSAT 실패 요인 역분해', '리빌딩 본격 실행', '취약 과목 집중'], nextPeriod: 'B (리빌딩)'),
    PlanScenario(id: 'CASE_C', condition: '7급 1차 합격', trigger: '7급 1차 합격 확인',
      actions: ['2차 올인 모드', '전공 심화', '면접 준비'], nextPeriod: 'D (올인)'),
    PlanScenario(id: 'CASE_D', condition: '7급 1차 불합격', trigger: '7급 1차 불합격',
      actions: ['직렬·연도 전략 전면 수정'], nextPeriod: '재검토'),
  ];

  // ═══ 유틸리티 ═══
  static PlanPeriod? periodForDate(String ds) {
    for (final p in periods) { if (p.containsDate(ds)) return p; } return null;
  }
  static PlanSubPeriod? subPeriodForDate(String ds) => periodForDate(ds)?.subPeriodForDate(ds);
  static PlanDailyPlan? dailyPlanForDate(String ds) {
    try { return dailyPlans.firstWhere((p) => p.date == ds); } catch (_) { return null; }
  }
  static List<PlanDDay> ddaysForDate(String ds) => ddays.where((d) => d.enabled && d.date == ds).toList();
  static List<PlanMilestone> milestonesForDate(String ds) => milestones.where((m) => m.date == ds).toList();
  static PlanEvaluation? evaluationForDate(String ds) {
    try { return evaluations.firstWhere((e) => e.date == ds); } catch (_) { return null; }
  }
  static PlanDDay? nearestDDay() {
    final future = ddays.where((d) => d.enabled && d.daysLeft >= 0).toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return future.isNotEmpty ? future.first : null;
  }
  static PlanDDay? primaryDDay() {
    try { return ddays.firstWhere((d) => d.primary && d.enabled); } catch (_) { return nearestDDay(); }
  }
  static Color tagColor(String tag) => tagColors[tag] ?? const Color(0xFF64748B);
  static String tagLabel(String tag) => tagLabels[tag] ?? tag;
  static String? dDayLabelForDate(String ds) => dailyPlanForDate(ds)?.label;

  // ═══════════════════════════════════════════════
  //  ★ 시드: HTML 2차 중간평가 → OrderGoal / OrderHabit 변환
  //  _seed() 호출 시 한 번만 생성, Firebase 저장 후 재사용
  // ═══════════════════════════════════════════════

  static List<OrderGoal> seedGoals() {
    int ms = 0;
    OrderMilestone _m(String text) =>
        OrderMilestone(id: 'ms_seed_${ms++}', text: text);

    return [
      // ── Marathon (장기) ──────────────────────────

      OrderGoal(
        id: 'g_plan_1',
        title: '7급 외무영사직 1차 합격',
        desc: '★ 핵심 목표. PSAT 3과목 완성 → 7월 18일 합격',
        tier: GoalTier.marathon, area: GoalArea.study,
        priority: 1,
        deadline: '2026-07-18',
        milestones: [
          _m('언어논리 기출 아카이브 완성'),
          _m('자료해석 기출 아카이브 완성'),
          _m('상황판단 커리큘럼 완주'),
          _m('모의고사 실전 훈련 3회+'),
          _m('과목별 단권화 자료 완성'),
          _m('7급 1차 PSAT 응시'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_2',
        title: '7급 2차 전공 완성',
        desc: '국제법 · 국제정치학 인강 + 경제학 기본서',
        tier: GoalTier.marathon, area: GoalArea.study,
        deadline: '2026-10-31',
        milestones: [
          _m('국제법 인강 1회독 완료'),
          _m('국제정치학 인강 1회독 완료'),
          _m('경제학 기본서 1회독 완료'),
          _m('전공 문제풀이 착수'),
        ],
      ),

      // ── Race (중기) ──────────────────────────

      OrderGoal(
        id: 'g_plan_3',
        title: '생활 루틴 안정화',
        desc: '최우선 과제 — 3월 3주까지 기상/취침 루틴 완성',
        tier: GoalTier.race, area: GoalArea.life,
        priority: 2,
        deadline: '2026-03-22',
        milestones: [
          _m('기상 목표시간 확립'),
          _m('취침 루틴 정착'),
          _m('루틴 정착률 80%+ 달성'),
          _m('오전 시간대 학습 활용 정착'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_4',
        title: '상황판단 커리큘럼 완주',
        desc: '고시닷컴 이지은 인강 전체 수강 (~6월 초)',
        tier: GoalTier.race, area: GoalArea.study,
        deadline: '2026-06-15',
        parentGoalId: 'g_plan_1', // ← 7급 1차 합격 하위
        milestones: [
          _m('기초과정 완료'),
          _m('기본과정 완료'),
          _m('유형별과정 완료'),
          _m('기출분석 완료'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_5',
        title: '경제학 일일 루틴 확립',
        desc: '매일 1시간 장기 투입 — 직렬 변경 대비',
        tier: GoalTier.race, area: GoalArea.study,
        deadline: '2026-06-15',
        parentGoalId: 'g_plan_2', // ← 7급 2차 전공 하위
        milestones: [
          _m('경제학 입문 인강 선정'),
          _m('입문 인강 수강 완료'),
          _m('기본서 1회독 착수'),
          _m('매일 1시간 투입 4주 연속 달성'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_6',
        title: 'PSAT 자해·언논 약점 보완',
        desc: '자료해석/언어논리 약점 유형 재분석 및 보완',
        tier: GoalTier.race, area: GoalArea.study,
        deadline: '2026-06-15',
        parentGoalId: 'g_plan_1', // ← 7급 1차 합격 하위
        milestones: [
          _m('자료해석 약점 유형 재분석'),
          _m('언어논리 약점 유형 재분석'),
          _m('약점별 보완 학습 계획 수립'),
          _m('보완 학습 완료'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_7',
        title: '7급 2차 인강 착수',
        desc: '국제법/국제정치학 인강 수강 시작 + 공부법 수립',
        tier: GoalTier.race, area: GoalArea.study,
        deadline: '2026-06-15',
        parentGoalId: 'g_plan_2', // ← 7급 2차 전공 하위
        milestones: [
          _m('국제법 인강 착수'),
          _m('국제정치학 인강 착수'),
          _m('과목별 공부법 수립'),
          _m('7월까지 2차 투입 시간 결정'),
        ],
      ),

      // ── Sprint (단기) ──────────────────────────

      OrderGoal(
        id: 'g_plan_8',
        title: '5급 1차 PSAT 응시',
        desc: '최대한 점수 확보 — 분기점 가치 소멸, 경험치로 활용',
        tier: GoalTier.sprint, area: GoalArea.study,
        deadline: '2026-03-07',
        parentGoalId: 'g_plan_1', // ← 경험치로 7급 1차에 기여
        milestones: [
          _m('기출 세트 매일 풀이'),
          _m('시간 배분 고정 훈련'),
          _m('5급 1차 시험 응시 완료'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_9',
        title: '입법고시 1차 응시',
        desc: '2/28 응시 완료',
        tier: GoalTier.sprint, area: GoalArea.study,
        deadline: '2026-02-28',
        milestones: [
          _m('입법고시 1차 시험 응시 완료'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_10',
        title: '기상/취침 루틴 1차 점검',
        desc: '3/15까지 — 루틴 정착 초기 목표',
        tier: GoalTier.sprint, area: GoalArea.life,
        deadline: '2026-03-15',
        parentGoalId: 'g_plan_3', // ← 생활 루틴 안정화 하위
        milestones: [
          _m('기상 목표시간 5일 연속 달성'),
          _m('취침 목표시간 5일 연속 달성'),
          _m('NFC 기상 태그 활용 정착'),
        ],
      ),
      OrderGoal(
        id: 'g_plan_11',
        title: '매일 자기반성 루틴 정착',
        desc: '학습/인식적 문제점 매일 분석 및 교정',
        tier: GoalTier.sprint, area: GoalArea.life,
        deadline: '2026-03-22',
        parentGoalId: 'g_plan_3', // ← 생활 루틴 안정화 하위
        milestones: [
          _m('학습 문제점 매일 분석 7일 연속'),
          _m('인식적 문제점 매일 교정 7일 연속'),
          _m('자기반성 기록 2주 이상 축적'),
        ],
      ),
    ];
  }

  /// 수험 비용 초기 데이터
  static List<StudyExpense> seedExpenses() {
    return [
      StudyExpense(
        id: 'exp_seed_1',
        title: '조훈 2025 자료해석 모의고사',
        amount: 180000,
        category: '모의고사',
        date: '2026-03-03',
      ),
    ];
  }

  /// HTML 평가서 기반 초기 습관 큐
  static List<OrderHabit> seedHabits() {
    return [
      OrderHabit(
        id: 'h_plan_1', title: '기상 루틴', emoji: '⏰',
        rank: 1, targetDays: 21,  // ★ 포커스
      ),
      OrderHabit(
        id: 'h_plan_2', title: '취침 루틴', emoji: '🌙',
        rank: 2, targetDays: 21,
      ),
      OrderHabit(
        id: 'h_plan_3', title: '경제학 매일 1시간', emoji: '📚',
        rank: 3, targetDays: 21,
      ),
      OrderHabit(
        id: 'h_plan_4', title: '자기반성 기록', emoji: '📝',
        rank: 4, targetDays: 21,
      ),
      OrderHabit(
        id: 'h_plan_5', title: '상황판단 인강', emoji: '🎧',
        rank: 5, targetDays: 21,
      ),
    ];
  }
}