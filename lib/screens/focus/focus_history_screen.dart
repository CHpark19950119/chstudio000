import 'package:flutter/material.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../services/focus_service.dart';

// ══════════════════════════════════════════
//  포커스 기록 화면 (조회/수정/삭제/수동추가)
// ══════════════════════════════════════════

class FocusHistoryScreen extends StatefulWidget {
  const FocusHistoryScreen({super.key});
  @override
  State<FocusHistoryScreen> createState() => _FocusHistoryScreenState();
}

class _FocusHistoryScreenState extends State<FocusHistoryScreen> {
  final _fb = FirebaseService();
  String _selectedDate = '';
  List<FocusCycle> _cycles = [];
  bool _loading = true;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

  @override
  void initState() {
    super.initState();
    _selectedDate = _today();
    _loadCycles();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCycles() async {
    setState(() => _loading = true);
    try {
      _cycles = await _fb.getFocusCycles(_selectedDate);
      _cycles.sort((a, b) => b.startTime.compareTo(a.startTime));
    } catch (_) {
      _cycles = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final totalEff = _cycles.fold<int>(0, (s, c) => s + c.effectiveMin);
    final totalStudy = _cycles.fold<int>(0, (s, c) => s + c.studyMin);
    final totalLecture = _cycles.fold<int>(0, (s, c) => s + c.lectureMin);
    final totalRest = _cycles.fold<int>(0, (s, c) => s + c.restMin);

    return Scaffold(
      backgroundColor: _dk ? const Color(0xFF1A1210) : const Color(0xFFFCF9F3),
      appBar: AppBar(
        title: Text('포커스 기록', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            tooltip: '수동 세션 추가',
            onPressed: _addManualSession),
        ],
      ),
      body: Column(children: [
        // ── 날짜 선택 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _changeDate(-1)),
            Expanded(child: GestureDetector(
              onTap: _pickDate,
              child: Text(_selectedDate, textAlign: TextAlign.center,
                style: BotanicalTypo.heading(size: 16, color: _textMain)),
            )),
            IconButton(icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _changeDate(1)),
          ]),
        ),

        // ── 일일 요약 ──
        if (_cycles.isNotEmpty) Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BotanicalDeco.card(_dk),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _dayStat('순공', '${totalEff}m', BotanicalColors.primary),
            _dayStat('공부', '${totalStudy}m', BotanicalColors.subjectData),
            _dayStat('강의', '${totalLecture}m', BotanicalColors.subjectVerbal),
            _dayStat('휴식', '${totalRest}m', Colors.orange),
            _dayStat('세션', '${_cycles.length}', _textSub),
          ]),
        ),
        const SizedBox(height: 12),

        // ── 세션 목록 ──
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _cycles.isEmpty
              ? Center(child: Text('이 날짜에 기록이 없습니다',
                  style: BotanicalTypo.body(size: 14, color: _textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _cycles.length,
                  itemBuilder: (_, i) => _cycleCard(_cycles[i]),
                ),
        ),
      ]),
    );
  }

  Widget _dayStat(String label, String val, Color c) {
    return Column(children: [
      Text(val, style: BotanicalTypo.number(size: 18, weight: FontWeight.w700, color: c)),
      Text(label, style: BotanicalTypo.label(size: 10, color: _textMuted)),
    ]);
  }

  Widget _cycleCard(FocusCycle cycle) {
    final c = BotanicalColors.subjectColor(cycle.subject);
    final startTime = _parseTime(cycle.startTime);
    final endTime = cycle.endTime != null ? _parseTime(cycle.endTime!) : '진행중';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(_dk ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(SubjectConfig.subjects[cycle.subject]?.emoji ?? '📚',
            style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cycle.subject, style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w700, color: _textMain)),
            Text('$startTime → $endTime', style: BotanicalTypo.label(
              size: 12, color: _textSub)),
          ])),
          Text('순공 ${cycle.effectiveMin}m', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        ]),
        const SizedBox(height: 8),
        if (cycle.segments.isNotEmpty) _segmentBar(cycle),
        const SizedBox(height: 8),
        Row(children: [
          Text('공부 ${cycle.studyMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const SizedBox(width: 10),
          Text('강의 ${cycle.lectureMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const SizedBox(width: 10),
          Text('휴식 ${cycle.restMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const Spacer(),
          GestureDetector(
            onTap: () => _editCycle(cycle),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.edit_outlined, size: 18, color: _textMuted)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _deleteCycle(cycle),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent)),
          ),
        ]),
      ]),
    );
  }

  Widget _segmentBar(FocusCycle cycle) {
    final totalMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
    if (totalMin <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(children: cycle.segments.map((s) {
          final w = s.durationMin / totalMin;
          final color = s.mode == 'study' ? BotanicalColors.primary
            : s.mode == 'lecture' ? BotanicalColors.subjectData
            : Colors.orange;
          return Expanded(
            flex: (w * 1000).round().clamp(1, 1000),
            child: Container(
              color: color.withOpacity(0.7),
              margin: const EdgeInsets.only(right: 1)),
          );
        }).toList()),
      ),
    );
  }

  String _parseTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(11, 16) : iso;
    }
  }

  void _changeDate(int delta) {
    final parts = _selectedDate.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
      .add(Duration(days: delta));
    _selectedDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    _loadCycles();
  }

  Future<void> _pickDate() async {
    final parts = _selectedDate.split('-');
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _selectedDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _loadCycles();
    }
  }

  Future<void> _editCycle(FocusCycle cycle) async {
    final subjects = SubjectConfig.subjects;
    String newSubject = cycle.subject;
    int studyMin = cycle.studyMin;
    int lectureMin = cycle.lectureMin;
    int restMin = cycle.restMin;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) {
          int effMin = studyMin + (lectureMin * 0.5).round();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('세션 수정'),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('과목 변경', style: BotanicalTypo.label(size: 13, color: _textSub)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: subjects.entries.map((e) {
                  final sel = newSubject == e.key;
                  return GestureDetector(
                    onTap: () => setDlg(() => newSubject = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? Color(e.value.colorValue).withOpacity(0.15) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: sel ? Border.all(color: Color(e.value.colorValue)) : null),
                      child: Text('${e.value.emoji} ${e.key}', style: TextStyle(
                        fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  );
                }).toList()),
              const SizedBox(height: 16),
              _minuteEditor('📖 집중공부', studyMin,
                (v) => setDlg(() => studyMin = v.clamp(0, 600))),
              _minuteEditor('🎧 강의듣기', lectureMin,
                (v) => setDlg(() => lectureMin = v.clamp(0, 600))),
              _minuteEditor('☕ 휴식', restMin,
                (v) => setDlg(() => restMin = v.clamp(0, 120)),
                maxVal: 120),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: BotanicalColors.primarySurface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('순공시간: ', style: BotanicalTypo.label(size: 12, color: _textSub)),
                  Text('${effMin}분', style: BotanicalTypo.label(
                    size: 14, weight: FontWeight.w800, color: BotanicalColors.primary)),
                ]),
              ),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.pop(dCtx, {
                'subject': newSubject,
                'studyMin': studyMin,
                'lectureMin': lectureMin,
                'restMin': restMin,
              }), child: const Text('저장')),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final newEffMin = (result['studyMin'] as int) +
          ((result['lectureMin'] as int) * 0.5).round();
      final updated = FocusCycle(
        id: cycle.id, date: cycle.date,
        startTime: cycle.startTime, endTime: cycle.endTime,
        subject: result['subject'] as String,
        segments: cycle.segments,
        studyMin: result['studyMin'] as int,
        lectureMin: result['lectureMin'] as int,
        effectiveMin: newEffMin,
        restMin: result['restMin'] as int,
      );
      await _fb.saveFocusCycle(cycle.date, updated);

      final diffEff = newEffMin - cycle.effectiveMin;
      final diffTotal = (result['studyMin'] as int) + (result['lectureMin'] as int) +
          (result['restMin'] as int) - cycle.studyMin - cycle.lectureMin - cycle.restMin;
      if (diffEff != 0 || diffTotal != 0) {
        try {
          final strs = await _fb.getStudyTimeRecords();
          final existing = strs[cycle.date];
          final newEff = (existing?.effectiveMinutes ?? 0) + diffEff;
          final newTotal = (existing?.totalMinutes ?? 0) + diffTotal;
          await _fb.updateStudyTimeRecord(cycle.date, StudyTimeRecord(
            date: cycle.date,
            effectiveMinutes: newEff.clamp(0, 1440),
            totalMinutes: newTotal.clamp(0, 1440),
          ));
        } catch (_) {}
      }
      _loadCycles();
    }
  }

  Future<void> _deleteCycle(FocusCycle cycle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('세션 삭제'),
        content: Text('이 포커스 세션을 삭제하시겠습니까?\n순공 ${cycle.effectiveMin}분이 기록에서 제거됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await FocusService().deleteFocusCycle(cycle.date, cycle.id);
      _loadCycles();
    }
  }

  Future<void> _addManualSession() async {
    final subjects = SubjectConfig.subjects;
    String subject = subjects.keys.first;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 30);
    int studyMin = 90;
    int lectureMin = 0;
    int restMin = 0;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (_, setDlg) {
        int effMin = studyMin + (lectureMin * 0.5).round();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('수동 세션 추가'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, runSpacing: 8,
              children: subjects.entries.map((e) {
                final sel = subject == e.key;
                return GestureDetector(
                  onTap: () => setDlg(() => subject = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? Color(e.value.colorValue).withOpacity(0.15) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: sel ? Border.all(color: Color(e.value.colorValue)) : null),
                    child: Text('${e.value.emoji} ${e.key}', style: TextStyle(
                      fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                  ),
                );
              }).toList()),
            const SizedBox(height: 16),
            Row(children: [
              Text('시작', style: BotanicalTypo.label(size: 12, color: _textSub)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: dCtx, initialTime: startTime);
                  if (t != null) setDlg(() => startTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}',
                    style: BotanicalTypo.label(size: 14, weight: FontWeight.w800, color: _textMain)),
                ),
              ),
              const SizedBox(width: 12),
              Text('종료', style: BotanicalTypo.label(size: 12, color: _textSub)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: dCtx, initialTime: endTime);
                  if (t != null) setDlg(() => endTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}',
                    style: BotanicalTypo.label(size: 14, weight: FontWeight.w800, color: _textMain)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _minuteEditor('📖 집중공부', studyMin,
              (v) => setDlg(() => studyMin = v.clamp(0, 600))),
            _minuteEditor('🎧 강의듣기', lectureMin,
              (v) => setDlg(() => lectureMin = v.clamp(0, 600))),
            _minuteEditor('☕ 휴식', restMin,
              (v) => setDlg(() => restMin = v.clamp(0, 120)),
              maxVal: 120),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: BotanicalColors.primarySurface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10)),
              child: Text('순공시간: ${effMin}분',
                style: BotanicalTypo.label(size: 14, weight: FontWeight.w800,
                  color: BotanicalColors.primary)),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(dCtx, {
              'subject': subject,
              'startTime': startTime,
              'endTime': endTime,
              'studyMin': studyMin,
              'lectureMin': lectureMin,
              'restMin': restMin,
            }), child: const Text('추가')),
          ],
        );
      }),
    );

    if (result == null) return;
    final st = result['startTime'] as TimeOfDay;
    final et = result['endTime'] as TimeOfDay;
    final now = DateTime.now();
    final startDt = DateTime(now.year, now.month, now.day, st.hour, st.minute);
    final endDt = DateTime(now.year, now.month, now.day, et.hour, et.minute);
    final newEffMin = (result['studyMin'] as int) +
        ((result['lectureMin'] as int) * 0.5).round();

    final cycle = FocusCycle(
      id: 'fc_manual_${now.millisecondsSinceEpoch}',
      date: _selectedDate,
      startTime: startDt.toIso8601String(),
      endTime: endDt.toIso8601String(),
      subject: result['subject'] as String,
      segments: [],
      studyMin: result['studyMin'] as int,
      lectureMin: result['lectureMin'] as int,
      effectiveMin: newEffMin,
      restMin: result['restMin'] as int,
    );

    await _fb.saveFocusCycle(_selectedDate, cycle);
    try {
      final strs = await _fb.getStudyTimeRecords();
      final existing = strs[_selectedDate];
      final totalMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
      await _fb.updateStudyTimeRecord(_selectedDate, StudyTimeRecord(
        date: _selectedDate,
        effectiveMinutes: (existing?.effectiveMinutes ?? 0) + newEffMin,
        totalMinutes: (existing?.totalMinutes ?? 0) + totalMin,
      ));
    } catch (_) {}
    _loadCycles();
  }

  // ── 분 조절 위젯 ──

  Widget _minuteEditor(String label, int value, ValueChanged<int> onChanged,
      {int maxVal = 600}) {
    final h = value ~/ 60;
    final m = value % 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(label,
              style: BotanicalTypo.label(size: 12, weight: FontWeight.w700, color: _textSub),
              overflow: TextOverflow.ellipsis)),
          _circAdjBtn('-15', value >= 15
            ? () => onChanged((value - 15).clamp(0, maxVal)) : null),
          const SizedBox(width: 3),
          _circAdjBtn('-5', value >= 5
            ? () => onChanged((value - 5).clamp(0, maxVal)) : null),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showMinuteInputDialog(label, value, maxVal, onChanged),
            child: Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BotanicalColors.primary.withOpacity(0.2), width: 1.5)),
              child: Text(
                h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}분',
                textAlign: TextAlign.center,
                style: BotanicalTypo.number(
                  size: 14, weight: FontWeight.w800,
                  color: value > 0 ? BotanicalColors.primary : _textMuted)),
            ),
          ),
          const SizedBox(width: 6),
          _circAdjBtn('+5', () => onChanged((value + 5).clamp(0, maxVal))),
          const SizedBox(width: 3),
          _circAdjBtn('+15', () => onChanged((value + 15).clamp(0, maxVal))),
        ]),
      ),
    );
  }

  Widget _circAdjBtn(String label, VoidCallback? onTap) {
    final isAdd = label.startsWith('+');
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: !enabled
            ? (_dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade100)
            : (isAdd
              ? BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.08)
              : (_dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
          shape: BoxShape.circle),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
            color: !enabled ? (_dk ? Colors.white24 : Colors.grey.shade400)
              : (isAdd ? BotanicalColors.primary : _textSub)))),
      ),
    );
  }

  Future<void> _showMinuteInputDialog(String label, int current, int maxVal,
      ValueChanged<int> onChanged) async {
    final hourCtrl = TextEditingController(text: '${current ~/ 60}');
    final minCtrl = TextEditingController(text: '${current % 60}');
    final result = await showDialog<int>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(label, style: BotanicalTypo.heading(size: 16)),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 60, child: TextField(
            controller: hourCtrl, keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: BotanicalTypo.number(size: 28, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0', suffixText: 'h',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(':', style: BotanicalTypo.number(size: 28, weight: FontWeight.w300))),
          SizedBox(width: 60, child: TextField(
            controller: minCtrl, keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: BotanicalTypo.number(size: 28, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0', suffixText: 'm',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
          TextButton(onPressed: () {
            final h = int.tryParse(hourCtrl.text) ?? 0;
            final m = int.tryParse(minCtrl.text) ?? 0;
            Navigator.pop(dCtx, (h * 60 + m).clamp(0, maxVal));
          }, child: const Text('확인')),
        ],
      ),
    );
    if (result != null) onChanged(result);
  }
}
