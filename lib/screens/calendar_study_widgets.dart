part of 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════
/// CALENDAR — 학습 위젯 + 시간편집 + 저널 + FAB
/// ═══════════════════════════════════════════════════
extension _CalendarStudyWidgets on _CalendarScreenState {
  // ══════════════════════════════════════════
  //  ★ 저널 → 웹앱 study 섹션 이동
  // ══════════════════════════════════════════

  // ══════════════════════════════════════════
  //  유틸 위젯들
  // ══════════════════════════════════════════

  Widget _sectionLabel(String emoji, String label) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 1, color: _textMuted)),
    ]);
  }

  Widget _buildStudySummaryRow() {
    final sr = _selectedStudyRecord!;
    final effH = sr.effectiveMinutes ~/ 60;
    final effM = sr.effectiveMinutes % 60;
    final grade = _selectedGrade;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF6366F1).withOpacity(_dk ? 0.08 : 0.04),
          const Color(0xFF8B5CF6).withOpacity(_dk ? 0.04 : 0.02),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.1))),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('순공시간', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
          const SizedBox(height: 2),
          Text('${effH > 0 ? '${effH}h ' : ''}${effM}m', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: _textMain)),
        ]),
        const Spacer(),
        if (grade != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: BotanicalColors.gradeColor(grade.grade).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(grade.grade, style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: BotanicalColors.gradeColor(grade.grade))),
              Text(GrowthMetaphor.gradeFlower(grade.grade),
                style: const TextStyle(fontSize: 12)),
            ])),
      ]),
    );
  }

  Widget _buildFocusCyclesList() {
    return Wrap(
      spacing: 6, runSpacing: 4,
      children: _selectedFocusCycles.map((c) {
        final sc = BotanicalColors.subjectColor(c.subject);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: sc.withOpacity(_dk ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sc.withOpacity(0.15))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: sc)),
            const SizedBox(width: 5),
            Text(c.subject, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: sc)),
            const SizedBox(width: 4),
            Text(_fmtMin(c.effectiveMin), style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: _textSub)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildTimeRecordRow() {
    final tr = _selectedTimeRecord!;
    final fields = <_TRField>[
      if (tr.wake != null) _TRField('🌅', '기상', 'wake', tr.wake),
      if (tr.study != null) _TRField('📖', '공부', 'study', tr.study),
      if (tr.studyEnd != null) _TRField('🏁', '종료', 'studyEnd', tr.studyEnd),
      if (tr.outing != null) _TRField('🚶', '외출', 'outing', tr.outing),
      if (tr.returnHome != null) _TRField('🏠', '귀가', 'returnHome', tr.returnHome),
      if (tr.bedTime != null) _TRField('😴', '취침', 'bedTime', tr.bedTime),
    ];
    if (fields.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8, runSpacing: 6,
      children: fields.map((f) => GestureDetector(
        onTap: () => _editCalendarTime(f.key, f.label, f.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.03) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border.withOpacity(0.15))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(f.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(f.label, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: _textMuted)),
            const SizedBox(width: 4),
            Text(f.value ?? '--', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _textMain)),
            const SizedBox(width: 4),
            Icon(Icons.edit_rounded, size: 10,
              color: _textMuted.withOpacity(0.4)),
          ]),
        ),
      )).toList(),
    );
  }

  /// ★ v10: 캘린더 시간 수정 기능
  Future<void> _editCalendarTime(String key, String label, String? current) async {
    int hour = 8, minute = 0;
    if (current != null && current.contains(':')) {
      final parts = current.split(':');
      hour = int.tryParse(parts[0]) ?? 8;
      minute = int.tryParse(parts[1]) ?? 0;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!),
    );
    if (picked == null) return;
    final newTime = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    try {
      final ds = _selectedDateStr;
      await _fb.updateField('timeRecords.$ds.$key', newTime);
      // 로컬 갱신
      final records = await _fb.getTimeRecords();
      _safeSetState(() {
        _selectedTimeRecord = records[ds];
        _selectedGrade = DailyGrade.calculate(
          date: ds, wakeTime: _selectedTimeRecord?.wake,
          studyStartTime: _selectedTimeRecord?.study,
          effectiveMinutes: _selectedStudyRecord?.effectiveMinutes ?? 0);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$label 시간이 $newTime으로 수정되었습니다'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      debugPrint('[Calendar] 시간 수정 실패: $e');
    }
  }

  String _fmtMin(int min) {
    final h = min ~/ 60; final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  Widget _eventTile(CalendarEvent event) {
    final isExam = event.type == EventType.exam;
    final c = isExam ? const Color(0xFFEF4444) : const Color(0xFF6366F1);
    return Dismissible(
      key: ValueKey(event.title),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18)),
      onDismissed: (_) async {
        await _cal.deleteEvent(event);
        _cal.invalidate();
        _loadMonth();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.withOpacity(_dk ? 0.06 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: c, width: 3))),
        child: Row(children: [
          Text(event.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(event.title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textMain))),
        ]),
      ),
    );
  }

  Widget _memoTile(String memo) {
    final isPinned = memo.startsWith('📌');
    return Dismissible(
      key: ValueKey(memo),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18)),
      onDismissed: (_) async {
        if (isPinned) {
          await _cal.deletePinnedMemo(memo.replaceFirst('📌 ', ''));
        } else {
          await _cal.deleteMemoForDate(_selectedDateStr, memo);
        }
        _selectedMemos.remove(memo);
        _safeSetState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7).withOpacity(_dk ? 0.06 : 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.12))),
        child: Row(children: [
          Text(isPinned ? '📌' : '💡', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: Text(isPinned ? memo.replaceFirst('📌 ', '') : memo,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textMain))),
        ]),
      ),
    );
  }

  /// ★ 1-B Fix: 저널 → 간결한 타입+시간 한 줄 + 탭으로 웹앱 이동
  Widget _journalTile(Map<String, dynamic> journal) {
    final createdAt = journal['createdAt'] as String? ?? '';
    final isMeal = journal['journalType'] == 'meal';
    String timeStr = '';
    try {
      timeStr = createdAt.isNotEmpty
        ? DateFormat('HH:mm').format(DateTime.parse(createdAt))
        : '';
    } catch (_) {}
    return GestureDetector(
      onTap: () => _openWebJournal(journal['date'] as String?),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(_dk ? 0.06 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(
            color: isMeal ? const Color(0xFF10B981) : const Color(0xFF8B5CF6), width: 3))),
        child: Row(children: [
          Text(isMeal ? '🍽️' : '✏️', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(isMeal ? '식사 기록' : '학습 저널', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: _textMain)),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(timeStr, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: _textMuted)),
          ],
          const Spacer(),
          Text('웹앱에서 보기', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: _accent.withOpacity(0.6))),
          const SizedBox(width: 3),
          Icon(Icons.open_in_new_rounded, size: 12, color: _accent.withOpacity(0.5)),
        ]),
      ),
    );
  }

  void _openWebJournal([String? date]) async {
    final baseUrl = 'https://cheonhong-studio.web.app/';
    final url = date != null
        ? '${baseUrl}#study?date=$date'
        : '${baseUrl}#study';
    try {
      // ★ Android Intent 직접 호출 (url_launcher 불필요)
      const platform = MethodChannel('com.cheonhong.cheonhong_studio/browser');
      await platform.invokeMethod('openUrl', {'url': url});
    } catch (_) {
      // MethodChannel 미구현 시 → URL 복사 스낵바
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('브라우저에서 열어주세요:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text(url, style: const TextStyle(fontSize: 11)),
            ],
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: '복사', onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
          }),
        ));
      }
    }
  }

  // ══════════════════════════════════════════
  //  ★ 학습 계획 전체보기 시트
  // ══════════════════════════════════════════

  void _showPlanOverview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlanOverviewSheet(dk: _dk),
    );
  }

  // ══════════════════════════════════════════
  //  FAB: 일정/메모 추가
  // ══════════════════════════════════════════

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _showAddSheet,
      backgroundColor: _accent,
      elevation: 6,
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddEventMemoSheet(
        selectedDate: _selectedDate,
        onAdded: () { _cal.invalidate(); _loadMonth(); },
      ),
    );
  }
}