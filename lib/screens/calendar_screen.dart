import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/ai_calendar_service.dart';
import '../services/firebase_service.dart';
import '../services/exam_ticket_service.dart';
import '../models/models.dart';
import '../models/order_models.dart';
import '../theme/botanical_theme.dart';
import '../data/plan_data.dart';
import 'painters.dart';

part 'calendar_day_detail.dart';
part 'calendar_study_widgets.dart';
part 'calendar_sheets.dart';

/// ═══════════════════════════════════════════════════════════════
/// 캘린더 v4 — Plan 전체보기 + 저널 웹앱 연동 + 학습과제
/// ═══════════════════════════════════════════════════════════════

class CalendarScreen extends StatefulWidget {
  final bool embedded;
  const CalendarScreen({super.key, this.embedded = false});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  final _cal = AiCalendarService();
  final _fb = FirebaseService();

  late DateTime _viewMonth;
  late DateTime _selectedDate;
  bool _loading = true;
  bool _loadLock = false;   // 중복 호출 방지 (UI 상태와 분리)

  List<CalendarEvent> _monthEvents = [];
  Map<String, List<String>> _monthMemos = {};
  List<String> _selectedMemos = [];
  TimeRecord? _selectedTimeRecord;
  StudyTimeRecord? _selectedStudyRecord;
  DailyGrade? _selectedGrade;
  List<FocusCycle> _selectedFocusCycles = [];
  List<String> _restDays = [];
  Map<String, StudyTimeRecord> _monthStudyRecords = {};
  Map<String, List<FocusCycle>> _monthFocusCycles = {};
  List<Map<String, dynamic>> _monthJournals = [];

  // ★ 2-C: 커스텀 학습과제
  List<String> _selectedCustomTasks = [];

  // ★ R2: 수험표 시험일정
  List<ExamTicketInfo> _examTickets = [];
  Map<String, List<ExamTicketInfo>> _examTicketsByDate = {};

