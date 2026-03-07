import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';

// ═══════════════════════════════════════════
//  상태 편집 바텀시트 v11: 식사 관리 통합
// ═══════════════════════════════════════════

class StatusEditorSheet extends StatefulWidget {
  final TimeRecord? existing;
  final bool dk;
  final String highlightField;

  const StatusEditorSheet({
    super.key,
    required this.existing,
    required this.dk,
    required this.highlightField,
  });

  @override
  State<StatusEditorSheet> createState() => _StatusEditorSheetState();
}

class _StatusEditorSheetState extends State<StatusEditorSheet> {
  late String? _wakeTime, _outingTime, _returnTime, _studyTime, _studyEndTime, _bedTimeEdit;
  late List<_EditableMeal> _meals;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _wakeTime = e?.wake;
    _outingTime = e?.outing;
    _returnTime = e?.returnHome;
    _studyTime = e?.study;
    _studyEndTime = e?.studyEnd;
    _bedTimeEdit = e?.bedTime;

    // 식사 목록 초기화
    if (e != null && e.meals.isNotEmpty) {
      _meals = e.meals.map((m) => _EditableMeal(
        start: m.start,
        end: m.end,
        type: m.type ?? _guessType(m.start),
      )).toList();
    } else if (e?.mealStart != null) {
      // 레거시 단일 식사 → 마이그레이션
      _meals = [_EditableMeal(
        start: e!.mealStart!,
        end: e.mealEnd,
        type: _guessType(e.mealStart!),
      )];
    } else {
      _meals = [];
    }
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

  /// 시간으로 식사 타입 추정
  String _guessType(String time) {
    try {
      final h = int.parse(time.split(':')[0]);
      if (h < 10) return 'breakfast';
      if (h < 15) return 'lunch';
      if (h < 20) return 'dinner';
      return 'snack';
    } catch (_) { return 'lunch'; }
  }

  String _nowStr() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  String? _adjustTime(String? time, int deltaMin) {
    if (time == null) return null;
    try {
      final p = time.split(':');
      final total = (int.parse(p[0]) * 60 + int.parse(p[1]) + deltaMin).clamp(0, 1439);
      return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    } catch (_) { return time; }
  }

