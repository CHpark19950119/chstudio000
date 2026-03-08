/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — ORDER PORTAL MODELS v4.0
/// 목표 · 습관(큐/순위) · 스트레스 · 루틴 · NFC 트리거 데이터 모델
/// ═══════════════════════════════════════════════════════════

enum GoalTier { sprint, race, marathon }
enum GoalArea { study, life }
enum HabitFreq { daily, weekly }
enum StressType { release, escape, alternative }
enum StressTrigger { stress, fatigue, boredom, reward, habitual }
enum PriorActivity { study, sns, lying, afterOuting, other }
enum GrowthStage { seed, sprout, tree, pillar }
enum SetbackCategory { examFail, rejection, burnout, lostMotivation, health, other }

// ═══ MILESTONE ═══
class OrderMilestone {
  final String id;
  final String text;
  bool done;
  OrderMilestone({required this.id, required this.text, this.done = false});
  factory OrderMilestone.fromMap(Map<String, dynamic> m) => OrderMilestone(
        id: m['id'] ?? 'ms_${DateTime.now().millisecondsSinceEpoch}',
        text: m['text'] ?? '', done: m['done'] ?? false);
  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'done': done};
}

// ═══ ORDER GOAL ═══
class OrderGoal {
  final String id;
  String title, desc;
  GoalTier tier;
  GoalArea area;
  int progress;
  List<OrderMilestone> milestones;
  String? deadline;
  final String createdAt;
  String? completedAt;
  String? parentGoalId;
  int priority; // 하위호환용 유지 (더 이상 홈에 표시하지 않음)
  String? failedAt;
  String? failedNote;

  OrderGoal({
    required this.id, required this.title, this.desc = '',
    this.tier = GoalTier.sprint, this.area = GoalArea.study,
    this.progress = 0, List<OrderMilestone>? milestones,
    this.deadline, String? createdAt, this.completedAt,
    this.parentGoalId, this.priority = 0,
    this.failedAt, this.failedNote,
  })  : milestones = milestones ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  bool get isCompleted => completedAt != null;
  bool get isFailed => failedAt != null;
  bool get isFinished => isCompleted || isFailed;

