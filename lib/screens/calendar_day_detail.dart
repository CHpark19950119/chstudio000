part of 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════
/// CALENDAR — 선택 날짜 상세 + Plan 카드
/// ═══════════════════════════════════════════════════
extension _CalendarDayDetail on _CalendarScreenState {
  // ══════════════════════════════════════════
  //  선택된 날짜 상세 카드
  // ══════════════════════════════════════════

  Widget _buildSelectedDayCard() {
    String dateLabel;
    try {
      dateLabel = DateFormat('M월 d일 (E)', 'ko').format(_selectedDate);
    } catch (_) {
      const labels = ['일', '월', '화', '수', '목', '금', '토'];
      dateLabel = '${_selectedDate.month}월 ${_selectedDate.day}일 (${labels[_selectedDate.weekday % 7]})';
    }
    final now = DateTime.now();
    final diff = _selectedDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    final diffLabel = diff == 0 ? '오늘' : diff > 0 ? 'D-$diff' : 'D+${-diff}';
    final memos = _selectedMemos;
    final journals = _journalsForDate(_selectedDateStr);

    // ★ Plan 데이터
    final planDDays = StudyPlanData.ddaysForDate(_selectedDateStr);
    final planSub = StudyPlanData.subPeriodForDate(_selectedDateStr);
    final planEval = StudyPlanData.evaluationForDate(_selectedDateStr);
    final dailyPlan = StudyPlanData.dailyPlanForDate(_selectedDateStr);

    final isEmpty = memos.isEmpty && journals.isEmpty
        && _selectedStudyRecord == null && planDDays.isEmpty && planSub == null
        && dailyPlan == null
        && _selectedCustomTasks.isEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withOpacity(0.15)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 날짜 헤더
        Row(children: [
          Text(dateLabel, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: _textMain)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: diff == 0 ? _accent.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Text(diffLabel, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: diff == 0 ? _accent : _textMuted))),
          const SizedBox(width: 6),
          // 쉬는날 토글
          GestureDetector(
            onTap: () async {
              final ds = _selectedDateStr;
              final isNowRest = await _fb.toggleRestDay(ds);
              if (isNowRest) { _restDays.add(ds); } else { _restDays.remove(ds); }
              _safeSetState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _restDays.contains(_selectedDateStr)
                    ? const Color(0xFF64748B).withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _restDays.contains(_selectedDateStr)
                    ? const Color(0xFF64748B).withOpacity(0.3) : _border.withOpacity(0.3))),
              child: Text(
                _restDays.contains(_selectedDateStr) ? '😴 쉬는날' : '😴',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _restDays.contains(_selectedDateStr)
                      ? const Color(0xFF64748B) : _textMuted))),
          ),
        ]),

        // ── ★ Plan: 시험 D-Day ──
        if (planDDays.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...planDDays.map((dd) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                dd.color.withOpacity(0.08), dd.color.withOpacity(0.03)]),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: dd.color, width: 3))),
            child: Row(children: [
              const Text('🎯', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dd.name, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: dd.color)),
                Text(dd.dDayLabel, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _textSub)),
              ])),
            ]),
          )),
        ],

        // ── ★ 2-B: 일일계획 카드 (정적 시드) ──
        if (dailyPlan != null) ...[
          const SizedBox(height: 10),
          _buildDailyPlanCard(dailyPlan),
        ],

        // ── ★ Plan: 현재 기간/서브기간 ──
        if (planSub != null && dailyPlan == null) ...[
          const SizedBox(height: 10),
          _buildSubPeriodCard(planSub),
        ],

        // ── ★ Plan: 평가 ──
        if (planEval != null) ...[
          const SizedBox(height: 10),
          _buildEvalCard(planEval),
        ],

        // ── 학습 기록 요약 ──
        if (_selectedStudyRecord != null && _selectedStudyRecord!.effectiveMinutes > 0) ...[
          const SizedBox(height: 14),
          _buildStudySummaryRow(),
        ],

        // ── 포커스 사이클 ──
        if (_selectedFocusCycles.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildFocusCyclesList(),
        ],

        // ── 시간 기록 ──
        if (_selectedTimeRecord != null) ...[
          const SizedBox(height: 12),
          _buildTimeRecordRow(),
        ],

        // ── 메모 ──
        if (memos.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('💡', '메모'),
          const SizedBox(height: 6),
          ...memos.map(_memoTile),
        ],

        // ── ★ 1-B Fix: 저널 (간결 + 웹앱 링크) ──
        if (journals.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('📝', '저널'),
          const SizedBox(height: 6),
          ...journals.map(_journalTile),
        ],

        // ── ★ 2-C: 커스텀 학습과제 ──
        const SizedBox(height: 14),
        _buildCustomTasksSection(),

        // ── ★ 학습 계획 전체보기 버튼 ──
        const SizedBox(height: 14),
        _buildPlanOverviewButton(),

        if (isEmpty && _selectedCustomTasks.isEmpty) ...[
          const SizedBox(height: 20),
          Center(child: Column(children: [
            const Text('📭', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text('기록이 없습니다', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _textMuted)),
          ])),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ 2-B: 일일계획 카드
  // ══════════════════════════════════════════

  Widget _buildDailyPlanCard(PlanDailyPlan plan) {
    final tagColor = StudyPlanData.tagColor(plan.tag ?? 'rest');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tagColor.withOpacity(_dk ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tagColor.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 태그 뱃지 + 제목 + D-라벨
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tagColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text(_tagLabel(plan.tag), style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: tagColor))),
          const SizedBox(width: 8),
          Expanded(child: Text(plan.title ?? '일일 계획', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _textMain))),
          if (plan.label != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6)),
              child: Text(plan.label!, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: tagColor))),
        ]),
        // 코칭 메시지 (말풍선)
        if (plan.coaching != null && plan.coaching!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border.withOpacity(0.1))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💬 ', style: TextStyle(fontSize: 11)),
              Expanded(child: Text(plan.coaching!, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w500,
                color: _textSub, height: 1.5, fontStyle: FontStyle.italic))),
            ]),
          ),
        ],
        // 태스크 목록
        if (plan.tasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...plan.tasks.map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📋 ', style: TextStyle(fontSize: 10, color: _textMuted)),
              Expanded(child: Text(task, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: _textMain, height: 1.3))),
            ]),
          )),
        ],
        // 체크포인트
        if (plan.checkpoint != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(_dk ? 0.08 : 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.15))),
            child: Row(children: [
              const Text('📌 ', style: TextStyle(fontSize: 10)),
              Expanded(child: Text(plan.checkpoint!, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: _textMain))),
            ]),
          ),
        ],
      ]),
    );
  }

  String _tagLabel(String? tag) {
    switch (tag) {
      case 'data': return '자료해석';
      case 'lang': return '언어논리';
      case 'sit': return '상황판단';
      case 'exam': return '모의고사';
      case 'test': return '실전모의';
      case 'rest': return '휴식';
      default: return tag ?? '일반';
    }
  }


  Widget _buildSubPeriodCard(PlanSubPeriod planSub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.02) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📋', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(planSub.name, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
          if (planSub.instructor != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6)),
              child: Text(planSub.instructor!, style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
          ],
        ]),
        const SizedBox(height: 6),
        Text(planSub.primaryGoal, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: _textSub, height: 1.4)),
        if (planSub.checkpoints.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: planSub.checkpoints.map((cp) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border.withOpacity(0.1))),
              child: Text('☑ $cp', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w500, color: _textMuted)),
            )).toList()),
        ],
      ]),
    );
  }

  Widget _buildEvalCard(dynamic planEval) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2).withOpacity(_dk ? 0.05 : 1),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Color(0xFFEF4444), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📊', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(planEval.title as String, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
        ]),
        if (planEval.result != null) ...[
          const SizedBox(height: 4),
          Text(planEval.result as String, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
        ],
        if (planEval.strategy != null) ...[
          const SizedBox(height: 4),
          Text('→ ${planEval.strategy}', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500, color: _textSub)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ 2-C: 커스텀 학습과제 섹션
  // ══════════════════════════════════════════

  Widget _buildCustomTasksSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _sectionLabel('📝', '학습과제'),
        const Spacer(),
        GestureDetector(
          onTap: _addCustomTask,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 12, color: _accent),
              const SizedBox(width: 2),
              Text('추가', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _accent)),
            ]),
          ),
        ),
      ]),
      if (_selectedCustomTasks.isNotEmpty) ...[
        const SizedBox(height: 6),
        ...List.generate(_selectedCustomTasks.length, (i) {
          final task = _selectedCustomTasks[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border.withOpacity(0.1))),
            child: Row(children: [
              Text('📋', style: TextStyle(fontSize: 11, color: _textMuted)),
              const SizedBox(width: 6),
              Expanded(child: Text(task, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: _textMain))),
              GestureDetector(
                onTap: () => _editCustomTask(i, task),
                child: Icon(Icons.edit_outlined, size: 14, color: _textMuted)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _deleteCustomTask(i),
                child: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red.shade300)),
            ]),
          );
        }),
      ] else ...[
        const SizedBox(height: 4),
        Text('등록된 학습과제가 없습니다', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w500, color: _textMuted)),
      ],
    ]);
  }

  Future<void> _addCustomTask() async {
    final ctrl = TextEditingController();
    final result = await _showTaskDialog('학습과제 추가', ctrl);
    if (result != null && result.trim().isNotEmpty) {
      await _fb.addCustomStudyTask(_selectedDateStr, result.trim());
      _selectedCustomTasks = await _fb.getCustomStudyTasks(_selectedDateStr);
      _safeSetState(() {});
    }
  }

  Future<void> _editCustomTask(int index, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await _showTaskDialog('학습과제 수정', ctrl);
    if (result != null && result.trim().isNotEmpty) {
      await _fb.editCustomStudyTask(_selectedDateStr, index, result.trim());
      _selectedCustomTasks = await _fb.getCustomStudyTasks(_selectedDateStr);
      _safeSetState(() {});
    }
  }

  Future<void> _deleteCustomTask(int index) async {
    await _fb.deleteCustomStudyTask(_selectedDateStr, index);
    _selectedCustomTasks = await _fb.getCustomStudyTasks(_selectedDateStr);
    _safeSetState(() {});
  }

  Future<String?> _showTaskDialog(String title, TextEditingController ctrl) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 16, bottom: sheetBottomPad(ctx, extra: 16)),
        decoration: BoxDecoration(
          color: _dk ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, autofocus: true,
            style: TextStyle(fontSize: 14, color: _textMain),
            decoration: InputDecoration(
              hintText: '학습과제 내용...',
              hintStyle: TextStyle(color: _textMuted),
              filled: true,
              fillColor: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 44, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: BotanicalColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  ★ 학습 계획 전체보기 버튼
  // ══════════════════════════════════════════

  Widget _buildPlanOverviewButton() {
    return GestureDetector(
      onTap: _showPlanOverview,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFF6366F1).withOpacity(_dk ? 0.08 : 0.05),
            const Color(0xFF8B5CF6).withOpacity(_dk ? 0.04 : 0.02),
          ]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.15))),
        child: Row(children: [
          const Text('📋', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('학습 계획 전체보기', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
            Text('기간·과목·분기·평가 전체 확인', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: _textMuted)),
          ])),
          Icon(Icons.chevron_right_rounded, size: 20,
            color: const Color(0xFF6366F1).withOpacity(0.5)),
        ]),
      ),
    );
  }


}