  @override
  Widget build(BuildContext context) {
    final dk = widget.dk;
    final bg = dk ? const Color(0xFF1a2332) : const Color(0xFFFCF9F3);
    final textMain = dk ? Colors.white : const Color(0xFF1e293b);
    final textMuted = dk ? Colors.white54 : Colors.grey;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final isMealSection = widget.highlightField == 'meal';

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 드래그 핸들
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: textMuted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2))),
        ),

        // 스크롤 가능 콘텐츠
        Flexible(child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24, right: 24,
            bottom: bottomInset + bottomPad + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('오늘의 상태 수정', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: textMain)),
            const SizedBox(height: 4),
            Text('각 항목의 시간을 수정합니다', style: TextStyle(
              fontSize: 11, color: textMuted)),
            const SizedBox(height: 20),

            // ── 기본 시간 필드 ──
            _timeRow('🚿', '기상', _wakeTime, BotanicalColors.gold,
              (t) => _safeSetState(() => _wakeTime = t), textMain, textMuted, dk),
            _timeRow('🚪', '외출', _outingTime, const Color(0xFF3B8A6B),
              (t) => _safeSetState(() => _outingTime = t), textMain, textMuted, dk),
            _timeRow('🏠', '귀가', _returnTime, const Color(0xFF3B8A6B),
              (t) => _safeSetState(() => _returnTime = t), textMain, textMuted, dk),
            _timeRow('📚', '공부시작', _studyTime, BotanicalColors.primary,
              (t) => _safeSetState(() => _studyTime = t), textMain, textMuted, dk),
            _timeRow('🏁', '공부종료', _studyEndTime, const Color(0xFF5B7ABF),
              (t) => _safeSetState(() => _studyEndTime = t), textMain, textMuted, dk),
            _timeRow('🌙', '수면시작', _bedTimeEdit, const Color(0xFF6B5DAF),
              (t) => _safeSetState(() => _bedTimeEdit = t), textMain, textMuted, dk),

            const SizedBox(height: 8),

            // ══════════════════════════════════
            //  ★ 식사 관리 섹션
            // ══════════════════════════════════
            _buildMealSection(dk, textMain, textMuted),

            const SizedBox(height: 16),

            // 저장 버튼
            SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D5F2D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
                child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              )),
            const SizedBox(height: 8),
          ]),
        )),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  식사 관리 위젯
  // ══════════════════════════════════════════

  Widget _buildMealSection(bool dk, Color textMain, Color textMuted) {
    const mealColor = Color(0xFFFF8A65);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mealColor.withOpacity(dk ? 0.06 : 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mealColor.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Row(children: [
          const Text('🍽️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('식사 관리', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: textMain)),
          const Spacer(),
          Text('${_meals.length}건', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: mealColor)),
        ]),
        const SizedBox(height: 12),

        // 식사 목록
        if (_meals.isEmpty)
          _emptyMealHint(dk, textMuted, mealColor)
        else
          ...List.generate(_meals.length, (i) =>
            _mealCard(i, dk, textMain, textMuted, mealColor)),

        const SizedBox(height: 10),

        // 식사 추가 버튼
        GestureDetector(
          onTap: _addMeal,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: mealColor.withOpacity(dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: mealColor.withOpacity(0.2),
                style: BorderStyle.solid)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, size: 18, color: mealColor),
              const SizedBox(width: 6),
              Text('식사 추가', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: mealColor)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _emptyMealHint(bool dk, Color textMuted, Color mealColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Column(children: [
        Icon(Icons.restaurant_menu_rounded, size: 28,
          color: textMuted.withOpacity(0.3)),
        const SizedBox(height: 8),
        Text('기록된 식사가 없습니다', style: TextStyle(
          fontSize: 12, color: textMuted.withOpacity(0.5))),
      ]),
    );
  }

  Widget _mealCard(int index, bool dk, Color textMain, Color textMuted, Color mealColor) {
    final meal = _meals[index];
    final typeInfo = _mealTypeInfo(meal.type);
    final duration = _calcDuration(meal.start, meal.end);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dk ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mealColor.withOpacity(0.12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 상단: 타입 + 삭제
        Row(children: [
          // 타입 선택 칩들
          ...['breakfast', 'lunch', 'dinner', 'snack'].map((type) {
            final info = _mealTypeInfo(type);
            final selected = meal.type == type;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => _safeSetState(() => _meals[index].type = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                      ? mealColor.withOpacity(dk ? 0.2 : 0.12)
                      : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                        ? mealColor.withOpacity(0.4)
                        : textMuted.withOpacity(0.15))),
                  child: Text('${info.emoji} ${info.label}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? mealColor : textMuted)),
                ),
              ),
            );
          }),
          const Spacer(),
          // 삭제
          GestureDetector(
            onTap: () => _deleteMeal(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(dk ? 0.1 : 0.05),
                borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.delete_outline_rounded, size: 16,
                color: Colors.red.withOpacity(0.5)),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // 하단: 시간 편집
        Row(children: [
          // 시작시간
          Expanded(child: _mealTimePicker(
            label: '시작',
            time: meal.start,
            color: mealColor,
            dk: dk,
            textMain: textMain,
            textMuted: textMuted,
            onChanged: (t) => _safeSetState(() => _meals[index].start = t),
          )),
          // 화살표
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded, size: 16,
              color: textMuted.withOpacity(0.4)),
          ),
          // 종료시간
          Expanded(child: _mealTimePicker(
            label: meal.end != null ? '종료' : '식사 중',
            time: meal.end,
            color: mealColor,
            dk: dk,
            textMain: textMain,
            textMuted: textMuted,
            onChanged: (t) => _safeSetState(() => _meals[index].end = t),
            allowNull: true,
          )),
          // 소요시간
          if (duration != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mealColor.withOpacity(dk ? 0.1 : 0.06),
                borderRadius: BorderRadius.circular(8)),
              child: Text(duration, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: mealColor, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _mealTimePicker({
    required String label,
    required String? time,
    required Color color,
    required bool dk,
    required Color textMain,
    required Color textMuted,
    required ValueChanged<String> onChanged,
    bool allowNull = false,
  }) {
    final hasTime = time != null;

    return GestureDetector(
      onTap: () async {
        final result = await _pickTimeDialog(time, dk, textMain);
        if (result != null) onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hasTime
            ? color.withOpacity(dk ? 0.08 : 0.05)
            : (dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasTime
            ? color.withOpacity(0.2)
            : textMuted.withOpacity(0.1))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hasTime) ...[
            // ±5분 버튼
            GestureDetector(
              onTap: () {
                final adj = _adjustTime(time, -5);
                if (adj != null) onChanged(adj);
              },
              child: Icon(Icons.remove_rounded, size: 14,
                color: textMuted.withOpacity(0.5))),
            const SizedBox(width: 4),
            Text(time!, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: color, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                final adj = _adjustTime(time, 5);
                if (adj != null) onChanged(adj);
              },
              child: Icon(Icons.add_rounded, size: 14,
                color: textMuted.withOpacity(0.5))),
            if (allowNull) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _safeSetState(() {
                  // end를 null로 → "식사 중" 상태
                  // 여기선 onChanged가 String만 받으므로 별도 처리
                  final idx = _meals.indexWhere((m) => m.end == time);
                  if (idx >= 0) _meals[idx].end = null;
                }),
                child: Icon(Icons.close_rounded, size: 12,
                  color: Colors.red.withOpacity(0.3)),
              ),
            ],
          ] else ...[
            Icon(Icons.access_time_rounded, size: 14,
              color: textMuted.withOpacity(0.4)),
            const SizedBox(width: 4),
            Text(allowNull ? '미정' : '입력', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: textMuted.withOpacity(0.5))),
          ],
        ]),
      ),
    );
  }

  String? _calcDuration(String start, String? end) {
    if (end == null) return null;
    try {
      final sp = start.split(':');
      final ep = end.split(':');
      final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      int diff = em - sm;
      if (diff < 0) diff += 1440;
      if (diff > 720) return null;
      if (diff >= 60) return '${diff ~/ 60}h${diff % 60}m';
      return '${diff}m';
    } catch (_) { return null; }
  }

  _MealTypeInfo _mealTypeInfo(String? type) {
    switch (type) {
      case 'breakfast': return _MealTypeInfo('🌅', '아침');
      case 'lunch':     return _MealTypeInfo('☀️', '점심');
      case 'dinner':    return _MealTypeInfo('🌙', '저녁');
      case 'snack':     return _MealTypeInfo('🍪', '간식');
      default:          return _MealTypeInfo('🍽️', '식사');
    }
  }

  void _addMeal() {
    _safeSetState(() {
      _meals.add(_EditableMeal(
        start: _nowStr(),
        end: null,
        type: _guessType(_nowStr()),
      ));
    });
  }

  void _deleteMeal(int index) {
    _safeSetState(() => _meals.removeAt(index));
  }

  // ══════════════════════════════════════════
  //  기본 시간 행 위젯 (기존과 동일)
  // ══════════════════════════════════════════

  Widget _timeRow(String emoji, String label, String? time, Color rowColor,
      ValueChanged<String?> onChanged, Color textMain, Color textMuted, bool dk) {
    final hasTime = time != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: hasTime
          ? rowColor.withOpacity(dk ? 0.08 : 0.04)
          : (dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hasTime
          ? rowColor.withOpacity(0.2)
          : (dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200))),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: textMain)),
        const Spacer(),
        if (hasTime) ...[
          _circleBtn(Icons.remove_rounded,
            () => onChanged(_adjustTime(time, -5)), dk, textMuted),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _pickTimeInline(time, onChanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: dk ? Colors.white.withOpacity(0.10) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rowColor.withOpacity(0.25), width: 1.5)),
              child: Text(time!,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: rowColor, fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 1)),
            ),
          ),
          const SizedBox(width: 6),
          _circleBtn(Icons.add_rounded,
            () => onChanged(_adjustTime(time, 5)), dk, textMuted),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onChanged(null),
            child: Icon(Icons.close_rounded, size: 18,
              color: Colors.red.withOpacity(0.4))),
        ] else ...[
          GestureDetector(
            onTap: () => onChanged(_nowStr()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: rowColor.withOpacity(dk ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.access_time_filled_rounded, size: 14, color: rowColor),
                const SizedBox(width: 4),
                Text('지금', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: rowColor)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _pickTimeInline(null, onChanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: textMuted.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(10)),
              child: Text('입력', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: textMuted)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, bool dk, Color textMuted) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: dk ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
          shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: dk ? Colors.white70 : Colors.grey.shade600)),
    );
  }

  // ══════════════════════════════════════════
  //  시간 입력 다이얼로그
  // ══════════════════════════════════════════

  Future<String?> _pickTimeDialog(String? current, bool dk, Color textMain) async {
    int initH = 12, initM = 0;
    if (current != null && current.contains(':')) {
      try {
        final p = current.split(':');
        initH = int.parse(p[0]);
        initM = int.parse(p[1]);
      } catch (_) {}
    }
    final hourCtrl = TextEditingController(text: initH.toString().padLeft(2, '0'));
    final minCtrl = TextEditingController(text: initM.toString().padLeft(2, '0'));

    final bg = dk ? const Color(0xFF1e2a3a) : Colors.white;
    final tc = dk ? Colors.white : const Color(0xFF1e293b);

    return showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('시간 입력', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: tc)),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 70, child: TextField(
            controller: hourCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center, maxLength: 2,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: tc),
            decoration: InputDecoration(
              counterText: '', hintText: '00',
              suffixText: '시', suffixStyle: TextStyle(fontSize: 13, color: tc.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
          )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: tc))),
          SizedBox(width: 70, child: TextField(
            controller: minCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center, maxLength: 2,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: tc),
            decoration: InputDecoration(
              counterText: '', hintText: '00',
              suffixText: '분', suffixStyle: TextStyle(fontSize: 13, color: tc.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
          )),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx),
            child: Text('취소', style: TextStyle(color: tc.withOpacity(0.5)))),
          TextButton(
            onPressed: () {
              final h = (int.tryParse(hourCtrl.text) ?? 0).clamp(0, 23);
              final m = (int.tryParse(minCtrl.text) ?? 0).clamp(0, 59);
              Navigator.pop(dCtx,
                '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
            },
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<void> _pickTimeInline(String? current, ValueChanged<String?> onChanged) async {
    final result = await _pickTimeDialog(current, widget.dk,
      widget.dk ? Colors.white : const Color(0xFF1e293b));
    if (result != null) onChanged(result);
  }

  // ══════════════════════════════════════════
  //  저장 — TimeRecord 반환
  // ══════════════════════════════════════════

  void _save() {
    // 식사를 시간순 정렬
    _meals.sort((a, b) => a.start.compareTo(b.start));

    final mealEntries = _meals.map((m) => MealEntry(
      start: m.start,
      end: m.end,
      type: m.type,
    )).toList();

    final record = TimeRecord(
      date: widget.existing?.date ?? '',
      wake: _wakeTime,
      study: _studyTime,
      studyEnd: _studyEndTime,
      outing: _outingTime,
      returnHome: _returnTime,
      arrival: widget.existing?.arrival,
      bedTime: _bedTimeEdit,
      // 레거시 호환 유지
      mealStart: mealEntries.isNotEmpty ? mealEntries.first.start : null,
      mealEnd: mealEntries.isNotEmpty ? mealEntries.first.end : null,
      meals: mealEntries,
    );

    Navigator.pop(context, record);
  }
}

// ── 내부 모델 ──

class _EditableMeal {
  String start;
  String? end;
  String? type;

  _EditableMeal({required this.start, this.end, this.type});
}

class _MealTypeInfo {
  final String emoji;
  final String label;
  const _MealTypeInfo(this.emoji, this.label);
}