  late AnimationController _fadeCtrl;
  late AnimationController _waveCtrl;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewMonth = DateTime(now.year, now.month);
    _selectedDate = now;
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _loadMonth();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  Future<void> _loadMonth() async {
    if (_loadLock) return; // 중복 호출 방지 (_loading과 분리)
    _loadLock = true;
    _safeSetState(() => _loading = true);
    const t = Duration(seconds: 8);

    try {
      // ★ Phase C: history → archive → study fallback
      final monthKey = DateFormat('yyyy-MM').format(_viewMonth);
      var historyData = await _fb.getMonthHistory(monthKey).timeout(t, onTimeout: () => null);

      // history 없으면 archive에서 가져오기
      if (historyData == null || (historyData['days'] as Map?)?.isEmpty != false) {
        final archiveData = await _fb.getArchive(monthKey).timeout(t, onTimeout: () => null);
        if (archiveData != null) {
          // archive 형식 → history 형식 변환
          historyData = _archiveToHistoryFormat(archiveData, monthKey);
        }
      }

      // study 문서도 로드 (today 데이터 + restDays/journals 등)
      final studyData = await _fb.getStudyData().timeout(t);

      // studyTimeRecords: history → study fallback
      try {
        _monthStudyRecords = {};
        if (historyData != null) {
          final days = historyData['days'] as Map<String, dynamic>? ?? {};
          for (final entry in days.entries) {
            final dateKey = '$monthKey-${entry.key}';
            final dayData = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
            if (dayData == null) continue;
            // studyTimeRecords (raw) fallback
            final str = dayData['studyTimeRecords'];
            if (str is Map) {
              _monthStudyRecords[dateKey] = StudyTimeRecord.fromMap(dateKey, Map<String, dynamic>.from(str));
            } else {
              // studyTime (Phase C format)
              final st = dayData['studyTime'];
              if (st is Map && st['total'] is num) {
                _monthStudyRecords[dateKey] = StudyTimeRecord(
                  date: dateKey,
                  totalMinutes: (st['total'] as num).toInt(),
                  effectiveMinutes: (st['total'] as num).toInt(),
                );
              }
            }
          }
        }
        // study doc fallback (for recent data not yet in history)
        if (studyData != null) {
          final strRaw = studyData['studyTimeRecords'] as Map<String, dynamic>?;
          if (strRaw != null) {
            for (final entry in strRaw.entries) {
              if (entry.key.startsWith(monthKey) && !_monthStudyRecords.containsKey(entry.key)) {
                _monthStudyRecords[entry.key] = StudyTimeRecord.fromMap(
                    entry.key, entry.value as Map<String, dynamic>);
              }
            }
          }
        }
      } catch (_) { _monthStudyRecords = {}; }

      // focusCycles: history → study fallback
      try {
        _monthFocusCycles = {};
        if (historyData != null) {
          final days = historyData['days'] as Map<String, dynamic>? ?? {};
          for (final entry in days.entries) {
            final dateKey = '$monthKey-${entry.key}';
            final dayData = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
            if (dayData == null) continue;
            final fc = dayData['focusSessions'] ?? dayData['focusCycles'];
            if (fc is List) {
              _monthFocusCycles[dateKey] = fc
                  .where((e) => e is Map)
                  .map((e) {
                    final m = Map<String, dynamic>.from(e as Map);
                    // history format may differ from FocusCycle
                    if (m.containsKey('id')) {
                      return FocusCycle.fromMap(m);
                    }
                    // Phase C simplified session format
                    return FocusCycle(
                      id: m['start']?.toString() ?? '',
                      date: dateKey,
                      startTime: m['start']?.toString() ?? '',
                      endTime: m['end']?.toString(),
                      subject: m['subject']?.toString() ?? '',
                      studyMin: (m['minutes'] as num?)?.toInt() ?? 0,
                      effectiveMin: (m['effectiveMin'] as num?)?.toInt() ?? (m['minutes'] as num?)?.toInt() ?? 0,
                    );
                  }).toList();
            }
          }
        }
        // study doc fallback
        final fcRaw = studyData?['focusCycles'] as Map<String, dynamic>?;
        if (fcRaw != null) {
          final year = _viewMonth.year;
          final month = _viewMonth.month;
          final daysInMonth = DateTime(year, month + 1, 0).day;
          for (int d = 1; d <= daysInMonth; d++) {
            final ds = '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
            if (fcRaw[ds] != null && !_monthFocusCycles.containsKey(ds)) {
              final dayData = fcRaw[ds] as List<dynamic>;
              _monthFocusCycles[ds] = dayData
                  .map((e) => FocusCycle.fromMap(e as Map<String, dynamic>))
                  .toList();
            }
          }
        }
      } catch (_) { _monthFocusCycles = {}; }

      try {
        final raw = studyData?['restDays'] as List<dynamic>?;
        _restDays = raw?.map((e) => e.toString()).toList() ?? [];
      } catch (_) { _restDays = []; }

      try {
        final raw = studyData?['journals'] as List<dynamic>?;
        _monthJournals = raw?.map((j) => Map<String, dynamic>.from(j as Map)).toList() ?? [];
      } catch (_) { _monthJournals = []; }

      // ── 외부 서비스 병렬 ──
      final fEvents = _cal.getAllEventsForMonth(_viewMonth.year, _viewMonth.month)
          .timeout(t, onTimeout: () => <CalendarEvent>[]);
      final fMemos = _cal.getAllMemosForMonth(_viewMonth.year, _viewMonth.month)
          .timeout(t, onTimeout: () => <String, List<String>>{});
      final fTickets = ExamTicketService().loadAllTickets()
          .timeout(t, onTimeout: () => <ExamTicketInfo>[]);

      try { _monthEvents = await fEvents; } catch (_) { _monthEvents = []; }
      try { _monthMemos = await fMemos; } catch (_) { _monthMemos = {}; }
      try {
        _examTickets = await fTickets;
        _examTicketsByDate = {};
        for (final tk in _examTickets) {
          if (tk.examDate != null) {
            _examTicketsByDate.putIfAbsent(tk.examDate!, () => []).add(tk);
          }
        }
      } catch (_) { _examTickets = []; _examTicketsByDate = {}; }

      try { await _loadSelectedDay(); } catch (_) { _selectedMemos = []; }
    } catch (e) {
      debugPrint('[Calendar] _loadMonth error: $e');
    } finally {
      _loadLock = false;
      _safeSetState(() => _loading = false);
      if (mounted) _fadeCtrl.forward(from: 0);
    }
  }

