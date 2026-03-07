import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';

// ═══════════════════════════════════════════
//  포커스 기록 위젯 (Firebase 연동, 일별 누적)
// ═══════════════════════════════════════════

class FocusRecordsWidget extends StatefulWidget {
  final bool dk;
  final Color textMain, textMuted, textSub, border, accent;
  final VoidCallback onRefresh;

  const FocusRecordsWidget({
    super.key,
    required this.dk, required this.textMain, required this.textMuted,
    required this.textSub, required this.border, required this.accent,
    required this.onRefresh,
  });

  @override
  State<FocusRecordsWidget> createState() => _FocusRecordsWidgetState();
}

class _FocusRecordsWidgetState extends State<FocusRecordsWidget> {
  DateTime _selectedDate = DateTime.now();
  List<FocusCycle> _cycles = [];
  bool _loading = false;

  // static 캐시: 위젯 state 재생성되어도 데이터 유지
  static List<FocusCycle>? _cachedCycles;
  static String? _cachedDate;

  static const _subjects = ['자료해석', '언어논리', '상황판단', '헌법', '영어'];

  @override
  void initState() {
    super.initState();
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    // 캐시된 데이터가 있으면 즉시 사용 (스피너 없이)
    if (_cachedDate == dateStr && _cachedCycles != null) {
      _cycles = _cachedCycles!;
      _loading = false;
    } else {
      _loading = true;
    }
    _loadData();
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

  Future<void> _loadData() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    // 캐시 없을 때만 스피너 표시
    if (_cachedDate != dateStr || _cachedCycles == null) {
      _safeSetState(() => _loading = true);
    }
    final fb = FirebaseService();
    final cycles = await fb.getFocusCycles(dateStr);
    _cachedCycles = cycles;
    _cachedDate = dateStr;
    _safeSetState(() { _cycles = cycles; _loading = false; });
  }

  void _changeDate(int delta) {
    _selectedDate = _selectedDate.add(Duration(days: delta));
    _loadData();
  }

