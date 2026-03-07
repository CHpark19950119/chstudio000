part of 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════
/// CALENDAR — 바텀시트 (일정추가 + Plan 전체보기)
/// ═══════════════════════════════════════════════════

// ══════════════════════════════════════════
//  바텀시트: 일정/메모 추가
// ══════════════════════════════════════════

class _AddEventMemoSheet extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback onAdded;
  const _AddEventMemoSheet({required this.selectedDate, required this.onAdded});
  @override
  State<_AddEventMemoSheet> createState() => _AddEventMemoSheetState();
}

class _AddEventMemoSheetState extends State<_AddEventMemoSheet> {
  final _cal = AiCalendarService();
  final _titleCtrl = TextEditingController();
  bool _isMemo = true;
  String _emoji = '📋';
  late DateTime _date;

  @override
  void initState() { super.initState(); _date = widget.selectedDate; }
  @override
  void dispose() { _titleCtrl.dispose(); super.dispose(); }

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
  bool get _dk => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: sheetBottomPad(context, extra: 0)),
      decoration: BoxDecoration(
        color: _dk ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            _typeChip('📝 메모', true),
            const SizedBox(width: 8),
            _typeChip('📅 일정', false),
            const Spacer(),
            Text(DateFormat('M/d').format(_date), style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: _dk ? Colors.white70 : Colors.grey.shade600)),
          ]),
          const SizedBox(height: 14),
          if (!_isMemo)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: ['📋', '📚', '🎯', '📊', '🧩', '🔥', '🎉', '💪'].map((e) =>
                GestureDetector(
                  onTap: () => _safeSetState(() => _emoji = e),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _emoji == e
                        ? BotanicalColors.primary.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(e, style: const TextStyle(fontSize: 20))),
                )).toList()),
            ),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
              color: _dk ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: _isMemo ? '메모 내용 입력...' : '일정 제목 입력...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: BotanicalColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(_isMemo ? '메모 저장' : '일정 추가',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  Widget _typeChip(String label, bool isMemoType) {
    final selected = _isMemo == isMemoType;
    return GestureDetector(
      onTap: () => _safeSetState(() => _isMemo = isMemoType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
            ? BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.1)
            : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected
            ? BotanicalColors.primary.withOpacity(0.3) : Colors.grey.shade300)),
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: selected ? BotanicalColors.primary
               : _dk ? Colors.white54 : Colors.grey.shade500)),
      ),
    );
  }

  Future<void> _save() async {
    final text = _titleCtrl.text.trim();
    if (text.isEmpty) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    if (_isMemo) {
      await _cal.addMemoForDate(dateStr, text);
    } else {
      await _cal.addLocalEvent(date: dateStr, title: text, emoji: _emoji);
    }
    widget.onAdded();
    if (mounted) Navigator.pop(context);
  }
}

class _TRField {
  final String emoji, label, key;
  final String? value;
  const _TRField(this.emoji, this.label, this.key, this.value);
}

// ═══════════════════════════════════════════════════════════════
//  학습 계획 전체보기 시트
// ═══════════════════════════════════════════════════════════════

class _PlanOverviewSheet extends StatefulWidget {
  final bool dk;
  const _PlanOverviewSheet({required this.dk});
  @override
  State<_PlanOverviewSheet> createState() => _PlanOverviewSheetState();
}

