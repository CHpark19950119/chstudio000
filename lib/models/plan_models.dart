/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 학습계획 · 피드백 · AI코칭 · 성장 모델
/// Batch 3: #3 학습계획·피드백관리 + #4 AI협업학습코칭
/// ═══════════════════════════════════════════════════════════

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 1: 학습 계획 (Study Plan)                           ║
// ╚═══════════════════════════════════════════════════════════╝

/// 동적 학습 계획 — Firestore studyPlan 필드
class StudyPlan {
  final String version;
  final String title;
  final String? updatedAt;
  final String? updatedBy; // "web" | "app" | "ai"
  final Map<String, AnnualGoal> annualGoals;
  final List<PlanPeriodDyn> periods;
  final List<DDayEvent> ddays;
  final StrategicDirection? strategy;
  final List<ScenarioBranch> scenarios;

  StudyPlan({
    this.version = '5.0',
    this.title = '',
    this.updatedAt,
    this.updatedBy,
    Map<String, AnnualGoal>? annualGoals,
    List<PlanPeriodDyn>? periods,
    List<DDayEvent>? ddays,
    this.strategy,
    List<ScenarioBranch>? scenarios,
  })  : annualGoals = annualGoals ?? {},
        periods = periods ?? [],
        ddays = ddays ?? [],
        scenarios = scenarios ?? [];

  /// 현재 날짜가 속한 기간
  PlanPeriodDyn? periodForDate(String ds) {
    for (final p in periods) {
      if (p.containsDate(ds)) return p;
    }
    return null;
  }

  /// 현재 날짜가 속한 하위 기간
  PlanSubPeriodDyn? subPeriodForDate(String ds) {
    return periodForDate(ds)?.subPeriodForDate(ds);
  }

  /// 활성 D-Day 중 가장 가까운 것
  DDayEvent? nearestDDay() {
    final future = ddays
        .where((d) => d.enabled && d.daysLeft >= 0)
        .toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return future.isNotEmpty ? future.first : null;
  }

  /// primary D-Day (없으면 가장 가까운 것)
  DDayEvent? primaryDDay() {
    try {
      return ddays.firstWhere((d) => d.primary && d.enabled);
    } catch (_) {
      return nearestDDay();
    }
  }