  String _fmtMin(int min) {
    final h = min ~/ 60; final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  /// ISO 또는 HH:mm 형식 → HH:mm 변환
  String _fmtTime(String? raw) {
    if (raw == null) return '--:--';
    if (raw.contains('T')) {
      try {
        final dt = DateTime.parse(raw);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    // 이미 HH:mm 형식이면 그대로
    if (raw.length >= 5 && raw.contains(':')) return raw.substring(0, 5);
    return raw;
  }

  Future<void> _deleteCycle(int index) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final removed = _cycles[index];
    final updated = List<FocusCycle>.from(_cycles)..removeAt(index);
    final fb = FirebaseService();
    await fb.overwriteFocusCycles(dateStr, updated);
    // studyTimeRecords 동기화 (삭제분 차감)
    try {
      final strs = await fb.getStudyTimeRecords();
      final existing = strs[dateStr];
      if (existing != null) {
        await fb.updateStudyTimeRecord(dateStr, StudyTimeRecord(
          date: dateStr,
          effectiveMinutes: (existing.effectiveMinutes - removed.effectiveMin).clamp(0, 1440),
          totalMinutes: (existing.totalMinutes - removed.studyMin - removed.lectureMin - removed.restMin).clamp(0, 1440),
        ));
      }
    } catch (_) {}
    _loadData();
    widget.onRefresh();
  }

  Future<void> _editCycle(int index) async {
    final c = _cycles[index];
    final dk = widget.dk;
    final bg = dk ? const Color(0xFF1a2332) : const Color(0xFFFCF9F3);
    final txt = dk ? Colors.white : const Color(0xFF1e293b);
    final muted = dk ? Colors.white54 : Colors.grey;

    String newSubject = c.subject;
    int studyMin = c.studyMin;
    int lectureMin = c.lectureMin;
    int restMin = c.restMin;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final bottomPad = MediaQuery.of(ctx).padding.bottom;
        int effMin = studyMin + (lectureMin * 0.5).round();

        return Container(
          padding: EdgeInsets.only(
            top: 16, left: 24, right: 24,
            bottom: bottomInset + bottomPad + 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: muted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('세션 수정', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: txt)),
            const SizedBox(height: 4),
            Text('${_fmtTime(c.startTime)} → ${_fmtTime(c.endTime) == '--:--' ? '진행중' : _fmtTime(c.endTime)}',
              style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 20),

            // ── 과목 선택 ──
            Align(alignment: Alignment.centerLeft,
              child: Text('과목', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: muted))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: _subjects.map((s) {
                final sc = BotanicalColors.subjectColor(s);
                final sel = newSubject == s;
                return GestureDetector(
                  onTap: () => setLocal(() => newSubject = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? sc.withOpacity(dk ? 0.15 : 0.08) : (dk ? Colors.white.withOpacity(0.03) : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? sc.withOpacity(0.4) : Colors.transparent)),
                    child: Text(s, style: TextStyle(
                      fontSize: 13, fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      color: sel ? sc : txt)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── 시간 수정 ──
            _minuteRow('📖 집중공부', studyMin, (v) => setLocal(() => studyMin = v), dk, txt, muted),
            _minuteRow('🎧 강의듣기', lectureMin, (v) => setLocal(() => lectureMin = v), dk, txt, muted),
            _minuteRow('☕ 휴식', restMin, (v) => setLocal(() => restMin = v), dk, txt, muted, maxVal: 120),
            const SizedBox(height: 12),

            // 순공 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: BotanicalColors.primary.withOpacity(dk ? 0.1 : 0.05),
                borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('순공시간: ', style: TextStyle(fontSize: 12, color: muted)),
                Text('${effMin}분', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: BotanicalColors.primary)),
              ]),
            ),
            const SizedBox(height: 16),

            // 버튼
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('취소', style: TextStyle(color: muted)))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'subject': newSubject,
                  'studyMin': studyMin,
                  'lectureMin': lectureMin,
                  'restMin': restMin,
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BotanicalColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)))),
            ]),
          ])),
        );
      }),
    );

    if (result == null) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final newEffMin = (result['studyMin'] as int) + ((result['lectureMin'] as int) * 0.5).round();
    final updated = List<FocusCycle>.from(_cycles);
    final old = updated[index];
    updated[index] = FocusCycle(
      id: old.id, date: old.date, startTime: old.startTime, endTime: old.endTime,
      subject: result['subject'] as String, segments: old.segments,
      studyMin: result['studyMin'] as int,
      lectureMin: result['lectureMin'] as int,
      effectiveMin: newEffMin,
      restMin: result['restMin'] as int);

    final fb = FirebaseService();
    await fb.overwriteFocusCycles(dateStr, updated);

    // studyTimeRecords 동기화
    try {
      final diffEff = newEffMin - old.effectiveMin;
      final diffTotal = (result['studyMin'] as int) + (result['lectureMin'] as int) +
          (result['restMin'] as int) - old.studyMin - old.lectureMin - old.restMin;
      if (diffEff != 0 || diffTotal != 0) {
        final strs = await fb.getStudyTimeRecords();
        final existing = strs[dateStr];
        if (existing != null) {
          await fb.updateStudyTimeRecord(dateStr, StudyTimeRecord(
            date: dateStr,
            effectiveMinutes: (existing.effectiveMinutes + diffEff).clamp(0, 1440),
            totalMinutes: (existing.totalMinutes + diffTotal).clamp(0, 1440),
          ));
        }
      }
    } catch (_) {}

    _loadData();
    widget.onRefresh();
  }

  Widget _minuteRow(String label, int value, ValueChanged<int> onChanged,
      bool dk, Color txt, Color muted, {int maxVal = 600}) {
    final h = value ~/ 60;
    final m = value % 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dk ? Colors.white.withOpacity(0.03) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: txt))),
          _adjBtn('-15', value >= 15 ? () => onChanged((value - 15).clamp(0, maxVal)) : null, dk),
          const SizedBox(width: 3),
          _adjBtn('-5', value >= 5 ? () => onChanged((value - 5).clamp(0, maxVal)) : null, dk),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 50),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8)),
            child: Text(
              h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}분',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                color: value > 0 ? BotanicalColors.primary : muted)),
          ),
          const SizedBox(width: 6),
          _adjBtn('+5', () => onChanged((value + 5).clamp(0, maxVal)), dk),
          const SizedBox(width: 3),
          _adjBtn('+15', () => onChanged((value + 15).clamp(0, maxVal)), dk),
        ]),
      ),
    );
  }

  Widget _adjBtn(String label, VoidCallback? onTap, bool dk) {
    final isAdd = label.startsWith('+');
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: !enabled
            ? (dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade100)
            : (isAdd ? BotanicalColors.primary.withOpacity(dk ? 0.15 : 0.08)
                     : (dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
          shape: BoxShape.circle),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
            color: !enabled ? (dk ? Colors.white24 : Colors.grey.shade400)
              : (isAdd ? BotanicalColors.primary : widget.textSub)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dk = widget.dk;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateStr;
    final wd = ['월','화','수','목','금','토','일'][_selectedDate.weekday - 1];

    int totalStudy = 0, totalLecture = 0, totalEff = 0, totalRest = 0;
    for (final c in _cycles) {
      totalStudy += c.studyMin; totalLecture += c.lectureMin;
      totalEff += c.effectiveMin; totalRest += c.restMin;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── 날짜 네비게이션 ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: dk ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.border.withOpacity(0.2)),
          boxShadow: dk ? null : [BoxShadow(
            color: Colors.black.withOpacity(0.02), blurRadius: 8)]),
        child: Row(children: [
          GestureDetector(
            onTap: () => _changeDate(-1),
            child: Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.chevron_left_rounded, size: 20, color: widget.textSub)),
          ),
          Expanded(child: Column(children: [
            Text('${_selectedDate.month}월 ${_selectedDate.day}일 ($wd)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: widget.textMain, letterSpacing: -0.3)),
            if (isToday) Text('오늘', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: BotanicalColors.primary)),
          ])),
          GestureDetector(
            onTap: isToday ? null : () => _changeDate(1),
            child: Container(width: 34, height: 34,
              decoration: BoxDecoration(
                color: isToday ? Colors.transparent
                  : (dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.chevron_right_rounded, size: 20,
                color: isToday ? Colors.transparent : widget.textSub)),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ── 일별 합계 (메쉬 그라디언트 카드) ──
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: dk
              ? [BotanicalColors.primary.withOpacity(0.08), const Color(0xFF0F172A)]
              : [BotanicalColors.primary.withOpacity(0.04), const Color(0xFFFAF8F2)]),
          border: Border.all(color: BotanicalColors.primary.withOpacity(dk ? 0.10 : 0.06))),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmtMin(totalEff), style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w900,
              color: BotanicalColors.primary, letterSpacing: -1, height: 1)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('순공시간', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: BotanicalColors.primary.withOpacity(0.6)))),
            const Spacer(),
            Text('${_cycles.length}세션', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: dk ? Colors.white38 : widget.textMuted)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _summaryPill('📖 집중', _fmtMin(totalStudy), const Color(0xFF6366F1), dk),
            const SizedBox(width: 8),
            _summaryPill('🎧 강의', _fmtMin(totalLecture), const Color(0xFF10B981), dk),
            const SizedBox(width: 8),
            _summaryPill('☕ 휴식', _fmtMin(totalRest), const Color(0xFFF59E0B), dk),
          ]),
        ]),
      ),
      const SizedBox(height: 14),

      // ── 세션 리스트 ──
      if (_loading)
        const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_cycles.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(children: [
            Icon(Icons.event_busy_rounded, size: 44,
              color: widget.textMuted.withOpacity(0.2)),
            const SizedBox(height: 10),
            Text('기록 없음', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: widget.textMuted.withOpacity(0.5))),
          ])))
      else
        ...List.generate(_cycles.length, (i) => _cycleCard(i)),
    ]);
  }

  Widget _cycleCard(int i) {
    final c = _cycles[i];
    final sc = BotanicalColors.subjectColor(c.subject);
    final dk = widget.dk;

    return Dismissible(
      key: Key('cycle_${c.id}_$i'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22)),
      confirmDismiss: (_) async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('세션 삭제', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            content: Text('${c.subject} (${_fmtTime(c.startTime)}~${c.endTime != null ? _fmtTime(c.endTime) : '진행중'})\n순공 ${_fmtMin(c.effectiveMin)}을 삭제합니다.',
              style: TextStyle(fontSize: 13, height: 1.5, color: widget.textSub)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text('취소', style: TextStyle(color: widget.textMuted))),
              TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
            ],
          ),
        );
        return confirm == true;
      },
      onDismissed: (_) => _deleteCycle(i),
      child: GestureDetector(
        onTap: () => _editCycle(i),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dk ? sc.withOpacity(0.04) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sc.withOpacity(dk ? 0.12 : 0.08)),
            boxShadow: dk ? null : [
              BoxShadow(color: sc.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Row(children: [
            Column(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [sc.withOpacity(0.2), sc.withOpacity(0.08)]),
                  borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('${i + 1}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: sc)))),
              const SizedBox(height: 4),
              Container(width: 3, height: 20,
                decoration: BoxDecoration(
                  color: sc.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sc.withOpacity(dk ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(c.subject, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: sc))),
                const SizedBox(width: 6),
                if (c.lectureMin > 0)
                  const Text('🎧', style: TextStyle(fontSize: 11)),
                const Spacer(),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_rounded, size: 12, color: widget.textMuted.withOpacity(0.5)),
                  const SizedBox(width: 2),
                  Text('수정', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    color: widget.textMuted.withOpacity(0.5))),
                ]),
              ]),
              const SizedBox(height: 6),
              Text('${_fmtTime(c.startTime)} → ${c.endTime != null ? _fmtTime(c.endTime) : '진행 중'}',
                style: TextStyle(fontSize: 12, color: widget.textSub, fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text('공부 ${c.studyMin}m · 강의 ${c.lectureMin}m · 휴식 ${c.restMin}m',
                style: TextStyle(fontSize: 10, color: widget.textMuted.withOpacity(0.6))),
              if (c.segments.isNotEmpty) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(height: 4, child: Row(
                    children: c.segments.map((seg) {
                      final segColor = seg.mode == 'rest'
                        ? const Color(0xFFF59E0B)
                        : (seg.mode == 'lecture' ? const Color(0xFF10B981) : sc);
                      return Expanded(
                        flex: seg.durationMin.clamp(1, 999),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          color: segColor.withOpacity(dk ? 0.5 : 0.3)));
                    }).toList())),
                ),
              ],
            ])),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtMin(c.effectiveMin), style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: sc, letterSpacing: -0.5)),
              const SizedBox(height: 2),
              Text('순공', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: sc.withOpacity(0.6))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _summaryPill(String label, String value, Color color, bool dk) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(dk ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(dk ? 0.10 : 0.05))),
      child: Column(children: [
        Text(value, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: color.withOpacity(0.6))),
      ]),
    ));
  }
}