class _PlanOverviewSheetState extends State<_PlanOverviewSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool get _dk => widget.dk;

  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bg = _dk ? const Color(0xFF1a2332) : const Color(0xFFFCF9F3);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        // 드래그 핸들
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: _textMuted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2)))),

        // 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            const Text('📋', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(StudyPlanData.title, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: _textMain)),
              Text('v${StudyPlanData.version} · ${StudyPlanData.description}',
                style: TextStyle(fontSize: 10, color: _textMuted)),
            ])),
          ]),
        ),

        // 탭 바
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            labelColor: _accent,
            unselectedLabelColor: _textMuted,
            tabs: const [
              Tab(text: '기간'),
              Tab(text: '과목'),
              Tab(text: '분기'),
              Tab(text: '평가'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 탭 뷰
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildPeriodsTab(),
              _buildSubjectsTab(),
              _buildScenariosTab(),
              _buildEvaluationsTab(),
            ],
          ),
        ),
        SizedBox(height: bottomPad + 12),
      ]),
    );
  }

  // ── 탭 1: 기간 (Periods + Sub-periods) ──

  Widget _buildPeriodsTab() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // D-Day 카드
        _sectionTitle('🎯 D-Day 목록'),
        const SizedBox(height: 8),
        ...StudyPlanData.ddays.where((d) => d.enabled).map((dd) =>
          _ddayRow(dd, todayStr)),
        const SizedBox(height: 20),

        // 기간별 상세
        _sectionTitle('📅 기간별 계획'),
        const SizedBox(height: 8),
        ...StudyPlanData.periods.map((period) =>
          _periodCard(period, todayStr)),
      ],
    );
  }

  Widget _ddayRow(PlanDDay dd, String today) {
    final isCurrent = dd.containsToday;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dd.primary
          ? dd.color.withOpacity(_dk ? 0.08 : 0.06)
          : (_dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
        border: dd.primary
          ? Border.all(color: dd.color.withOpacity(0.2))
          : Border.all(color: _border.withOpacity(0.1))),
      child: Row(children: [
        Container(
          width: 48, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dd.color.withOpacity(_dk ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(8)),
          child: Text(dd.dDayLabel, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: dd.color))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dd.name, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
          Text(dd.date, style: TextStyle(
            fontSize: 10, color: _textMuted)),
        ])),
        if (dd.primary)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: dd.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text('핵심', style: TextStyle(
              fontSize: 8, fontWeight: FontWeight.w800, color: dd.color))),
      ]),
    );
  }

  Widget _periodCard(PlanPeriod period, String today) {
    final isActive = period.containsDate(today);
    final progress = period.progressForDate(today);
    final color = _periodColor(period.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive
          ? color.withOpacity(_dk ? 0.06 : 0.04)
          : (_dk ? Colors.white.withOpacity(0.02) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive
          ? color.withOpacity(0.25) : _border.withOpacity(0.12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(_dk ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('Period ${period.id}', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color))),
          const SizedBox(width: 8),
          Expanded(child: Text(period.name, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _textMain))),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
              child: const Text('진행중', style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF22C55E)))),
        ]),
        const SizedBox(height: 6),
        Text('${period.start} ~ ${period.end} (${period.totalDays}일)',
          style: TextStyle(fontSize: 10, color: _textMuted)),
        const SizedBox(height: 4),
        Text(period.goal, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: _textSub, height: 1.4)),

        // 진행 바 (활성 기간만)
        if (isActive) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color))),
          const SizedBox(height: 2),
          Align(alignment: Alignment.centerRight,
            child: Text('${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color))),
        ],

        // 서브기간
        if (period.subPeriods.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...period.subPeriods.map((sp) => _subPeriodRow(sp, today, color)),
        ],
      ]),
    );
  }

  Widget _subPeriodRow(PlanSubPeriod sp, String today, Color parentColor) {
    final isActive = sp.containsDate(today);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive
          ? parentColor.withOpacity(_dk ? 0.04 : 0.03)
          : (_dk ? Colors.white.withOpacity(0.01) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(
          color: isActive ? parentColor : _border.withOpacity(0.2), width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(sp.id, style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: parentColor)),
          const SizedBox(width: 6),
          Expanded(child: Text(sp.name, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: _textMain))),
          if (sp.instructor != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: parentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4)),
              child: Text(sp.instructor!, style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w600, color: parentColor))),
          if (isActive)
            Padding(padding: const EdgeInsets.only(left: 4),
              child: Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E), shape: BoxShape.circle))),
        ]),
        const SizedBox(height: 3),
        Text('${sp.start} ~ ${sp.end} (${sp.days}일)', style: TextStyle(
          fontSize: 9, color: _textMuted)),
        const SizedBox(height: 3),
        Text(sp.primaryGoal, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w500, color: _textSub, height: 1.3)),
        // 세부 목표
        if (sp.goals.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...sp.goals.map((g) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('  · ', style: TextStyle(fontSize: 10, color: _textMuted)),
              Expanded(child: Text(g, style: TextStyle(
                fontSize: 9, color: _textSub, height: 1.3))),
            ]),
          )),
        ],
        // 체크포인트
        if (sp.checkpoints.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 3, children: sp.checkpoints.map((cp) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(_dk ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(4)),
              child: Text('☑ $cp', style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w500, color: _textMuted)),
            )).toList()),
        ],
      ]),
    );
  }

  // ── 탭 2: 과목 ──

  Widget _buildSubjectsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle('📚 목표 시험'),
        const SizedBox(height: 8),
        ...StudyPlanData.targets.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Text('🎯 ', style: TextStyle(fontSize: 11)),
            Expanded(child: Text(t, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500, color: _textMain))),
          ]),
        )),
        const SizedBox(height: 16),

        _sectionTitle('📖 연간 목표'),
        const SizedBox(height: 8),
        ...StudyPlanData.annualGoals.entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.02) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border.withOpacity(0.1))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24, height: 24, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text(e.key, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: _accent))),
            const SizedBox(width: 8),
            Expanded(child: Text(e.value, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: _textMain, height: 1.3))),
          ]),
        )),
        const SizedBox(height: 16),

        // 기간별 과목 상세
        ...StudyPlanData.periods.where((p) => p.subjects.isNotEmpty).map((period) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle('Period ${period.id}: ${period.name}'),
            const SizedBox(height: 8),
            ...period.subjects.map((subj) => _subjectCard(subj)),
            const SizedBox(height: 12),
          ]);
        }),
      ],
    );
  }

  Widget _subjectCard(PlanSubject subj) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: subj.color.withOpacity(_dk ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: subj.color, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(subj.title, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          if (subj.instructor != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: subj.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6)),
              child: Text(subj.instructor!, style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: subj.color))),
        ]),
        if (subj.period != null) ...[
          const SizedBox(height: 3),
          Text(subj.period!, style: TextStyle(fontSize: 10, color: _textMuted)),
        ],
        if (subj.curriculum.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: subj.curriculum.map((c) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.04) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: subj.color.withOpacity(0.15))),
              child: Text(c, style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w500, color: _textSub)),
            )).toList()),
        ],
      ]),
    );
  }

  // ── 탭 3: 분기 (시나리오) ──

  Widget _buildScenariosTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle('🔀 조건부 전략 분기'),
        const SizedBox(height: 4),
        Text('시험 결과에 따라 자동으로 전략이 전환됩니다.',
          style: TextStyle(fontSize: 11, color: _textMuted, height: 1.4)),
        const SizedBox(height: 14),
        ...StudyPlanData.scenarios.map(_scenarioCard),
      ],
    );
  }

  Widget _scenarioCard(PlanScenario sc) {
    final color = _scenarioColor(sc.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(_dk ? 0.05 : 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(_dk ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text(sc.id, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color))),
          const SizedBox(width: 8),
          Expanded(child: Text(sc.condition, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _textMain))),
        ]),
        const SizedBox(height: 8),

        // 트리거
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border.withOpacity(0.1))),
          child: Row(children: [
            const Text('⚡', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Expanded(child: Text('트리거: ${sc.trigger}', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: _textSub))),
          ]),
        ),
        const SizedBox(height: 8),

        // 액션
        ...sc.actions.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('→ ', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            Expanded(child: Text(a, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: _textMain, height: 1.3))),
          ]),
        )),

        // 다음 기간
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6)),
          child: Text('다음 → ${sc.nextPeriod}', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }

  // ── 탭 4: 평가 ──

  Widget _buildEvaluationsTab() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle('📊 마일스톤'),
        const SizedBox(height: 8),
        ...StudyPlanData.milestones.map((m) {
          final isPast = m.date.compareTo(todayStr) < 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isPast
                ? (_dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade50)
                : const Color(0xFFEF4444).withOpacity(_dk ? 0.05 : 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isPast
                ? _border.withOpacity(0.1)
                : const Color(0xFFEF4444).withOpacity(0.15))),
            child: Row(children: [
              Text(isPast ? '✅' : '📌', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.title, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: isPast ? _textMuted : _textMain,
                  decoration: isPast ? TextDecoration.lineThrough : null)),
                Text(m.date, style: TextStyle(fontSize: 10, color: _textMuted)),
              ])),
            ]),
          );
        }),
        const SizedBox(height: 16),

        _sectionTitle('📝 평가 일정'),
        const SizedBox(height: 8),
        ...StudyPlanData.evaluations.map((ev) {
          final isPast = ev.date.compareTo(todayStr) < 0;
          final hasResult = ev.result != null;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasResult
                ? const Color(0xFFF59E0B).withOpacity(_dk ? 0.05 : 0.03)
                : (_dk ? Colors.white.withOpacity(0.02) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hasResult
                ? const Color(0xFFF59E0B).withOpacity(0.15) : _border.withOpacity(0.1))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(isPast && hasResult ? '📊' : '📋', style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(ev.title, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _textMain))),
                Text(ev.date, style: TextStyle(fontSize: 10, color: _textMuted)),
              ]),
              if (hasResult) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(_dk ? 0.08 : 0.05),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text('결과: ${ev.result}', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: const Color(0xFFEF4444)))),
              ],
              if (ev.causes.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...ev.causes.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('  ⚠ ', style: TextStyle(fontSize: 10, color: _textMuted)),
                    Expanded(child: Text(c, style: TextStyle(
                      fontSize: 10, color: _textSub, height: 1.3))),
                  ]),
                )),
              ],
              if (ev.strategy != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.03) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.1))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('💡 ', style: TextStyle(fontSize: 10)),
                    Expanded(child: Text('전략: ${ev.strategy}', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: const Color(0xFF22C55E), height: 1.3))),
                  ]),
                ),
              ],
            ]),
          );
        }),
      ],
    );
  }

  // ── 유틸 ──

  Widget _sectionTitle(String text) {
    return Text(text, style: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w800, color: _textMain));
  }

  Color _periodColor(String id) {
    switch (id) {
      case 'A': return const Color(0xFF3B82F6);
      case 'B': return const Color(0xFF8B5CF6);
      case 'C': return const Color(0xFF22C55E);
      case 'D': return const Color(0xFFF59E0B);
      default: return const Color(0xFF6366F1);
    }
  }

  Color _scenarioColor(String id) {
    switch (id) {
      case 'CASE_A': return const Color(0xFF22C55E);
      case 'CASE_B': return const Color(0xFFF59E0B);
      case 'CASE_C': return const Color(0xFF3B82F6);
      case 'CASE_D': return const Color(0xFFEF4444);
      default: return const Color(0xFF6366F1);
    }
  }
}

extension _PlanDDayExt on PlanDDay {
  bool get containsToday {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == todayStr;
  }
}