  /// archive 문서 형식 → history 형식으로 변환
  Map<String, dynamic> _archiveToHistoryFormat(Map<String, dynamic> archive, String month) {
    final days = <String, Map<String, dynamic>>{};
    final trMap = archive['timeRecords'] as Map?;
    final strMap = archive['studyTimeRecords'] as Map?;
    final fcMap = archive['focusCycles'] as Map?;
    final todosMap = archive['todos'] as Map?;
    for (final dateKey in {...?trMap?.keys, ...?strMap?.keys, ...?fcMap?.keys, ...?todosMap?.keys}) {
      final ds = dateKey.toString();
      if (ds.length < 10 || !ds.startsWith(month)) continue;
      final day = ds.substring(8, 10);
      days.putIfAbsent(day, () => {});
      if (trMap?[dateKey] != null) days[day]!['timeRecords'] = trMap![dateKey];
      if (strMap?[dateKey] != null) {
        days[day]!['studyTimeRecords'] = strMap![dateKey];
        final str = strMap[dateKey];
        if (str is Map) {
          final effMin = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
          days[day]!['studyTime'] = {'total': effMin, 'subjects': {}};
        }
      }
      if (fcMap?[dateKey] != null) days[day]!['focusSessions'] = fcMap![dateKey];
      if (todosMap?[dateKey] != null) {
        final td = todosMap![dateKey];
        if (td is Map) days[day]!['todos'] = td['items'] ?? [];
      }
    }
    return {'month': month, 'days': days};
  }

  Future<void> _loadSelectedDay() async {
    final ds = DateFormat('yyyy-MM-dd').format(_selectedDate);
    const t = Duration(seconds: 5);

    // ★ Phase B: 분리된 문서별 읽기
    final fMemos = _cal.getMemosForDate(ds).timeout(t, onTimeout: () => <String>[]);
    final fTimeRecords = _fb.getTimeRecords().timeout(t, onTimeout: () => <String, TimeRecord>{});

    try { _selectedMemos = await fMemos; } catch (_) { _selectedMemos = []; }

    try {
      final records = await fTimeRecords;
      _selectedTimeRecord = records[ds];
    } catch (_) {
      _selectedTimeRecord = null;
    }

    // focusCycles (focus 문서 or 캐시)
    _selectedFocusCycles = _monthFocusCycles[ds] ?? [];
    if (_selectedFocusCycles.isEmpty) {
      try {
        _selectedFocusCycles = await _fb.getFocusCycles(ds);
      } catch (_) {}
    }

    // customTasks (plan 문서)
    try {
      _selectedCustomTasks = await _fb.getCustomStudyTasks(ds);
    } catch (_) {
      _selectedCustomTasks = [];
    }

    // grade 계산
    _selectedStudyRecord = _monthStudyRecords[ds];
    if (_selectedStudyRecord != null && _selectedStudyRecord!.effectiveMinutes > 0) {
      _selectedGrade = DailyGrade.calculate(
        date: ds,
        wakeTime: _selectedTimeRecord?.wake,
        studyStartTime: _selectedTimeRecord?.study,
        effectiveMinutes: _selectedStudyRecord!.effectiveMinutes,
      );
    } else {
      _selectedGrade = null;
    }
  }

