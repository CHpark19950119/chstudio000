part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — COMPASS 포탈 + 습관 큐 집중 카드 + 수험표 OCR
/// ⚠️ 네비바 충돌 금지
/// ═══════════════════════════════════════════════════
extension _HomeOrderSection on _HomeScreenState {

   // ── ORDER PORTAL — 라이트 컴팩트 COMPASS 카드 ──
  Widget _orderPortalChip() {
    final p1 = _orderData?.primaryGoal;
    final p2 = _orderData?.secondaryGoal;
    final nextExam = _examTickets.isNotEmpty ? _examTickets.first : null;
    final focusHabits = _orderData?.focusHabits ?? [];
    final goals = <MapEntry<int, OrderGoal>>[
      if (p1 != null) MapEntry(1, p1),
      if (p2 != null) MapEntry(2, p2),
    ];
    final goalsDone = goals.where((e) => e.value.progress >= 100).length;

    // 테마 색상
    final cardBg = _dk ? const Color(0xFF1A1A2E) : Colors.white;
    final borderC = _dk ? const Color(0xFF2D2D44) : const Color(0xFFE8E4DF);
    final subtleBg = _dk ? Colors.white.withOpacity(0.04) : const Color(0xFFF8F7F5);
    final subtleBorder = _dk ? Colors.white.withOpacity(0.08) : const Color(0xFFEEE9E2);
    final labelC = _dk ? Colors.white.withOpacity(0.4) : const Color(0xFF94A3B8);
    final mainC = _dk ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const OrderScreen(),
            transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          )).then((_) => _load());
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderC),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ═══ 헤더: COMPASS + D-day 뱃지 + > 화살표 ═══
          Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('COMPASS', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: mainC, letterSpacing: 1.2)),
            const Spacer(),
            if (nextExam != null && nextExam.dDayLabel.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _dk ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('시험 ', style: TextStyle(
                    fontSize: 11, color: const Color(0xFFDC2626))),
                  Text(nextExam.dDayLabel, style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: Color(0xFFDC2626))),
                ]),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded,
              size: 18, color: labelC),
          ]),

          // ═══ 습관: 최대 4개, 2열 동적 그리드 ═══
          if (focusHabits.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(builder: (ctx, constraints) {
              final habits = focusHabits.take(4).toList();
              final cardW = (constraints.maxWidth - 8) / 2;
              // 2열 Row 쌍으로 구성
              final rows = <Widget>[];
              for (int i = 0; i < habits.length; i += 2) {
                final row = Row(children: [
                  SizedBox(
                    width: cardW,
                    child: GestureDetector(
                      onTap: () => _toggleHabit(habits[i]),
                      child: _focusHabitCard(habits[i], subtleBg, subtleBorder, labelC, mainC, cardW))),
                  if (i + 1 < habits.length) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: cardW,
                      child: GestureDetector(
                        onTap: () => _toggleHabit(habits[i + 1]),
                        child: _focusHabitCard(habits[i + 1], subtleBg, subtleBorder, labelC, mainC, cardW))),
                  ],
                ]);
                if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
                rows.add(row);
              }
              return Column(children: rows);
            }),
          ],

          // ═══ 목표 ═══
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 14),
            _compassDivider(borderC),
            const SizedBox(height: 10),
            Row(children: [
              Text('GOALS', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: labelC, letterSpacing: 1)),
              const Spacer(),
              Text('$goalsDone/${goals.length}', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: labelC)),
            ]),
            const SizedBox(height: 8),
            ...goals.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _compassGoalRow(e.key, e.value, mainC, labelC, subtleBg),
            )),
            if (goals.isNotEmpty && goals.first.value.dDayLabel.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Text(goals.first.value.dDayLabel, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: labelC)),
              ),
          ],

          // ═══ 투두 요약 ═══
          if (_todayTodos != null && _todayTodos!.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            _compassDivider(borderC),
            const SizedBox(height: 10),
            _compassTodoRow(_todayTodos!, mainC, labelC),
          ],

          // ═══ 시험 정보 ═══
          const SizedBox(height: 10),
          _compassDivider(borderC),
          const SizedBox(height: 10),
          if (nextExam != null) ...[
            _compassExamRow(nextExam, mainC, labelC, subtleBg),
            const SizedBox(height: 8),
          ],
          // 수험표 업로드 버튼 (항상 표시)
          GestureDetector(
            onTap: _uploadExamTicket,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: subtleBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: subtleBorder)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('📋', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(nextExam != null ? '수험표 업데이트' : '수험표 등록 (OCR)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelC)),
              ]),
            ),
          ),

          // ═══ 데이터 없을 때 ═══
          if (focusHabits.isEmpty && goals.isEmpty && nextExam == null) ...[
            const SizedBox(height: 8),
            Text('목표 · 습관 · 질서 관리', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: labelC)),
          ],
        ]),
      ),
    );
  }

  Widget _compassDivider(Color c) => Container(
    height: 1, color: c.withOpacity(0.5));

  // ═══ 습관 카드 (2열 그리드 아이템) ═══
  Widget _focusHabitCard(OrderHabit h, Color bg, Color border, Color label, Color main, [double? width]) {
    final todayStr = StudyDateUtils.todayKey();
    final done = h.isDoneOn(todayStr);
    final streak = h.currentStreak;

    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done
            ? const Color(0xFF22C55E).withOpacity(0.3) : border)),
      child: Row(children: [
        Text(h.emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.title, style: TextStyle(
              fontSize: 11, color: label),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 12)),
              Text(' ${streak}일', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: main)),
            ]),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFDCFCE7)
                : (_dk ? const Color(0xFF312E81) : const Color(0xFFEEF2FF)),
            borderRadius: BorderRadius.circular(6)),
          child: Text(done ? '완료' : '집중', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: done
                ? const Color(0xFF16A34A)
                : const Color(0xFF6366F1))),
        ),
      ]),
    );
  }

  /// 습관 완료 처리 (홈에서 직접 체크 — 원터치 완료만)
  void _toggleHabit(OrderHabit h) {
    final todayStr = StudyDateUtils.todayKey();

    // ★ 이미 완료 시 무시 (실수 방지 — ORDER 탭에서 수정 가능)
    if (h.isDoneOn(todayStr)) return;

    HapticFeedback.mediumImpact();
    h.completedDates.add(todayStr);
    _saveOrderData();
    _safeSetState(() {});
  }

  /// 비집중 활성 습관 미니 행 (최대 3개)
  List<Widget> _buildMiniHabitRows() {
    final habits = _orderData?.habits ?? [];
    final active = habits.where((h) =>
      h.rank != 1 && h.settledAt == null && h.rank > 0
    ).take(3).toList();
    if (active.isEmpty) return [];

    final todayStr = StudyDateUtils.todayKey();

    return active.map((h) {
      final done = h.isDoneOn(todayStr);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => _toggleHabit(h),
          child: Row(children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: done
                  ? const Color(0xFF22C55E).withOpacity(0.7)
                  : _textMuted.withOpacity(0.3)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              '${h.emoji} ${h.title}',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: done ? _textMuted : _textSub,
                decoration: done ? TextDecoration.lineThrough : null),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('🔥${h.currentStreak}', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: _textMuted)),
          ]),
        ),
      );
    }).toList();
  }

  /// ORDER 데이터 Firebase 저장 (★ Phase B: order 문서에 write)
  Future<void> _saveOrderData() async {
    if (_orderData == null) return;
    try {
      await FirebaseService().updateField('orderData', _orderData!.toMap());
    } catch (e) {
      debugPrint('[HomeOrder] orderData 저장 실패: $e');
    }
  }

  // ═══ COMPASS 내부 컴포넌트 ═══

  /// 목표 행 — 번호 뱃지 + 타이틀 + 미니 프로그레스
  Widget _compassGoalRow(int rank, OrderGoal g, Color main, Color label, Color bg) {
    final rankColors = {
      1: const Color(0xFFD97706),
      2: const Color(0xFF6366F1),
    };
    final rankBg = {
      1: _dk ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
      2: _dk ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
    };
    final c = rankColors[rank] ?? const Color(0xFF64748B);

    return Row(children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: rankBg[rank] ?? bg,
          borderRadius: BorderRadius.circular(8)),
        child: Center(child: Text('$rank', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: c))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(g.title, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500, color: main),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${g.progress}%', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        const SizedBox(height: 3),
        Container(
          width: 50, height: 3,
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.06) : const Color(0xFFE8E4DF),
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (g.progress / 100).clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(
              color: c, borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ]),
    ]);
  }

  /// 투두 요약 1줄
  Widget _compassTodoRow(TodoDaily todos, Color main, Color label) {
    final rate = todos.completionRate;
    final rateColor = rate >= 0.8
        ? const Color(0xFF22C55E)
        : rate >= 0.5
            ? const Color(0xFFFBBF24)
            : const Color(0xFFEF4444);

    return GestureDetector(
      onTap: () => _safeSetState(() => _tab = 1),
      child: Row(children: [
        const Text('✅', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text('오늘의 할일', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: main)),
        const Spacer(),
        Text('${todos.completedCount}/${todos.totalCount}', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: rateColor)),
      ]),
    );
  }

  /// 시험 정보 행
  Widget _compassExamRow(ExamTicketInfo exam, Color main, Color label, Color bg) {
    return Row(children: [
      const Text('📋', style: TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exam.examName, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: main),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          if (exam.location != null)
            Text(exam.location!, style: TextStyle(
              fontSize: 10, color: label),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      )),
      if (exam.dDayLabel.isNotEmpty)
        Text(exam.dDayLabel, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800,
          color: const Color(0xFFDC2626))),
    ]);
  }

  /// 수험표 업로드 플로우
  Future<void> _uploadExamTicket() async {
    final svc = ExamTicketService();

    // 이미지 소스 선택
    final source = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('수험표 업로드', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _sourceBtn('📷', '카메라', () => Navigator.pop(c, true))),
            const SizedBox(width: 12),
            Expanded(child: _sourceBtn('🖼️', '갤러리', () => Navigator.pop(c, false))),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
    if (source == null) return;

    // 처리 중 표시
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('🔍 수험표 분석 중...'),
      duration: Duration(seconds: 10)));

    final ticket = await svc.processExamTicket(fromCamera: source);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (ticket == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ 수험표 분석 실패'),
        backgroundColor: Color(0xFFEF4444)));
      return;
    }

    // 결과 확인/수정 다이얼로그
    await _showTicketConfirmDialog(ticket);
    _load();
  }

  Widget _sourceBtn(String emoji, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.7))),
        ]),
      ),
    );
  }

  /// 수험표 분석 결과 확인/수정 다이얼로그
  Future<void> _showTicketConfirmDialog(ExamTicketInfo ticket) async {
    final nameC = TextEditingController(text: ticket.examName);
    final dateC = TextEditingController(text: ticket.examDate ?? '');
    final timeC = TextEditingController(text: ticket.examTime ?? '');
    final locC = TextEditingController(text: ticket.location ?? '');
    final numC = TextEditingController(text: ticket.examNumber ?? '');
    final seatC = TextEditingController(text: ticket.seatNumber ?? '');

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('📋 수험표 정보', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () async {
              await ExamTicketService().deleteTicket(ticket.id);
              Navigator.pop(c);
            },
            child: const Icon(Icons.delete_outline, size: 20,
              color: Color(0xFFEF4444))),
        ]),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ticketField('시험명', nameC),
            _ticketField('시험일 (YYYY-MM-DD)', dateC),
            _ticketField('시험시간 (HH:mm)', timeC),
            _ticketField('장소', locC),
            _ticketField('수험번호', numC),
            _ticketField('좌석번호', seatC),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
            child: const Text('취소')),
          TextButton(onPressed: () async {
            ticket.examName = nameC.text;
            ticket.examDate = dateC.text.isNotEmpty ? dateC.text : null;
            ticket.examTime = timeC.text.isNotEmpty ? timeC.text : null;
            ticket.location = locC.text.isNotEmpty ? locC.text : null;
            ticket.examNumber = numC.text.isNotEmpty ? numC.text : null;
            ticket.seatNumber = seatC.text.isNotEmpty ? seatC.text : null;
            await ExamTicketService().saveTicket(ticket);
            Navigator.pop(c);
          }, child: const Text('저장')),
        ],
      ),
    );
  }

  Widget _ticketField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        style: const TextStyle(fontSize: 13)),
    );
  }

  // ══════════════════════════════════════════
  //  도구 바로가기 (하단 배치)
  // ══════════════════════════════════════════
  Widget _quickToolsRow() {
    return Row(children: [
      _quickTool('📡', 'NFC', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => NfcScreen()))
        .then((_) => _load())),
      const SizedBox(width: 8),
      _quickTool('⏰', '알람', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AlarmSettingsScreen()))
        .then((_) => _load())),
      const SizedBox(width: 8),
      _quickTool('📍', '위치', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LocationScreen()))
        .then((_) => _load())),
      const SizedBox(width: 8),
    ]);
  }

  Widget _quickTool(String emoji, String label, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border.withOpacity(0.15))),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: _textMuted)),
        ]),
      ),
    ));
  }

  Future<void> _showAddMemoDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('메모 추가', style: BotanicalTypo.heading(size: 18)),
        content: TextField(controller: controller, autofocus: true,
          decoration: const InputDecoration(hintText: '오늘의 메모...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
            child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('저장')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await AiCalendarService().addMemo(result);
      _load(); // ★ 메모 목록 갱신
    }
  }
}

/// 하루 타임라인 세그먼트 모델
class _DaySegment {
  final String start;
  final String end;
  final String label;
  final String emoji;
  final Color color;
  const _DaySegment({
    required this.start, required this.end,
    required this.label, required this.emoji, required this.color});
}

/// 시간축 마커
class _TimeMarker {
  final int min;
  final String label;
  const _TimeMarker({required this.min, required this.label});
}