  factory StudyPlan.fromMap(Map<String, dynamic> m) {
    // annualGoals 파싱
    final goalsRaw = m['annualGoals'] as Map<String, dynamic>? ?? {};
    final goals = goalsRaw.map((k, v) =>
        MapEntry(k, AnnualGoal.fromMap(Map<String, dynamic>.from(v as Map))));

    return StudyPlan(
      version: m['version'] ?? '5.0',
      title: m['title'] ?? '',
      updatedAt: m['updatedAt'] as String?,
      updatedBy: m['updatedBy'] as String?,
      annualGoals: goals,
      periods: (m['periods'] as List?)
              ?.map((e) =>
                  PlanPeriodDyn.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      ddays: (m['ddays'] as List?)
              ?.map((e) =>
                  DDayEvent.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      strategy: m['strategicDirection'] != null
          ? StrategicDirection.fromMap(
              Map<String, dynamic>.from(m['strategicDirection'] as Map))
          : null,
      scenarios: (m['scenarios'] as List?)
              ?.map((e) =>
                  ScenarioBranch.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'title': title,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
        'annualGoals':
            annualGoals.map((k, v) => MapEntry(k, v.toMap())),
        'periods': periods.map((p) => p.toMap()).toList(),
        'ddays': ddays.map((d) => d.toMap()).toList(),
        if (strategy != null) 'strategicDirection': strategy!.toMap(),
        'scenarios': scenarios.map((s) => s.toMap()).toList(),
      };
}

/// 연간 목표
class AnnualGoal {
  final String title;
  final int priority;
  final String status; // "active" | "completed" | "paused" | "dropped"

  AnnualGoal({
    required this.title,
    this.priority = 0,
    this.status = 'active',
  });

  bool get isActive => status == 'active';

  factory AnnualGoal.fromMap(Map<String, dynamic> m) => AnnualGoal(
        title: m['title'] ?? '',
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        status: m['status'] ?? 'active',
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'priority': priority,
        'status': status,
      };
}

/// 기간 (Period) — 동적 버전
class PlanPeriodDyn {
  final String id;
  final String name;
  final String start; // yyyy-MM-dd
  final String end;
  final String goal;
  final int totalDays;
  final String status; // "active" | "completed" | "upcoming" | "skipped"
  final List<PlanSubPeriodDyn> subPeriods;
  final List<PlanSubjectDyn> subjects;

  PlanPeriodDyn({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.goal,
    this.totalDays = 0,
    this.status = 'upcoming',
    List<PlanSubPeriodDyn>? subPeriods,
    List<PlanSubjectDyn>? subjects,
  })  : subPeriods = subPeriods ?? [],
        subjects = subjects ?? [];

  bool containsDate(String ds) =>
      ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;

  PlanSubPeriodDyn? subPeriodForDate(String ds) {
    for (final sp in subPeriods) {
      if (sp.containsDate(ds)) return sp;
    }
    return null;
  }

  double progressForDate(String ds) {
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    final d = DateTime.tryParse(ds);
    if (s == null || e == null || d == null) return 0;
    final total = e.difference(s).inDays;
    if (total <= 0) return 0;
    return (d.difference(s).inDays / total).clamp(0.0, 1.0);
  }

  factory PlanPeriodDyn.fromMap(Map<String, dynamic> m) => PlanPeriodDyn(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        start: m['start'] ?? '',
        end: m['end'] ?? '',
        goal: m['goal'] ?? '',
        totalDays: (m['totalDays'] as num?)?.toInt() ?? 0,
        status: m['status'] ?? 'upcoming',
        subPeriods: (m['subPeriods'] as List?)
                ?.map((e) => PlanSubPeriodDyn.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        subjects: (m['subjects'] as List?)
                ?.map((e) => PlanSubjectDyn.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start,
        'end': end,
        'goal': goal,
        'totalDays': totalDays,
        'status': status,
        'subPeriods': subPeriods.map((s) => s.toMap()).toList(),
        'subjects': subjects.map((s) => s.toMap()).toList(),
      };
}

/// 하위 기간
class PlanSubPeriodDyn {
  final String id;
  final String name;
  final String start;
  final String end;
  final int days;
  final String? instructor;
  final String primaryGoal;
  final List<String> goals;
  final List<String> checkpoints;
  final String status;

  PlanSubPeriodDyn({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.days = 0,
    this.instructor,
    required this.primaryGoal,
    List<String>? goals,
    List<String>? checkpoints,
    this.status = 'upcoming',
  })  : goals = goals ?? [],
        checkpoints = checkpoints ?? [];

  bool containsDate(String ds) =>
      ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;

  factory PlanSubPeriodDyn.fromMap(Map<String, dynamic> m) =>
      PlanSubPeriodDyn(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        start: m['start'] ?? '',
        end: m['end'] ?? '',
        days: (m['days'] as num?)?.toInt() ?? 0,
        instructor: m['instructor'] as String?,
        primaryGoal: m['primaryGoal'] ?? '',
        goals: (m['goals'] as List?)?.map((e) => e.toString()).toList() ?? [],
        checkpoints:
            (m['checkpoints'] as List?)?.map((e) => e.toString()).toList() ??
                [],
        status: m['status'] ?? 'upcoming',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start,
        'end': end,
        'days': days,
        if (instructor != null) 'instructor': instructor,
        'primaryGoal': primaryGoal,
        'goals': goals,
        'checkpoints': checkpoints,
        'status': status,
      };
}

/// 과목
class PlanSubjectDyn {
  final String title;
  final String tag;
  final String? instructor;
  final String? period; // 보류 등 메모
  final List<String> curriculum;

  PlanSubjectDyn({
    required this.title,
    required this.tag,
    this.instructor,
    this.period,
    List<String>? curriculum,
  }) : curriculum = curriculum ?? [];

  factory PlanSubjectDyn.fromMap(Map<String, dynamic> m) => PlanSubjectDyn(
        title: m['title'] ?? '',
        tag: m['tag'] ?? '',
        instructor: m['instructor'] as String?,
        period: m['period'] as String?,
        curriculum:
            (m['curriculum'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'tag': tag,
        if (instructor != null) 'instructor': instructor,
        if (period != null) 'period': period,
        'curriculum': curriculum,
      };
}

/// D-Day 이벤트
class DDayEvent {
  final int id;
  final String name;
  final String date; // yyyy-MM-dd
  final bool primary;
  final bool enabled;

  DDayEvent({
    required this.id,
    required this.name,
    required this.date,
    this.primary = false,
    this.enabled = true,
  });

  int get daysLeft {
    final now = DateTime.now();
    final target = DateTime.tryParse(date);
    if (target == null) return 999;
    return target
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  bool get isPast => daysLeft < 0;

  String get dDayLabel {
    final d = daysLeft;
    if (d == 0) return 'D-Day';
    return d > 0 ? 'D-$d' : 'D+${d.abs()}';
  }

  factory DDayEvent.fromMap(Map<String, dynamic> m) => DDayEvent(
        id: (m['id'] as num?)?.toInt() ?? 0,
        name: m['name'] ?? '',
        date: m['date'] ?? '',
        primary: m['primary'] ?? false,
        enabled: m['enabled'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'date': date,
        'primary': primary,
        'enabled': enabled,
      };
}

/// 전략 방향
class StrategicDirection {
  final String diagnosis;
  final String? lastEvaluated;
  final String? nextEvaluation;
  final Map<String, String> notes; // 키-값 자유 메모

  StrategicDirection({
    required this.diagnosis,
    this.lastEvaluated,
    this.nextEvaluation,
    Map<String, String>? notes,
  }) : notes = notes ?? {};

  factory StrategicDirection.fromMap(Map<String, dynamic> m) {
    final notesRaw = m['notes'] as Map<String, dynamic>? ?? {};
    return StrategicDirection(
      diagnosis: m['diagnosis'] ?? '',
      lastEvaluated: m['lastEvaluated'] as String?,
      nextEvaluation: m['nextEvaluation'] as String?,
      notes: notesRaw.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toMap() => {
        'diagnosis': diagnosis,
        if (lastEvaluated != null) 'lastEvaluated': lastEvaluated,
        if (nextEvaluation != null) 'nextEvaluation': nextEvaluation,
        'notes': notes,
      };
}

/// 시나리오 분기
class ScenarioBranch {
  final String id;
  final String condition;
  final String trigger;
  final List<String> actions;
  final String nextPeriod;

  ScenarioBranch({
    required this.id,
    required this.condition,
    required this.trigger,
    List<String>? actions,
    required this.nextPeriod,
  }) : actions = actions ?? [];

  factory ScenarioBranch.fromMap(Map<String, dynamic> m) => ScenarioBranch(
        id: m['id'] ?? '',
        condition: m['condition'] ?? '',
        trigger: m['trigger'] ?? '',
        actions:
            (m['actions'] as List?)?.map((e) => e.toString()).toList() ?? [],
        nextPeriod: m['nextPeriod'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'condition': condition,
        'trigger': trigger,
        'actions': actions,
        'nextPeriod': nextPeriod,
      };
}

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 1-B: Todo (할일 관리)                                 ║
// ╚═══════════════════════════════════════════════════════════╝

/// Todo 개별 항목
class TodoItem {
  final String id;
  final String title;
  bool completed;
  String? completedAt; // ISO8601
  int order; // 정렬 순서

  TodoItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.completedAt,
    this.order = 0,
  });

  TodoItem copyWith({
    String? title,
    bool? completed,
    String? completedAt,
    int? order,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        order: order ?? this.order,
      );

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'] ?? '',
        title: m['title'] ?? '',
        completed: m['completed'] ?? false,
        completedAt: m['completedAt'] as String?,
        order: (m['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        'order': order,
      };
}

/// 일일 Todo 전체 (하루 한 문서)
class TodoDaily {
  final String date; // yyyy-MM-dd
  final List<TodoItem> items;
  final String? memo;
  final String? createdAt;
  final String? updatedAt;

  TodoDaily({
    required this.date,
    List<TodoItem>? items,
    this.memo,
    this.createdAt,
    this.updatedAt,
  }) : items = items ?? [];

  /// 완료율 (0.0 ~ 1.0)
  double get completionRate {
    if (items.isEmpty) return 0.0;
    return items.where((t) => t.completed).length / items.length;
  }

  int get completedCount => items.where((t) => t.completed).length;
  int get totalCount => items.length;

  factory TodoDaily.fromMap(Map<String, dynamic> m) => TodoDaily(
        date: m['date'] ?? '',
        items: (m['items'] as List?)
                ?.map((e) =>
                    TodoItem.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        memo: m['memo'] as String?,
        createdAt: m['createdAt'] as String?,
        updatedAt: m['updatedAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'items': items.map((t) => t.toMap()).toList(),
        if (memo != null) 'memo': memo,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 2: 일간 피드백 (Daily Feedback)                      ║
// ╚═══════════════════════════════════════════════════════════╝

/// 일간 피드백 전체
class DailyFeedback {
  final String date;
  final String? createdAt;
  final String? source; // "web" | "app"
  final SelfAssessment? selfAssessment;
  final Execution? execution;
  final Reflection? reflection;
  final AiDailyAnalysis? aiAnalysis;

  DailyFeedback({
    required this.date,
    this.createdAt,
    this.source,
    this.selfAssessment,
    this.execution,
    this.reflection,
    this.aiAnalysis,
  });

  /// 성장 점수 (0~100) 자동 계산
  double calcGrowthScore({
    int effectiveMin = 0,
    bool wakeOnTime = false,
    bool bedOnTime = false,
    int activeHabits = 0,
    int completedHabits = 0,
  }) {
    // 학습시간 (30점): 목표 8시간(480분) 기준
    final studyScore =
        (effectiveMin / 480.0).clamp(0.0, 1.0) * 30;

    // 계획 실행률 (25점)
    final execScore =
        (execution?.completionRate ?? 0.0) * 25;

    // 루틴 점수 (20점): 기상 10 + 취침 10
    final routineScore =
        (wakeOnTime ? 10.0 : 0.0) + (bedOnTime ? 10.0 : 0.0);

    // 습관 점수 (15점)
    final habitScore = activeHabits > 0
        ? (completedHabits / activeHabits).clamp(0.0, 1.0) * 15
        : 0.0;

    // 집중도 점수 (10점)
    final focusScore = focusQualityScore(
        selfAssessment?.focusQuality ?? 'fair');

    return studyScore + execScore + routineScore + habitScore + focusScore;
  }

  static double focusQualityScore(String quality) {
    switch (quality) {
      case 'excellent':
        return 10.0;
      case 'good':
        return 7.0;
      case 'fair':
        return 5.0;
      case 'poor':
        return 2.0;
      default:
        return 5.0;
    }
  }

  factory DailyFeedback.fromMap(Map<String, dynamic> m) => DailyFeedback(
        date: m['date'] ?? '',
        createdAt: m['createdAt'] as String?,
        source: m['source'] as String?,
        selfAssessment: m['selfAssessment'] != null
            ? SelfAssessment.fromMap(
                Map<String, dynamic>.from(m['selfAssessment'] as Map))
            : null,
        execution: m['execution'] != null
            ? Execution.fromMap(
                Map<String, dynamic>.from(m['execution'] as Map))
            : null,
        reflection: m['reflection'] != null
            ? Reflection.fromMap(
                Map<String, dynamic>.from(m['reflection'] as Map))
            : null,
        aiAnalysis: m['aiAnalysis'] != null
            ? AiDailyAnalysis.fromMap(
                Map<String, dynamic>.from(m['aiAnalysis'] as Map))
            : null,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        if (createdAt != null) 'createdAt': createdAt,
        if (source != null) 'source': source,
        if (selfAssessment != null) 'selfAssessment': selfAssessment!.toMap(),
        if (execution != null) 'execution': execution!.toMap(),
        if (reflection != null) 'reflection': reflection!.toMap(),
        if (aiAnalysis != null) 'aiAnalysis': aiAnalysis!.toMap(),
      };
}

/// 자기 평가
class SelfAssessment {
  final int overallScore; // 1~10
  final String energyLevel; // low | medium | high
  final String focusQuality; // poor | fair | good | excellent
  final String emotionalState; // stressed | anxious | neutral | positive | motivated
  final String? freeNote;

  SelfAssessment({
    this.overallScore = 5,
    this.energyLevel = 'medium',
    this.focusQuality = 'fair',
    this.emotionalState = 'neutral',
    this.freeNote,
  });

  String get energyEmoji {
    switch (energyLevel) {
      case 'high': return '⚡';
      case 'medium': return '🔋';
      case 'low': return '🪫';
      default: return '🔋';
    }
  }

  String get focusEmoji {
    switch (focusQuality) {
      case 'excellent': return '🎯';
      case 'good': return '✅';
      case 'fair': return '➖';
      case 'poor': return '❌';
      default: return '➖';
    }
  }

  String get emotionEmoji {
    switch (emotionalState) {
      case 'motivated': return '🔥';
      case 'positive': return '😊';
      case 'neutral': return '😐';
      case 'anxious': return '😰';
      case 'stressed': return '😤';
      default: return '😐';
    }
  }

  factory SelfAssessment.fromMap(Map<String, dynamic> m) => SelfAssessment(
        overallScore: (m['overallScore'] as num?)?.toInt() ?? 5,
        energyLevel: m['energyLevel'] ?? 'medium',
        focusQuality: m['focusQuality'] ?? 'fair',
        emotionalState: m['emotionalState'] ?? 'neutral',
        freeNote: m['freeNote'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'overallScore': overallScore,
        'energyLevel': energyLevel,
        'focusQuality': focusQuality,
        'emotionalState': emotionalState,
        if (freeNote != null) 'freeNote': freeNote,
      };
}

/// 계획 실행
class Execution {
  final List<PlannedTask> plannedTasks;
  final List<String> unplannedTasks;
  final List<String> blockers;

  Execution({
    List<PlannedTask>? plannedTasks,
    List<String>? unplannedTasks,
    List<String>? blockers,
  })  : plannedTasks = plannedTasks ?? [],
        unplannedTasks = unplannedTasks ?? [],
        blockers = blockers ?? [];

  /// 실행률 자동 계산
  double get completionRate {
    if (plannedTasks.isEmpty) return 0.0;
    final completed = plannedTasks.where((t) => t.completed).length;
    return completed / plannedTasks.length;
  }

  int get completedCount => plannedTasks.where((t) => t.completed).length;
  int get totalCount => plannedTasks.length;

  factory Execution.fromMap(Map<String, dynamic> m) => Execution(
        plannedTasks: (m['plannedTasks'] as List?)
                ?.map((e) =>
                    PlannedTask.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        unplannedTasks: (m['unplannedTasks'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        blockers: (m['blockers'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'plannedTasks': plannedTasks.map((t) => t.toMap()).toList(),
        'unplannedTasks': unplannedTasks,
        'blockers': blockers,
        'completionRate': completionRate,
      };
}

/// 계획된 개별 과제
class PlannedTask {
  final String task;
  final bool completed;
  final int? actualMin;
  final String? reason; // 미완료 사유
  final String? subject; // 과목 태그

  PlannedTask({
    required this.task,
    this.completed = false,
    this.actualMin,
    this.reason,
    this.subject,
  });

  PlannedTask copyWith({
    String? task,
    bool? completed,
    int? actualMin,
    String? reason,
    String? subject,
  }) =>
      PlannedTask(
        task: task ?? this.task,
        completed: completed ?? this.completed,
        actualMin: actualMin ?? this.actualMin,
        reason: reason ?? this.reason,
        subject: subject ?? this.subject,
      );

  factory PlannedTask.fromMap(Map<String, dynamic> m) => PlannedTask(
        task: m['task'] ?? '',
        completed: m['completed'] ?? false,
        actualMin: (m['actualMin'] as num?)?.toInt(),
        reason: m['reason'] as String?,
        subject: m['subject'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'task': task,
        'completed': completed,
        if (actualMin != null) 'actualMin': actualMin,
        if (reason != null) 'reason': reason,
        if (subject != null) 'subject': subject,
      };
}

/// 자기 반성
class Reflection {
  final List<String> learningIssues; // 학습 문제
  final List<String> cognitiveIssues; // 인식 문제
  final List<String> corrections; // 교정 계획

  Reflection({
    List<String>? learningIssues,
    List<String>? cognitiveIssues,
    List<String>? corrections,
  })  : learningIssues = learningIssues ?? [],
        cognitiveIssues = cognitiveIssues ?? [],
        corrections = corrections ?? [];

  bool get isEmpty =>
      learningIssues.isEmpty &&
      cognitiveIssues.isEmpty &&
      corrections.isEmpty;

  factory Reflection.fromMap(Map<String, dynamic> m) => Reflection(
        learningIssues: (m['learningIssues'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        cognitiveIssues: (m['cognitiveIssues'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        corrections: (m['corrections'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'learningIssues': learningIssues,
        'cognitiveIssues': cognitiveIssues,
        'corrections': corrections,
      };
}

/// AI 일간 분석 결과
class AiDailyAnalysis {
  final String? generatedAt;
  final String? model;
  final String summary;
  final List<String> strengths;
  final List<String> concerns;
  final List<String> suggestions;
  final String? trendNote;
  final String? encouragement;

  AiDailyAnalysis({
    this.generatedAt,
    this.model,
    this.summary = '',
    List<String>? strengths,
    List<String>? concerns,
    List<String>? suggestions,
    this.trendNote,
    this.encouragement,
  })  : strengths = strengths ?? [],
        concerns = concerns ?? [],
        suggestions = suggestions ?? [];

  factory AiDailyAnalysis.fromMap(Map<String, dynamic> m) => AiDailyAnalysis(
        generatedAt: m['generatedAt'] as String?,
        model: m['model'] as String?,
        summary: m['summary'] ?? '',
        strengths:
            (m['strengths'] as List?)?.map((e) => e.toString()).toList() ?? [],
        concerns:
            (m['concerns'] as List?)?.map((e) => e.toString()).toList() ?? [],
        suggestions: (m['suggestions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        trendNote: m['trendNote'] as String?,
        encouragement: m['encouragement'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (generatedAt != null) 'generatedAt': generatedAt,
        if (model != null) 'model': model,
        'summary': summary,
        'strengths': strengths,
        'concerns': concerns,
        'suggestions': suggestions,
        if (trendNote != null) 'trendNote': trendNote,
        if (encouragement != null) 'encouragement': encouragement,
      };
}

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 3: 주간 리뷰 (Weekly Review)                        ║
// ╚═══════════════════════════════════════════════════════════╝

/// 주간 리뷰 전체
class WeeklyReview {
  final String weekId; // yyyy-Www (예: 2026-W10)
  final String startDate;
  final String endDate;
  final String? createdAt;
  final WeeklyStats? stats;
  final Map<String, SubjectTime> subjectBreakdown;
  final UserWeeklyReview? userReview;
  final AiWeeklyAnalysis? aiAnalysis;

  WeeklyReview({
    required this.weekId,
    required this.startDate,
    required this.endDate,
    this.createdAt,
    this.stats,
    Map<String, SubjectTime>? subjectBreakdown,
    this.userReview,
    this.aiAnalysis,
  }) : subjectBreakdown = subjectBreakdown ?? {};

  factory WeeklyReview.fromMap(Map<String, dynamic> m) {
    final breakdown = m['subjectBreakdown'] as Map<String, dynamic>? ?? {};
    return WeeklyReview(
      weekId: m['weekId'] ?? '',
      startDate: m['startDate'] ?? '',
      endDate: m['endDate'] ?? '',
      createdAt: m['createdAt'] as String?,
      stats: m['stats'] != null
          ? WeeklyStats.fromMap(
              Map<String, dynamic>.from(m['stats'] as Map))
          : null,
      subjectBreakdown: breakdown.map((k, v) =>
          MapEntry(k, SubjectTime.fromMap(Map<String, dynamic>.from(v as Map)))),
      userReview: m['userReview'] != null
          ? UserWeeklyReview.fromMap(
              Map<String, dynamic>.from(m['userReview'] as Map))
          : null,
      aiAnalysis: m['aiAnalysis'] != null
          ? AiWeeklyAnalysis.fromMap(
              Map<String, dynamic>.from(m['aiAnalysis'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'weekId': weekId,
        'startDate': startDate,
        'endDate': endDate,
        if (createdAt != null) 'createdAt': createdAt,
        if (stats != null) 'stats': stats!.toMap(),
        'subjectBreakdown':
            subjectBreakdown.map((k, v) => MapEntry(k, v.toMap())),
        if (userReview != null) 'userReview': userReview!.toMap(),
        if (aiAnalysis != null) 'aiAnalysis': aiAnalysis!.toMap(),
      };
}

/// 주간 통계
class WeeklyStats {
  final int totalStudyMin;
  final int avgDailyMin;
  final int maxDailyMin;
  final int minDailyMin;
  final int studyDays;
  final int restDays;
  final String? avgWakeTime;
  final String? avgBedTime;
  final double taskCompletionRate;
  final double habitCompletionRate;

  WeeklyStats({
    this.totalStudyMin = 0,
    this.avgDailyMin = 0,
    this.maxDailyMin = 0,
    this.minDailyMin = 0,
    this.studyDays = 0,
    this.restDays = 0,
    this.avgWakeTime,
    this.avgBedTime,
    this.taskCompletionRate = 0.0,
    this.habitCompletionRate = 0.0,
  });

  String get totalStudyFormatted {
    final h = totalStudyMin ~/ 60;
    final m = totalStudyMin % 60;
    return '${h}h ${m}m';
  }

  String get avgDailyFormatted {
    final h = avgDailyMin ~/ 60;
    final m = avgDailyMin % 60;
    return '${h}h ${m}m';
  }

  factory WeeklyStats.fromMap(Map<String, dynamic> m) => WeeklyStats(
        totalStudyMin: (m['totalStudyMin'] as num?)?.toInt() ?? 0,
        avgDailyMin: (m['avgDailyMin'] as num?)?.toInt() ?? 0,
        maxDailyMin: (m['maxDailyMin'] as num?)?.toInt() ?? 0,
        minDailyMin: (m['minDailyMin'] as num?)?.toInt() ?? 0,
        studyDays: (m['studyDays'] as num?)?.toInt() ?? 0,
        restDays: (m['restDays'] as num?)?.toInt() ?? 0,
        avgWakeTime: m['avgWakeTime'] as String?,
        avgBedTime: m['avgBedTime'] as String?,
        taskCompletionRate: (m['taskCompletionRate'] as num?)?.toDouble() ?? 0.0,
        habitCompletionRate:
            (m['habitCompletionRate'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toMap() => {
        'totalStudyMin': totalStudyMin,
        'avgDailyMin': avgDailyMin,
        'maxDailyMin': maxDailyMin,
        'minDailyMin': minDailyMin,
        'studyDays': studyDays,
        'restDays': restDays,
        if (avgWakeTime != null) 'avgWakeTime': avgWakeTime,
        if (avgBedTime != null) 'avgBedTime': avgBedTime,
        'taskCompletionRate': taskCompletionRate,
        'habitCompletionRate': habitCompletionRate,
      };
}

/// 과목별 시간
class SubjectTime {
  final int minutes;
  final int sessions;

  SubjectTime({this.minutes = 0, this.sessions = 0});

  String get formatted {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  factory SubjectTime.fromMap(Map<String, dynamic> m) => SubjectTime(
        minutes: (m['minutes'] as num?)?.toInt() ?? 0,
        sessions: (m['sessions'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'minutes': minutes,
        'sessions': sessions,
      };
}

/// 사용자 주간 회고
class UserWeeklyReview {
  final String? whatWentWell;
  final String? whatWentWrong;
  final String? nextWeekFocus;
  final List<String> goalAdjustments;

  UserWeeklyReview({
    this.whatWentWell,
    this.whatWentWrong,
    this.nextWeekFocus,
    List<String>? goalAdjustments,
  }) : goalAdjustments = goalAdjustments ?? [];

  factory UserWeeklyReview.fromMap(Map<String, dynamic> m) =>
      UserWeeklyReview(
        whatWentWell: m['whatWentWell'] as String?,
        whatWentWrong: m['whatWentWrong'] as String?,
        nextWeekFocus: m['nextWeekFocus'] as String?,
        goalAdjustments: (m['goalAdjustments'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        if (whatWentWell != null) 'whatWentWell': whatWentWell,
        if (whatWentWrong != null) 'whatWentWrong': whatWentWrong,
        if (nextWeekFocus != null) 'nextWeekFocus': nextWeekFocus,
        'goalAdjustments': goalAdjustments,
      };
}

/// AI 주간 분석
class AiWeeklyAnalysis {
  final String? generatedAt;
  final String? model;
  final String weekSummary;
  final List<AnalysisPattern> patterns;
  final List<Recommendation> recommendations;
  final String? weeklyGrade;
  final double growthScore;
  final String? comparisonToLastWeek;

  AiWeeklyAnalysis({
    this.generatedAt,
    this.model,
    this.weekSummary = '',
    List<AnalysisPattern>? patterns,
    List<Recommendation>? recommendations,
    this.weeklyGrade,
    this.growthScore = 0,
    this.comparisonToLastWeek,
  })  : patterns = patterns ?? [],
        recommendations = recommendations ?? [];

  factory AiWeeklyAnalysis.fromMap(Map<String, dynamic> m) =>
      AiWeeklyAnalysis(
        generatedAt: m['generatedAt'] as String?,
        model: m['model'] as String?,
        weekSummary: m['weekSummary'] ?? '',
        patterns: (m['patterns'] as List?)
                ?.map((e) => AnalysisPattern.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        recommendations: (m['recommendations'] as List?)
                ?.map((e) => Recommendation.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        weeklyGrade: m['weeklyGrade'] as String?,
        growthScore: (m['growthScore'] as num?)?.toDouble() ?? 0,
        comparisonToLastWeek: m['comparisonToLastWeek'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (generatedAt != null) 'generatedAt': generatedAt,
        if (model != null) 'model': model,
        'weekSummary': weekSummary,
        'patterns': patterns.map((p) => p.toMap()).toList(),
        'recommendations': recommendations.map((r) => r.toMap()).toList(),
        if (weeklyGrade != null) 'weeklyGrade': weeklyGrade,
        'growthScore': growthScore,
        if (comparisonToLastWeek != null)
          'comparisonToLastWeek': comparisonToLastWeek,
      };
}

/// 분석 패턴
class AnalysisPattern {
  final String type; // "positive" | "concern" | "insight"
  final String desc;

  AnalysisPattern({required this.type, required this.desc});

  factory AnalysisPattern.fromMap(Map<String, dynamic> m) => AnalysisPattern(
        type: m['type'] ?? 'insight',
        desc: m['desc'] ?? '',
      );

  Map<String, dynamic> toMap() => {'type': type, 'desc': desc};
}

/// AI 추천
class Recommendation {
  final String priority; // "high" | "medium" | "low"
  final String action;
  final String? rationale;

  Recommendation({
    required this.priority,
    required this.action,
    this.rationale,
  });

  factory Recommendation.fromMap(Map<String, dynamic> m) => Recommendation(
        priority: m['priority'] ?? 'medium',
        action: m['action'] ?? '',
        rationale: m['rationale'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'priority': priority,
        'action': action,
        if (rationale != null) 'rationale': rationale,
      };
}

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 4: 성장 지표 (Growth Metrics)                       ║
// ╚═══════════════════════════════════════════════════════════╝

/// 성장 지표 컨테이너
class GrowthMetrics {
  final String? lastUpdated;
  final Map<String, DailySnapshot> dailySnapshots; // 최근 90일
  final Map<String, WeeklySnapshot> weeklySnapshots;
  final List<GrowthMilestone> milestones;
  final LongTermInsight? longTermInsight;

  GrowthMetrics({
    this.lastUpdated,
    Map<String, DailySnapshot>? dailySnapshots,
    Map<String, WeeklySnapshot>? weeklySnapshots,
    List<GrowthMilestone>? milestones,
    this.longTermInsight,
  })  : dailySnapshots = dailySnapshots ?? {},
        weeklySnapshots = weeklySnapshots ?? {},
        milestones = milestones ?? [];

  /// 최근 N일 스냅샷 (정렬)
  List<MapEntry<String, DailySnapshot>> recentDays(int n) {
    final entries = dailySnapshots.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries.take(n).toList().reversed.toList();
  }

  /// 최근 주간 성장 추세
  String get trend {
    final weeks = weeklySnapshots.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    if (weeks.length < 2) return 'insufficient';
    final latest = weeks[0].value.growthScore;
    final prev = weeks[1].value.growthScore;
    if (latest > prev + 5) return 'upward';
    if (latest < prev - 5) return 'declining';
    return 'plateau';
  }

  factory GrowthMetrics.fromMap(Map<String, dynamic> m) {
    final dailyRaw =
        m['dailySnapshots'] as Map<String, dynamic>? ?? {};
    final weeklyRaw =
        m['weeklySnapshots'] as Map<String, dynamic>? ?? {};

    return GrowthMetrics(
      lastUpdated: m['lastUpdated'] as String?,
      dailySnapshots: dailyRaw.map((k, v) => MapEntry(
          k, DailySnapshot.fromMap(Map<String, dynamic>.from(v as Map)))),
      weeklySnapshots: weeklyRaw.map((k, v) => MapEntry(
          k, WeeklySnapshot.fromMap(Map<String, dynamic>.from(v as Map)))),
      milestones: (m['milestones'] as List?)
              ?.map((e) => GrowthMilestone.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      longTermInsight: m['longTermInsight'] != null
          ? LongTermInsight.fromMap(
              Map<String, dynamic>.from(m['longTermInsight'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        if (lastUpdated != null) 'lastUpdated': lastUpdated,
        'dailySnapshots':
            dailySnapshots.map((k, v) => MapEntry(k, v.toMap())),
        'weeklySnapshots':
            weeklySnapshots.map((k, v) => MapEntry(k, v.toMap())),
        'milestones': milestones.map((m) => m.toMap()).toList(),
        if (longTermInsight != null)
          'longTermInsight': longTermInsight!.toMap(),
      };
}

/// 일별 스냅샷
class DailySnapshot {
  final int studyMin;
  final String grade;
  final double gradeScore;
  final double taskCompletion;
  final double habitCompletion;
  final double wakeScore;
  final double focusScore;
  final double consistencyScore;
  final double growthScore; // 종합

  DailySnapshot({
    this.studyMin = 0,
    this.grade = 'F',
    this.gradeScore = 0,
    this.taskCompletion = 0,
    this.habitCompletion = 0,
    this.wakeScore = 0,
    this.focusScore = 0,
    this.consistencyScore = 0,
    this.growthScore = 0,
  });

  factory DailySnapshot.fromMap(Map<String, dynamic> m) => DailySnapshot(
        studyMin: (m['studyMin'] as num?)?.toInt() ?? 0,
        grade: m['grade'] ?? 'F',
        gradeScore: (m['gradeScore'] as num?)?.toDouble() ?? 0,
        taskCompletion: (m['taskCompletion'] as num?)?.toDouble() ?? 0,
        habitCompletion: (m['habitCompletion'] as num?)?.toDouble() ?? 0,
        wakeScore: (m['wakeScore'] as num?)?.toDouble() ?? 0,
        focusScore: (m['focusScore'] as num?)?.toDouble() ?? 0,
        consistencyScore: (m['consistencyScore'] as num?)?.toDouble() ?? 0,
        growthScore: (m['growthScore'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'studyMin': studyMin,
        'grade': grade,
        'gradeScore': gradeScore,
        'taskCompletion': taskCompletion,
        'habitCompletion': habitCompletion,
        'wakeScore': wakeScore,
        'focusScore': focusScore,
        'consistencyScore': consistencyScore,
        'growthScore': growthScore,
      };
}

/// 주간 스냅샷
class WeeklySnapshot {
  final int avgStudyMin;
  final double avgGrade;
  final double growthScore;

  WeeklySnapshot({
    this.avgStudyMin = 0,
    this.avgGrade = 0,
    this.growthScore = 0,
  });

  factory WeeklySnapshot.fromMap(Map<String, dynamic> m) => WeeklySnapshot(
        avgStudyMin: (m['avgStudyMin'] as num?)?.toInt() ?? 0,
        avgGrade: (m['avgGrade'] as num?)?.toDouble() ?? 0,
        growthScore: (m['growthScore'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'avgStudyMin': avgStudyMin,
        'avgGrade': avgGrade,
        'growthScore': growthScore,
      };
}

/// 성장 마일스톤
class GrowthMilestone {
  final String date;
  final String type; // "streak" | "exam" | "habit" | "grade" | "custom"
  final String desc;

  GrowthMilestone({
    required this.date,
    required this.type,
    required this.desc,
  });

  String get emoji {
    switch (type) {
      case 'streak': return '🔥';
      case 'exam': return '📝';
      case 'habit': return '✅';
      case 'grade': return '⭐';
      default: return '🏁';
    }
  }

  factory GrowthMilestone.fromMap(Map<String, dynamic> m) => GrowthMilestone(
        date: m['date'] ?? '',
        type: m['type'] ?? 'custom',
        desc: m['desc'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'type': type,
        'desc': desc,
      };
}

/// AI 장기 인사이트
class LongTermInsight {
  final String? generatedAt;
  final String overallTrajectory; // "upward" | "plateau" | "declining"
  final List<String> keyStrengths;
  final List<String> keyWeaknesses;
  final String? strategicAdvice;

  LongTermInsight({
    this.generatedAt,
    this.overallTrajectory = 'plateau',
    List<String>? keyStrengths,
    List<String>? keyWeaknesses,
    this.strategicAdvice,
  })  : keyStrengths = keyStrengths ?? [],
        keyWeaknesses = keyWeaknesses ?? [];

  String get trajectoryEmoji {
    switch (overallTrajectory) {
      case 'upward': return '📈';
      case 'declining': return '📉';
      default: return '➡️';
    }
  }

  factory LongTermInsight.fromMap(Map<String, dynamic> m) => LongTermInsight(
        generatedAt: m['generatedAt'] as String?,
        overallTrajectory: m['overallTrajectory'] ?? 'plateau',
        keyStrengths: (m['keyStrengths'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        keyWeaknesses: (m['keyWeaknesses'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        strategicAdvice: m['strategicAdvice'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (generatedAt != null) 'generatedAt': generatedAt,
        'overallTrajectory': overallTrajectory,
        'keyStrengths': keyStrengths,
        'keyWeaknesses': keyWeaknesses,
        if (strategicAdvice != null) 'strategicAdvice': strategicAdvice,
      };
}