  void _changeMonth(int delta) {
    _safeSetState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta);
    });
    _loadMonth();
  }

  void _selectDay(DateTime day) async {
    // 같은 날짜 재탭 방지
    if (day.year == _selectedDate.year &&
        day.month == _selectedDate.month &&
        day.day == _selectedDate.day) return;
    _safeSetState(() => _selectedDate = day);
    try {
      await _loadSelectedDay().timeout(const Duration(seconds: 8));
    } catch (_) {}
    _safeSetState(() {});
  }

  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  List<CalendarEvent> get _selectedEvents =>
    _monthEvents.where((e) => e.date == _selectedDateStr).toList();

  List<Map<String, dynamic>> _journalsForDate(String ds) =>
    _monthJournals.where((j) => j['date'] == ds).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.embedded
        ? _buildContent()
        : Stack(children: [
            Positioned.fill(child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: _dk
                  ? [const Color(0xFF1C1410), const Color(0xFF0F172A)]
                  : [const Color(0xFFFDF9F2), const Color(0xFFF8FAFC)])))),
            SafeArea(child: _buildContent()),
          ]),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildContent() {
    return Column(children: [
      _buildHeader(),
      Expanded(child: _loading
        ? Center(child: CircularProgressIndicator(color: _accent))
        : FadeTransition(
            opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 8),
                _buildMonthGrid(),
                const SizedBox(height: 12),
                _buildMonthSummary(),
                const SizedBox(height: 12),
                _buildSelectedDayCard(),
                const SizedBox(height: 80),
              ],
            ),
          )),
    ]);
  }

  // ══════════════════════════════════════════
  //  헤더 — D-Day 뱃지 + 오늘 버튼
  // ══════════════════════════════════════════

  Widget _buildHeader() {
    final monthLabel = DateFormat('yyyy년 M월').format(_viewMonth);
    final nearest = StudyPlanData.nearestDDay();

    return Container(
      padding: EdgeInsets.fromLTRB(widget.embedded ? 16 : 8, 8, 16, 12),
      child: Row(children: [
        if (!widget.embedded)
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textSub)),
        if (widget.embedded) ...[
          Text('캘린더', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: _textMain)),
          const SizedBox(width: 12),
        ],
        GestureDetector(
          onTap: () => _changeMonth(-1),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.chevron_left_rounded, size: 20, color: _textSub))),
        const SizedBox(width: 8),
        Text(monthLabel, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, color: _textMain)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _changeMonth(1),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: _textSub))),
        const Spacer(),
        // 오늘 버튼
        GestureDetector(
          onTap: () {
            final now = DateTime.now();
            final newMonth = DateTime(now.year, now.month);
            _selectedDate = now;
            if (_viewMonth.year == newMonth.year && _viewMonth.month == newMonth.month) {
              // 같은 월이면 전체 리로드 스킵 → 날짜 선택만
              _selectDay(now);
            } else {
              _viewMonth = newMonth;
              _loadMonth();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('오늘', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _accent)))),
        // 가장 가까운 시험 D-Day
        if (nearest != null && nearest.daysLeft >= 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                nearest.color, nearest.color.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(10)),
            child: Text(nearest.dDayLabel, style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white))),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  월간 그리드 — 워터탱크 + 파도
  // ══════════════════════════════════════════

  Widget _buildMonthGrid() {
    final year = _viewMonth.year;
    final month = _viewMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = DateTime(year, month, 1).weekday % 7;
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final selectedStr = _selectedDateStr;

    final eventDates = <String, List<CalendarEvent>>{};
    for (final e in _monthEvents) {
      eventDates.putIfAbsent(e.date, () => []).add(e);
    }

    const weekLabels = ['일', '월', '화', '수', '목', '금', '토'];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withOpacity(0.15)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16)]),
      child: Column(children: [
        // 요일 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: List.generate(7, (i) => Expanded(
            child: Center(child: Text(weekLabels[i], style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: i == 0 ? const Color(0xFFEF4444).withOpacity(0.7)
                   : i == 6 ? const Color(0xFF3B82F6).withOpacity(0.7)
                   : _textMuted)))))),
        ),
        const SizedBox(height: 6),
        // 날짜 그리드
        ...List.generate(6, (week) {
          final cells = List.generate(7, (dow) {
            final dayIdx = week * 7 + dow - startWeekday + 1;
            if (dayIdx < 1 || dayIdx > daysInMonth) {
              return const Expanded(child: SizedBox());
            }
            final dateStr = '$year-${month.toString().padLeft(2, '0')}-${dayIdx.toString().padLeft(2, '0')}';
            return Expanded(child: _buildDayCell(
              dateStr, dayIdx, dow, todayStr, selectedStr, eventDates));
          });
          final hasValidDay = List.generate(7, (dow) {
            final dayIdx = week * 7 + dow - startWeekday + 1;
            return dayIdx >= 1 && dayIdx <= daysInMonth;
          }).any((v) => v);
          if (!hasValidDay) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: cells));
        }),
      ]),
    );
  }

  Widget _buildDayCell(String dateStr, int day, int dow,
      String todayStr, String selectedStr,
      Map<String, List<CalendarEvent>> eventDates) {
    final today = DateTime.now();
    final date = DateTime(_viewMonth.year, _viewMonth.month, day);
    final isToday = dateStr == todayStr;
    final isSelected = dateStr == selectedStr;
    final isPast = date.isBefore(DateTime(today.year, today.month, today.day));
    final isFuture = date.isAfter(DateTime(today.year, today.month, today.day));
    final events = eventDates[dateStr];
    final hasMemo = _monthMemos.containsKey(dateStr);
    final hasExam = events?.any((e) => e.type == EventType.exam) ?? false;
    final isRestDay = _restDays.contains(dateStr);
    final isSunday = dow == 0;
    final hasJournal = _journalsForDate(dateStr).isNotEmpty;

    // ★ Plan 마일스톤 체크
    final planDDays = StudyPlanData.ddaysForDate(dateStr);
    final planMilestones = StudyPlanData.milestonesForDate(dateStr);
    final hasPlanExam = planDDays.isNotEmpty || planMilestones.isNotEmpty;

    // ★ R2: 수험표 시험일정 마커
    final ticketExams = _examTicketsByDate[dateStr] ?? [];
    final hasTicketExam = ticketExams.isNotEmpty;

    // ★ 2-A: Plan 일일계획
    final dailyPlan = StudyPlanData.dailyPlanForDate(dateStr);

    // 학습시간 & 워터탱크
    final studyRec = _monthStudyRecords[dateStr];
    final studyMin = studyRec?.effectiveMinutes ?? 0;
    const targetMin = 600;
    final fillPct = studyMin > 0 ? (studyMin / targetMin).clamp(0.0, 0.88) : 0.0;

    // 과목 컬러 (FocusCycles에서 추출)
    final cycles = _monthFocusCycles[dateStr] ?? [];
    final subjectMinutes = <String, int>{};
    for (final c in cycles) {
      subjectMinutes[c.subject] = (subjectMinutes[c.subject] ?? 0) + c.effectiveMin;
    }

    final timeLabel = studyMin > 0
      ? (studyMin >= 60 ? '${studyMin ~/ 60}h${studyMin % 60 > 0 ? '${studyMin % 60}' : ''}' : '${studyMin}m')
      : '';

    return GestureDetector(
      onTap: () => _selectDay(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: isSelected
            ? _accent.withOpacity(_dk ? 0.15 : 0.08)
            : _dk ? Colors.white.withOpacity(0.02) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
              ? _accent.withOpacity(0.5)
              : isToday
                ? _accent.withOpacity(0.3)
                : (hasPlanExam || hasExam || hasTicketExam)
                  ? const Color(0xFFEF4444).withOpacity(0.25)
                  : _border.withOpacity(0.1),
            width: isSelected ? 2 : isToday ? 1.5 : (hasPlanExam || hasExam || hasTicketExam) ? 1 : 0.5),
          boxShadow: isSelected ? [
            BoxShadow(color: _accent.withOpacity(0.1), blurRadius: 8)
          ] : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // ── 워터탱크 (학습시간 비례) ──
          if (fillPct > 0 && !isFuture)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, __) => CustomPaint(
                  painter: WaterWavePainter(
                    fillPercent: fillPct,
                    phase: _waveCtrl.value,
                    waterColor: const Color(0xFF38BDF8),
                    waveColor: const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ),
          // ── 글래스 오버레이 ──
          Positioned.fill(child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.08), Colors.transparent,
                  Colors.transparent, Colors.white.withOpacity(0.03),
                ],
              ),
            ),
          )),
          // ── 콘텐츠 ──
          Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 날짜 + 시험 뱃지
                Row(children: [
                  Text('$day', style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: (hasExam || hasPlanExam || hasTicketExam) ? const Color(0xFFEF4444)
                         : isSelected ? _accent
                         : isToday ? _accent
                         : isRestDay ? _textMuted
                         : isSunday ? const Color(0xFFEF4444).withOpacity(isPast ? 0.4 : 0.8)
                         : dow == 6 ? const Color(0xFF3B82F6).withOpacity(isPast ? 0.4 : 0.8)
                         : isPast ? _textMuted.withOpacity(0.5)
                         : _textMain,
                    decoration: isRestDay ? TextDecoration.lineThrough : null,
                  )),
                  if (hasPlanExam && !hasExam)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Text('🎯', style: TextStyle(fontSize: 7))),
                  if (hasTicketExam)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Text('📋', style: TextStyle(fontSize: 7))),
                ]),
                const Spacer(),
                // 중앙: 학습시간 또는 Plan D-Day 라벨
                if (timeLabel.isNotEmpty)
                  Center(child: Text(timeLabel, style: TextStyle(
                    fontSize: studyMin >= 240 ? 14 : 12,
                    fontWeight: FontWeight.w800,
                    color: _dk ? Colors.white.withOpacity(0.9) : const Color(0xFF1E293B),
                  )))
                // ★ 2-A: Plan 일일계획 제목 표시
                else if (dailyPlan != null && dailyPlan.title != null)
                  Center(child: Text(
                    dailyPlan.title!.length > 6
                      ? '${dailyPlan.title!.substring(0, 6)}…'
                      : dailyPlan.title!,
                    style: TextStyle(
                      fontSize: 8, fontWeight: FontWeight.w600,
                      color: StudyPlanData.tagColor(dailyPlan.tag ?? 'rest').withOpacity(0.8)),
                    maxLines: 1, overflow: TextOverflow.clip))
                else if (isFuture && planDDays.isNotEmpty)
                  Center(child: Text(
                    planDDays.first.dDayLabel.length > 5
                      ? planDDays.first.dDayLabel.substring(0, 5)
                      : planDDays.first.dDayLabel,
                    style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w800,
                      color: planDDays.first.color)))
                else if (timeLabel.isEmpty && isSunday && !isFuture)
                  Center(child: Text('OFF', style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w600, color: _textMuted.withOpacity(0.4)))),
                const Spacer(),
                // ★ 2-A: Plan 태그 색상 바
                if (dailyPlan != null && dailyPlan.tag != null && timeLabel.isEmpty)
                  Container(
                    height: 2, width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: StudyPlanData.tagColor(dailyPlan.tag!).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(1))),
                // 하단: 과목 바 + 인디케이터
                if (subjectMinutes.isNotEmpty) _buildSubjectBar(subjectMinutes),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (hasMemo) _dot(const Color(0xFFF59E0B)),
                  if (events != null && events.isNotEmpty) _dot(const Color(0xFF6366F1)),
                  if (hasJournal) _dot(const Color(0xFF10B981)),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSubjectBar(Map<String, int> subjectMinutes) {
    if (subjectMinutes.isEmpty) return const SizedBox.shrink();
    final total = subjectMinutes.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      height: 3,
      margin: const EdgeInsets.only(bottom: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
      child: Row(children: subjectMinutes.entries.map((e) {
        final flex = (e.value / total * 100).round().clamp(1, 100);
        return Flexible(
          flex: flex,
          child: Container(color: BotanicalColors.subjectColor(e.key), height: 3));
      }).toList()),
    );
  }

  Widget _dot(Color c) => Container(
    width: 4, height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.7)));

  // ══════════════════════════════════════════
  //  ★ 1-C Fix: 월간 요약 — 프로그레스바 명확화
  // ══════════════════════════════════════════

  Widget _buildMonthSummary() {
    final year = _viewMonth.year;
    final month = _viewMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    int totalMin = 0, studyDays = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final ds = '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final sr = _monthStudyRecords[ds];
      if (sr != null && sr.effectiveMinutes > 0) {
        totalMin += sr.effectiveMinutes;
        studyDays++;
      }
    }
    final avgMin = studyDays > 0 ? totalMin ~/ studyDays : 0;
    final totalH = totalMin ~/ 60;
    final totalM = totalMin % 60;
    final avgH = avgMin ~/ 60;
    final avgM = avgMin % 60;

    // 현재 기간 정보
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final currentPeriod = StudyPlanData.periodForDate(todayStr);
    final currentSub = StudyPlanData.subPeriodForDate(todayStr);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📚', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text('${month}월 학습 요약', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          _summaryChip('${totalH}h${totalM > 0 ? ' ${totalM}m' : ''}', '총'),
          const SizedBox(width: 12),
          _summaryChip('${avgH}h${avgM > 0 ? '${avgM}m' : ''}', '평균'),
          const SizedBox(width: 12),
          _summaryChip('${studyDays}일', '학습'),
        ]),
        // ★ 1-C Fix: 명확한 프로그레스바로 변경
        if (currentPeriod != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.02) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border.withOpacity(0.1))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 4, height: 24,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(currentPeriod.name, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _textMain)),
                  if (currentSub != null)
                    Text(currentSub.name, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w500, color: _textMuted)),
                ])),
              ]),
              const SizedBox(height: 8),
              // ★ 수평 프로그레스바 + 명확한 라벨
              _periodProgressBar(currentPeriod, currentSub, todayStr),
            ]),
          ),
        ],
      ]),
    );
  }

  /// ★ 1-C: 기간 진행률 프로그레스바 (명확한 라벨)
  Widget _periodProgressBar(dynamic period, PlanSubPeriod? sub, String todayStr) {
    final progress = period.progressForDate(todayStr) as double;
    final progressPct = (progress * 100).round();

    // 경과일/총일 계산
    final start = DateTime.parse(sub?.start ?? period.start as String);
    final end = DateTime.parse(sub?.end ?? period.end as String);
    final today = DateTime.now();
    final totalDays = end.difference(start).inDays + 1;
    final elapsed = today.difference(start).inDays + 1;
    final remaining = end.difference(today).inDays;
    final displayName = sub?.name ?? period.name as String;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(displayName, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: _accent)),
        const Spacer(),
        Text('$elapsed/$totalDays일 ($progressPct%)', style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: _textSub)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(_accent),
          minHeight: 6)),
      const SizedBox(height: 3),
      Text(remaining >= 0 ? '남은 $remaining일' : '${-remaining}일 경과',
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: _textMuted)),
    ]);
  }

  Widget _summaryChip(String value, String label) {
    return Column(children: [
      Text(value, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w800, color: _accent)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w600, color: _textMuted)),
    ]);
  }

}