  int? get daysLeft {
    if (deadline == null) return null;
    final t = DateTime.tryParse(deadline!);
    if (t == null) return null;
    final now = DateTime.now();
    return DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  String get dDayLabel {
    final d = daysLeft;
    if (d == null) return '';
    if (d == 0) return 'D-Day';
    return d > 0 ? 'D-$d' : 'D+${d.abs()}';
  }

  String get tierEmoji {
    switch (tier) {
      case GoalTier.sprint:  return '⚡';
      case GoalTier.race:    return '📌';
      case GoalTier.marathon: return '🎯';
    }
  }

  String get tierLabel {
    switch (tier) {
      case GoalTier.sprint:  return '단기';
      case GoalTier.race:    return '중기';
      case GoalTier.marathon: return '장기';
    }
  }

  void recalcFromMilestones() {
    if (milestones.isEmpty) return;
    progress = (milestones.where((m) => m.done).length /
            milestones.length * 100).round();
  }

  factory OrderGoal.fromMap(Map<String, dynamic> m) => OrderGoal(
        id: m['id'] ?? 'g_${DateTime.now().millisecondsSinceEpoch}',
        title: m['title'] ?? '', desc: m['desc'] ?? '',
        tier: _parseTier(m['tier'] ?? m['category']),
        area: m['area'] == 'life' ? GoalArea.life : GoalArea.study,
        progress: (m['progress'] as num?)?.toInt() ?? 0,
        milestones: (m['milestones'] as List?)
            ?.map((e) => OrderMilestone.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
        deadline: m['deadline'] as String?,
        createdAt: m['createdAt'] as String?,
        completedAt: m['completedAt'] as String?,
        parentGoalId: m['parentGoalId'] as String?,
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        failedAt: m['failedAt'] as String?,
        failedNote: m['failedNote'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'desc': desc,
        'tier': tier.name, 'area': area.name, 'progress': progress,
        'milestones': milestones.map((m) => m.toMap()).toList(),
        if (deadline != null) 'deadline': deadline,
        'createdAt': createdAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (parentGoalId != null) 'parentGoalId': parentGoalId,
        'priority': priority,
        if (failedAt != null) 'failedAt': failedAt,
        if (failedNote != null) 'failedNote': failedNote,
      };

  static GoalTier _parseTier(dynamic v) {
    if (v == 'race') return GoalTier.race;
    if (v == 'marathon') return GoalTier.marathon;
    return GoalTier.sprint;
  }
}

// ═══ STREAK RECORD ═══
class StreakRecord {
  final String startDate;
  final String endDate;
  final int length;
  String? breakReason; // 끊김 이유

  StreakRecord({
    required this.startDate,
    required this.endDate,
    required this.length,
    this.breakReason,
  });

  factory StreakRecord.fromMap(Map<String, dynamic> m) => StreakRecord(
        startDate: m['startDate'] ?? '',
        endDate: m['endDate'] ?? '',
        length: (m['length'] as num?)?.toInt() ?? 0,
        breakReason: m['breakReason'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'startDate': startDate,
        'endDate': endDate,
        'length': length,
        if (breakReason != null) 'breakReason': breakReason,
      };
}

// ═══ ORDER HABIT (v4: 순위 큐 시스템) ═══
class OrderHabit {
  final String id;
  String title, emoji;
  HabitFreq freq;
  int targetPerWeek;
  List<String> completedDates;
  String? nfcTagId;
  final String createdAt;
  bool archived;

  /// ★ v4: 습관 큐 순위
  /// 0 = 미지정, 1 = 집중(포커스), 2 = 대기2순위, 3 = 대기3순위...
  int rank;

  /// ★ v4: 목표 연속 일수 (기본 21일 = 습관 정착 기준)
  int targetDays;

  /// ★ v4: 정착 완료 일시
  String? settledAt;

  /// ★ v5: 연속일 이력
  List<StreakRecord> streakHistory;

  OrderHabit({
    required this.id, required this.title, this.emoji = '✅',
    this.freq = HabitFreq.daily, this.targetPerWeek = 7,
    List<String>? completedDates, this.nfcTagId,
    String? createdAt, this.archived = false,
    this.rank = 0, this.targetDays = 21, this.settledAt,
    List<StreakRecord>? streakHistory,
  })  : completedDates = completedDates ?? [],
        streakHistory = streakHistory ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  bool get isSettled => settledAt != null;
  bool get isFocus => rank == 1 && !archived && !isSettled;

  bool isDoneOn(String date) => completedDates.contains(date);

  void toggleDate(String date) {
    completedDates.contains(date)
        ? completedDates.remove(date)
        : completedDates.add(date);
  }

  int get currentStreak {
    if (completedDates.isEmpty) return 0;
    final sorted = completedDates.toList()..sort((a, b) => b.compareTo(a));
    var streak = 0;
    var d = DateTime.now();
    if (d.hour < 4) d = d.subtract(const Duration(days: 1));
    for (int i = 0; i < 365; i++) {
      final ds = _fmt(d);
      if (sorted.contains(ds)) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else if (i == 0) {
        d = d.subtract(const Duration(days: 1));
        if (sorted.contains(_fmt(d))) {
          streak++;
          d = d.subtract(const Duration(days: 1));
        } else { break; }
      } else { break; }
    }
    return streak;
  }

  int get maxStreak {
    if (completedDates.isEmpty) return 0;
    final sorted = completedDates.toList()..sort();
    int mx = 1, cur = 1;
    for (int i = 1; i < sorted.length; i++) {
      final prev = DateTime.tryParse(sorted[i - 1]);
      final curr = DateTime.tryParse(sorted[i]);
      if (prev != null && curr != null && curr.difference(prev).inDays == 1) {
        cur++;
        if (cur > mx) mx = cur;
      } else { cur = 1; }
    }
    return mx;
  }

  int get weeklyCount {
    final now = DateTime.now();
    final ws = _fmt(now.subtract(Duration(days: now.weekday - 1)));
    return completedDates.where((d) => d.compareTo(ws) >= 0).length;
  }

  double get weeklyRate =>
      (weeklyCount / (freq == HabitFreq.daily ? 7 : targetPerWeek)).clamp(0.0, 1.0);

  /// 습관 성장 단계: 1~7일 seed, 8~21일 sprout, 22~66일 tree, 67+ pillar
  GrowthStage get growthStage {
    final s = currentStreak;
    if (s >= 67) return GrowthStage.pillar;
    if (s >= 22) return GrowthStage.tree;
    if (s >= 8) return GrowthStage.sprout;
    return GrowthStage.seed;
  }

  String get growthEmoji {
    switch (growthStage) {
      case GrowthStage.seed: return '🌱';
      case GrowthStage.sprout: return '🌿';
      case GrowthStage.tree: return '🌳';
      case GrowthStage.pillar: return '🏛️';
    }
  }

  String get growthLabel {
    switch (growthStage) {
      case GrowthStage.seed: return '씨앗';
      case GrowthStage.sprout: return '새싹';
      case GrowthStage.tree: return '나무';
      case GrowthStage.pillar: return '기둥';
    }
  }

  int get daysToNext {
    final s = currentStreak;
    if (s >= 67) return 0;
    if (s >= 22) return 67 - s;
    if (s >= 8) return 22 - s;
    return 8 - s;
  }

  /// ★ v4: 정착 목표 대비 진행률 (0.0 ~ 1.0)
  double get settlementProgress =>
      (currentStreak / targetDays).clamp(0.0, 1.0);

  /// ★ v4: 정착까지 남은 일수
  int get daysToSettle =>
      (targetDays - currentStreak).clamp(0, targetDays);

  /// ★ v4: 정착 조건 달성 여부 (연속 targetDays일 이상)
  bool get canSettle => currentStreak >= targetDays && !isSettled;

  /// ★ v5: 가장 최근 끊긴 연속일 기록
  StreakRecord? get previousStreak {
    if (streakHistory.isEmpty) return null;
    return streakHistory.last;
  }

  /// ★ v5: 역대 최고 연속일
  int get bestStreak {
    final fromHistory = streakHistory.isEmpty
        ? 0 : streakHistory.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final cur = currentStreak;
    return cur > fromHistory ? cur : fromHistory;
  }

  /// ★ v5: completedDates에서 과거 연속일 이력 자동 계산
  void buildStreakHistoryFromDates() {
    if (completedDates.isEmpty) return;
    final sorted = completedDates.toList()..sort();
    final records = <StreakRecord>[];
    String start = sorted.first;
    String prev = sorted.first;
    int length = 1;

    for (int i = 1; i < sorted.length; i++) {
      final prevDt = DateTime.tryParse(prev);
      final currDt = DateTime.tryParse(sorted[i]);
      if (prevDt != null && currDt != null &&
          currDt.difference(prevDt).inDays == 1) {
        length++;
        prev = sorted[i];
      } else {
        if (length > 1) {
          records.add(StreakRecord(
            startDate: start, endDate: prev, length: length));
        }
        start = sorted[i];
        prev = sorted[i];
        length = 1;
      }
    }
    // 마지막 구간이 현재 진행 중인 연속일이 아닌 경우만 추가
    if (length > 1) {
      var now = DateTime.now();
      if (now.hour < 4) now = now.subtract(const Duration(days: 1));
      final todayStr = _fmt(now);
      final yesterdayStr = _fmt(now.subtract(const Duration(days: 1)));
      if (prev != todayStr && prev != yesterdayStr) {
        records.add(StreakRecord(
          startDate: start, endDate: prev, length: length));
      }
    }
    streakHistory = records;
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory OrderHabit.fromMap(Map<String, dynamic> m) {
    final habit = OrderHabit(
        id: m['id'] ?? 'h_${DateTime.now().millisecondsSinceEpoch}',
        title: m['title'] ?? '', emoji: m['emoji'] ?? '✅',
        freq: m['freq'] == 'weekly' ? HabitFreq.weekly : HabitFreq.daily,
        targetPerWeek: (m['targetPerWeek'] as num?)?.toInt() ?? 7,
        completedDates: (m['completedDates'] as List?)
            ?.map((e) => e.toString()).toList() ?? [],
        nfcTagId: m['nfcTagId'] as String?,
        createdAt: m['createdAt'] as String?,
        archived: m['archived'] ?? false,
        rank: (m['rank'] as num?)?.toInt() ?? 0,
        targetDays: (m['targetDays'] as num?)?.toInt() ?? 21,
        settledAt: m['settledAt'] as String?,
        streakHistory: (m['streakHistory'] as List?)
            ?.map((e) => StreakRecord.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
      );
    // 마이그레이션: streakHistory가 비어있으면 자동 계산
    if (habit.streakHistory.isEmpty && habit.completedDates.length > 1) {
      habit.buildStreakHistoryFromDates();
    }
    return habit;
  }

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'emoji': emoji,
        'freq': freq.name, 'targetPerWeek': targetPerWeek,
        'completedDates': completedDates,
        if (nfcTagId != null) 'nfcTagId': nfcTagId,
        'createdAt': createdAt, 'archived': archived,
        'rank': rank, 'targetDays': targetDays,
        if (settledAt != null) 'settledAt': settledAt,
        'streakHistory': streakHistory.map((r) => r.toMap()).toList(),
      };
}

// ═══ STRESS LOG ═══
class StressLog {
  final String id;
  StressType type;
  String timestamp;
  int duration; // 분
  StressTrigger trigger;
  PriorActivity priorActivity;
  String? alternativeUsed;
  String? note;
  String? subType; // overwatch, etc.
  final String? source;// manual, nfc, auto_poll

  StressLog({
    required this.id, this.type = StressType.release,
    String? timestamp, this.duration = 15,
    this.trigger = StressTrigger.stress,
    this.priorActivity = PriorActivity.study,
    this.alternativeUsed, this.note,
    this.subType, this.source = 'manual',
  }) : timestamp = timestamp ?? DateTime.now().toIso8601String();

  DateTime get dateTime => DateTime.tryParse(timestamp) ?? DateTime.now();

  String get typeLabel {
    switch (type) {
      case StressType.release: return 'Release';
      case StressType.escape: return 'Escape';
      case StressType.alternative: return '대체행동';
    }
  }

  String get typeEmoji {
    switch (type) {
      case StressType.release: return '🔴';
      case StressType.escape: return '🟡';
      case StressType.alternative: return '🟢';
    }
  }

  String get triggerLabel {
    switch (trigger) {
      case StressTrigger.stress: return '스트레스';
      case StressTrigger.fatigue: return '피로';
      case StressTrigger.boredom: return '무료함';
      case StressTrigger.reward: return '보상심리';
      case StressTrigger.habitual: return '습관적';
    }
  }

  String get priorLabel {
    switch (priorActivity) {
      case PriorActivity.study: return '공부';
      case PriorActivity.sns: return 'SNS';
      case PriorActivity.lying: return '누워있음';
      case PriorActivity.afterOuting: return '외출 후';
      case PriorActivity.other: return '기타';
    }
  }

  factory StressLog.fromMap(Map<String, dynamic> m) => StressLog(
        id: m['id'] ?? 'sl_${DateTime.now().millisecondsSinceEpoch}',
        type: _parseType(m['type']),
        timestamp: m['timestamp'] as String?,
        duration: (m['duration'] as num?)?.toInt() ?? 15,
        trigger: _parseTrigger(m['trigger']),
        priorActivity: _parsePrior(m['priorActivity']),
        alternativeUsed: m['alternativeUsed'] as String?,
        note: m['note'] as String?,
        subType: m['subType'] as String?,
        source: m['source'] ?? 'manual',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'type': type.name, 'timestamp': timestamp,
        'duration': duration, 'trigger': trigger.name,
        'priorActivity': priorActivity.name,
        if (alternativeUsed != null) 'alternativeUsed': alternativeUsed,
        if (note != null) 'note': note,
        if (subType != null) 'subType': subType,
        'source': source,
      };

  static StressType _parseType(dynamic v) {
    if (v == 'escape') return StressType.escape;
    if (v == 'alternative') return StressType.alternative;
    return StressType.release;
  }
  static StressTrigger _parseTrigger(dynamic v) {
    if (v == 'fatigue') return StressTrigger.fatigue;
    if (v == 'boredom') return StressTrigger.boredom;
    if (v == 'reward') return StressTrigger.reward;
    if (v == 'habitual') return StressTrigger.habitual;
    return StressTrigger.stress;
  }
  static PriorActivity _parsePrior(dynamic v) {
    if (v == 'sns') return PriorActivity.sns;
    if (v == 'lying') return PriorActivity.lying;
    if (v == 'afterOuting') return PriorActivity.afterOuting;
    if (v == 'other') return PriorActivity.other;
    return PriorActivity.study;
  }
}

// ═══ ROUTINE TARGET (이상적 NFC 시간) ═══
class RoutineTarget {
  String? wakeTime;   // HH:mm
  String? outingTime;
  String? studyTime;
  String? sleepTime;

  RoutineTarget({
    this.wakeTime = '05:30',
    this.outingTime = '07:00', this.studyTime = '08:00',
    this.sleepTime = '23:00',
  });

  factory RoutineTarget.fromMap(Map<String, dynamic> m) => RoutineTarget(
        wakeTime: m['wakeTime'] ?? '05:30',
        outingTime: m['outingTime'] ?? '07:00',
        studyTime: m['studyTime'] ?? '08:00',
        sleepTime: m['sleepTime'] ?? '23:00',
      );

  Map<String, dynamic> toMap() => {
        'wakeTime': wakeTime,
        'outingTime': outingTime, 'studyTime': studyTime,
        'sleepTime': sleepTime,
      };
}

// ═══ SETBACK LOG (좌절/실패 기록) ═══
class SetbackLog {
  final String id;
  String title;
  SetbackCategory category;
  String date;          // yyyy-MM-dd
  String? emotion;      // 감정 상태
  String? note;         // 상세 기록/소감
  String? lesson;       // 교훈/다음 행동
  String? linkedGoalId; // 연결 목표
  String timestamp;

  SetbackLog({
    required this.id, required this.title,
    this.category = SetbackCategory.other,
    String? date, this.emotion, this.note, this.lesson,
    this.linkedGoalId, String? timestamp,
  })  : date = date ?? _defaultDate(),
        timestamp = timestamp ?? DateTime.now().toIso8601String();

  static String _defaultDate() {
    var n = DateTime.now();
    if (n.hour < 4) n = n.subtract(const Duration(days: 1));
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String get categoryLabel {
    switch (category) {
      case SetbackCategory.examFail: return '시험 실패';
      case SetbackCategory.rejection: return '탈락/거절';
      case SetbackCategory.burnout: return '번아웃';
      case SetbackCategory.lostMotivation: return '동기 상실';
      case SetbackCategory.health: return '건강 문제';
      case SetbackCategory.other: return '기타';
    }
  }

  String get categoryEmoji {
    switch (category) {
      case SetbackCategory.examFail: return '📝';
      case SetbackCategory.rejection: return '🚫';
      case SetbackCategory.burnout: return '🔥';
      case SetbackCategory.lostMotivation: return '😶';
      case SetbackCategory.health: return '🏥';
      case SetbackCategory.other: return '📌';
    }
  }

  factory SetbackLog.fromMap(Map<String, dynamic> m) => SetbackLog(
        id: m['id'] ?? 'sb_${DateTime.now().millisecondsSinceEpoch}',
        title: m['title'] ?? '',
        category: _parseCat(m['category']),
        date: m['date'] as String?,
        emotion: m['emotion'] as String?,
        note: m['note'] as String?,
        lesson: m['lesson'] as String?,
        linkedGoalId: m['linkedGoalId'] as String?,
        timestamp: m['timestamp'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'category': category.name,
        'date': date, 'timestamp': timestamp,
        if (emotion != null) 'emotion': emotion,
        if (note != null) 'note': note,
        if (lesson != null) 'lesson': lesson,
        if (linkedGoalId != null) 'linkedGoalId': linkedGoalId,
      };

  static SetbackCategory _parseCat(dynamic v) {
    if (v == 'examFail') return SetbackCategory.examFail;
    if (v == 'rejection') return SetbackCategory.rejection;
    if (v == 'burnout') return SetbackCategory.burnout;
    if (v == 'lostMotivation') return SetbackCategory.lostMotivation;
    if (v == 'health') return SetbackCategory.health;
    return SetbackCategory.other;
  }
}

// ═══ STUDY EXPENSE ═══
class StudyExpense {
  final String id;
  String title;       // 예: "조훈 2025 자료해석 모의고사"
  int amount;          // 원 단위
  String category;     // 모의고사, 교재, 인강, 문구, 기타
  String date;         // yyyy-MM-dd (구매일)
  String? note;
  final String createdAt;

  static const List<String> categories = ['모의고사', '교재', '인강', '문구', '기타'];

  StudyExpense({
    required this.id, required this.title, required this.amount,
    this.category = '기타', String? date, this.note, String? createdAt,
  })  : date = date ?? _defaultDate(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  static String _defaultDate() {
    var n = DateTime.now();
    if (n.hour < 4) n = n.subtract(const Duration(days: 1));
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  factory StudyExpense.fromMap(Map<String, dynamic> m) => StudyExpense(
        id: m['id'] ?? 'exp_${DateTime.now().millisecondsSinceEpoch}',
        title: m['title'] ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        category: m['category'] ?? '기타',
        date: m['date'] as String?,
        note: m['note'] as String?,
        createdAt: m['createdAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'amount': amount,
        'category': category, 'date': date,
        if (note != null) 'note': note,
        'createdAt': createdAt,
      };
}

// ═══ ORDER DATA CONTAINER (v4) ═══
class OrderData {
  List<OrderGoal> goals;
  List<OrderHabit> habits;
  List<StressLog> stressLogs;
  List<SetbackLog> setbacks;
  RoutineTarget routineTarget;
  List<StudyExpense> expenses;

  OrderData({
    List<OrderGoal>? goals, List<OrderHabit>? habits,
    List<StressLog>? stressLogs, List<SetbackLog>? setbacks,
    RoutineTarget? routineTarget, List<StudyExpense>? expenses,
  })  : goals = goals ?? [],
        habits = habits ?? [],
        stressLogs = stressLogs ?? [],
        setbacks = setbacks ?? [],
        routineTarget = routineTarget ?? RoutineTarget(),
        expenses = expenses ?? [];

  /// 수험 비용 총액
  int get totalExpenseAmount =>
      expenses.fold(0, (sum, e) => sum + e.amount);

  /// 카테고리별 합계
  Map<String, int> get expensesByCategory {
    final map = <String, int>{};
    for (final e in expenses) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  // ─── 하위호환: 목표 순위 (deprecated, 습관으로 이관) ───
  OrderGoal? get primaryGoal {
    try { return goals.firstWhere((g) => g.priority == 1 && !g.isCompleted); }
    catch (_) { return null; }
  }
  OrderGoal? get secondaryGoal {
    try { return goals.firstWhere((g) => g.priority == 2 && !g.isCompleted); }
    catch (_) { return null; }
  }

  // ─── ★ v4: 습관 큐 시스템 ───

  /// 현재 집중 습관 (rank == 1, 미정착, 미보관) — 첫번째 반환 (하위호환)
  OrderHabit? get focusHabit {
    try {
      return habits.firstWhere(
          (h) => h.rank == 1 && !h.archived && !h.isSettled);
    } catch (_) { return null; }
  }

  /// ★ v5: 모든 집중 습관 (최대 3개)
  List<OrderHabit> get focusHabits {
    return habits
        .where((h) => h.rank == 1 && !h.archived && !h.isSettled)
        .toList();
  }

  /// 다음 대기 습관 (rank == 2)
  OrderHabit? get nextHabit {
    try {
      return habits.firstWhere(
          (h) => h.rank == 2 && !h.archived && !h.isSettled);
    } catch (_) { return null; }
  }

  /// 순위가 지정된 활성 습관 목록 (rank > 0, 미정착, 미보관)
  List<OrderHabit> get rankedHabits {
    return habits
        .where((h) => h.rank > 0 && !h.archived && !h.isSettled)
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
  }

  /// 순위 미지정 활성 습관
  List<OrderHabit> get unrankedHabits {
    return habits
        .where((h) => h.rank == 0 && !h.archived && !h.isSettled)
        .toList();
  }

  /// 정착 완료된 습관 (유지 모니터링)
  List<OrderHabit> get settledHabits {
    return habits.where((h) => h.isSettled && !h.archived).toList();
  }

  /// ★ 자동 승격: 모든 집중 습관이 정착되면 다음 순위를 1로 올림
  void promoteNextHabit() {
    final focus = focusHabits;
    if (focus.isEmpty) return;

    bool promoted = false;
    for (final h in focus) {
      if (h.canSettle) {
        h.settledAt = DateTime.now().toIso8601String();
        h.rank = 0; // 정착 → 순위 해제
        promoted = true;
      }
    }

    if (promoted && focusHabits.isEmpty) {
      // 모든 집중 습관이 정착 → 나머지 순위 1씩 올리기
      final ranked = habits
          .where((h) => h.rank > 1 && !h.archived && !h.isSettled)
          .toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      for (final h in ranked) {
        h.rank = h.rank - 1;
      }
    }
  }

  factory OrderData.fromMap(Map<String, dynamic> m) => OrderData(
        goals: (m['goals'] as List?)
            ?.map((e) => OrderGoal.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
        habits: (m['habits'] as List?)
            ?.map((e) => OrderHabit.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
        stressLogs: (m['stressLogs'] as List?)
            ?.map((e) => StressLog.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
        setbacks: (m['setbacks'] as List?)
            ?.map((e) => SetbackLog.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
        routineTarget: m['routineTarget'] != null
            ? RoutineTarget.fromMap(Map<String, dynamic>.from(m['routineTarget'] as Map))
            : RoutineTarget(),
        expenses: (m['expenses'] as List?)
            ?.map((e) => StudyExpense.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList() ?? [],
      );

  Map<String, dynamic> toMap() => {
        'goals': goals.map((g) => g.toMap()).toList(),
        'habits': habits.map((h) => h.toMap()).toList(),
        'stressLogs': stressLogs.map((s) => s.toMap()).toList(),
        'setbacks': setbacks.map((s) => s.toMap()).toList(),
        'routineTarget': routineTarget.toMap(),
        'expenses': expenses.map((e) => e.toMap()).toList(),
      };
}

// ═══ EXAM TICKET INFO (수험표/응시표 OCR 결과) ═══
class ExamTicketInfo {
  final String id;
  String examName;       // 시험명
  String? examDate;      // yyyy-MM-dd
  String? examTime;      // HH:mm
  String? location;      // 시험장소
  String? seatNumber;    // 좌석번호
  String? examNumber;    // 수험번호
  String? rawOcrText;    // OCR 원문
  String? imageUrl;      // Firebase Storage URL
  final String createdAt;

  ExamTicketInfo({
    required this.id, required this.examName,
    this.examDate, this.examTime, this.location,
    this.seatNumber, this.examNumber, this.rawOcrText,
    this.imageUrl, String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  int? get daysLeft {
    if (examDate == null) return null;
    final t = DateTime.tryParse(examDate!);
    if (t == null) return null;
    final now = DateTime.now();
    return DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  String get dDayLabel {
    final d = daysLeft;
    if (d == null) return '';
    if (d == 0) return 'D-Day';
    return d > 0 ? 'D-$d' : 'D+${d.abs()}';
  }

  factory ExamTicketInfo.fromMap(Map<String, dynamic> m) => ExamTicketInfo(
        id: m['id'] ?? 'et_${DateTime.now().millisecondsSinceEpoch}',
        examName: m['examName'] ?? '',
        examDate: m['examDate'] as String?,
        examTime: m['examTime'] as String?,
        location: m['location'] as String?,
        seatNumber: m['seatNumber'] as String?,
        examNumber: m['examNumber'] as String?,
        rawOcrText: m['rawOcrText'] as String?,
        imageUrl: m['imageUrl'] as String?,
        createdAt: m['createdAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'examName': examName,
        if (examDate != null) 'examDate': examDate,
        if (examTime != null) 'examTime': examTime,
        if (location != null) 'location': location,
        if (seatNumber != null) 'seatNumber': seatNumber,
        if (examNumber != null) 'examNumber': examNumber,
        if (rawOcrText != null) 'rawOcrText': rawOcrText,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'createdAt': createdAt,
      };
}