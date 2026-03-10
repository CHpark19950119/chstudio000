import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// TAB 1 — 오늘: Achievement · Habits · Goals · NFC Timeline
class OrderTodayTab extends StatelessWidget {
  final OrderData data;
  final void Function(VoidCallback fn) onUpdate;
  final Future<void> Function() onLoad;
  final Map<String, String> nfcActualTimes;

  const OrderTodayTab({super.key, required this.data,
    required this.onUpdate, required this.onLoad,
    this.nfcActualTimes = const {}});

  String get _today => todayStr();
  List<OrderHabit> get _active => data.habits.where((h) => !h.archived && !h.isSettled).toList();
  int get _done => _active.where((h) => h.isDoneOn(_today)).length;
  int get _score {
    final a = _active; if (a.isEmpty) return 0;
    double b = (a.where((h) => h.isDoneOn(_today)).length / a.length) * 70;
    for (var h in a) { if (h.currentStreak >= 7) b += 5; if (h.currentStreak >= 21) b += 5; }
    return b.clamp(0, 100).round();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onLoad, color: OC.accent,
    child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
      _header(), const SizedBox(height: 16), _summaryCard(),
      const SizedBox(height: 16), _habitsCard(context),
      const SizedBox(height: 16), _goalsCard(),
      const SizedBox(height: 16), _nfcTile(),
    ]));

  // ═══ HEADER ═══
  Widget _header() => Padding(padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [OC.accent, OC.accentLt]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: OC.accent.withOpacity(.2), blurRadius: 8, offset: const Offset(0, 3))]),
        child: const Text('COMPASS', style: TextStyle(color: Colors.white,
          fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2))),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 질서', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1)),
        Text(DateFormat('M월 d일 EEEE', 'ko').format(DateTime.now()),
          style: const TextStyle(fontSize: 12, color: OC.text3)),
      ]),
    ]));

  // ═══ 1. ACHIEVEMENT SUMMARY ═══
  Widget _summaryCard() {
    final total = _active.length, done = _done;
    final ratio = total > 0 ? done / total : 0.0;
    final score = _score;
    final grade = score >= 90 ? 'S' : score >= 75 ? 'A' : score >= 60 ? 'B' : score >= 40 ? 'C' : 'D';
    final gc = score >= 75 ? OC.success : score >= 50 ? OC.amber : OC.error;
    final sprints = data.goals.where((g) => !g.isFinished && g.tier == GoalTier.sprint && g.deadline != null).toList()
      ..sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
    final ns = sprints.isNotEmpty ? sprints.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: OC.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OC.border.withOpacity(.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 16, offset: const Offset(0, 6))]),
      child: Row(children: [
        SizedBox(width: 80, height: 80, child: CustomPaint(
          painter: _RingPainter(ratio: ratio, color: OC.accent),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$done/$total', style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: OC.text1, height: 1)),
            const SizedBox(height: 2),
            const Text('습관', style: TextStyle(fontSize: 10, color: OC.text3, fontWeight: FontWeight.w600)),
          ])))),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('$score', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: OC.text1, height: 1)),
            const SizedBox(width: 4),
            Text('/100', style: TextStyle(fontSize: 11, color: OC.text3)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: gc.withOpacity(.1), borderRadius: BorderRadius.circular(8),
                border: Border.all(color: gc.withOpacity(.25))),
              child: Text(grade, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: gc))),
          ]),
          const SizedBox(height: 4),
          Text('ORDER SCORE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: OC.text3, letterSpacing: 1)),
          if (ns != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: OC.sprintBg, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OC.sprint.withOpacity(.2))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('⚡', style: TextStyle(fontSize: 11)), const SizedBox(width: 4),
                Flexible(child: Text(ns.title, style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w600, color: OC.text2), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Text(ns.dDayLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  color: (ns.daysLeft ?? 99) <= 3 ? OC.error : OC.sprint)),
              ])),
          ],
        ])),
      ]),
    );
  }

  // ═══ 2. HABITS CHECKLIST ═══
  Widget _habitsCard(BuildContext context) {
    final focus = _active.where((h) => h.rank == 1).toList();
    final queue = _active.where((h) => h.rank > 1).toList()..sort((a, b) => a.rank.compareTo(b.rank));
    final unranked = _active.where((h) => h.rank == 0).toList();
    final all = [...focus, ...queue, ...unranked];
    final done = all.where((h) => h.isDoneOn(_today)).length;

    return orderSectionCard(
      title: '오늘의 습관', icon: Icons.check_circle_rounded,
      trailing: Text('$done/${all.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OC.text3)),
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
          value: all.isEmpty ? 0 : done / all.length, backgroundColor: OC.border, minHeight: 5,
          valueColor: AlwaysStoppedAnimation(done == all.length && all.isNotEmpty ? OC.success : OC.accent))),
        const SizedBox(height: 14),
        if (focus.isNotEmpty) ...[
          _chip('🔥', '집중', OC.amber, OC.amberBg), const SizedBox(height: 8),
          ...focus.map((h) => _hRow(h, context, bg: OC.amberBg, bc: OC.amber.withOpacity(.2))),
        ],
        if (queue.isNotEmpty) ...[
          SizedBox(height: focus.isNotEmpty ? 12 : 0),
          _chip('⏳', '대기열 ${queue.length}', const Color(0xFF94A3B8), const Color(0xFF94A3B8).withOpacity(.08)),
          const SizedBox(height: 8), ...queue.map((h) => _hRow(h, context)),
        ],
        if (unranked.isNotEmpty) ...[
          if (focus.isNotEmpty || queue.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(height: 1, color: OC.border.withOpacity(.3))),
          ...unranked.map((h) => _hRow(h, context)),
        ],
      ]);
  }

  Widget _chip(String emoji, String label, Color c, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withOpacity(.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 10)), const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c, letterSpacing: .5)),
    ]));

  Widget _hRow(OrderHabit h, BuildContext ctx, {Color? bg, Color? bc}) {
    final done = h.isDoneOn(_today);
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: GestureDetector(
      onTap: () => done ? _undoHabit(ctx, h) : onUpdate(() { h.toggleDate(_today); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: done ? OC.successBg : (bg ?? OC.cardHi),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: done ? OC.success.withOpacity(.25) : (bc ?? OC.border.withOpacity(.4)))),
        child: Row(children: [
          Text(h.emoji, style: const TextStyle(fontSize: 18)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OC.text1,
              decoration: done ? TextDecoration.lineThrough : null), maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              Text('${h.growthEmoji} ${h.currentStreak}일', style: const TextStyle(fontSize: 10, color: OC.text3)),
              if (h.bestStreak > h.currentStreak) ...[const SizedBox(width: 6),
                Text('👑 ${h.bestStreak}', style: const TextStyle(fontSize: 9, color: OC.amber, fontWeight: FontWeight.w700))],
            ]),
          ])),
          if (h.targetDays > 0) ...[
            SizedBox(width: 40, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${(h.settlementProgress * 100).round()}%', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: done ? OC.success : OC.text3)),
              const SizedBox(height: 3),
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(
                value: h.settlementProgress, backgroundColor: OC.border, minHeight: 3,
                valueColor: AlwaysStoppedAnimation(done ? OC.success : OC.accent))),
            ])), const SizedBox(width: 10),
          ],
          AnimatedContainer(duration: const Duration(milliseconds: 200), width: 24, height: 24,
            decoration: BoxDecoration(color: done ? OC.success : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: done ? OC.success : OC.text4.withOpacity(.5), width: 2)),
            child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null),
        ])),
    ));
  }

  void _undoHabit(BuildContext ctx, OrderHabit h) => showDialog(context: ctx,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('${h.emoji} 완료 취소', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Text('「${h.title}」 오늘 기록을 취소할까요?', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('아니요')),
        TextButton(onPressed: () { onUpdate(() { h.completedDates.remove(_today); }); Navigator.pop(c); },
          child: const Text('취소하기', style: TextStyle(color: Color(0xFFEF4444)))),
      ]));

  // ═══ 3. GOAL MILESTONES ═══
  Widget _goalsCard() {
    final goals = data.goals.where((g) => !g.isFinished).toList()
      ..sort((a, b) { final t = a.tier.index.compareTo(b.tier.index);
        return t != 0 ? t : (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999); });
    if (goals.isEmpty) return orderSectionCard(title: '목표 현황', icon: Icons.flag_rounded,
      children: [Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('진행 중인 목표가 없습니다', style: TextStyle(fontSize: 12, color: OC.text3))))]);
    return orderSectionCard(title: '목표 현황', icon: Icons.flag_rounded,
      trailing: Text('${goals.length}개 진행', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: OC.text3)),
      children: goals.take(5).map(_gRow).toList());
  }

  Widget _gRow(OrderGoal g) {
    final c = tierColor(g.tier), bg = tierBg(g.tier);
    final urgent = (g.daysLeft ?? 99) <= 3 && g.tier == GoalTier.sprint;
    final ms = g.milestones;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: urgent ? OC.error.withOpacity(.4) : c.withOpacity(.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(g.tierEmoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 8),
          Expanded(child: Text(g.title, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w700, color: OC.text1), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (g.dDayLabel.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: urgent ? OC.errorBg : c.withOpacity(.12), borderRadius: BorderRadius.circular(8)),
            child: Text(g.dDayLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: urgent ? OC.error : c)))
          else orderChip(g.tierLabel, c, c.withOpacity(.12)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
            value: g.progress / 100, minHeight: 5, backgroundColor: c.withOpacity(.15), valueColor: AlwaysStoppedAnimation(c)))),
          const SizedBox(width: 10),
          Text('${g.progress}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
        ]),
        if (ms.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...ms.take(3).map((m) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
            Icon(m.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 14, color: m.done ? OC.success : OC.text4), const SizedBox(width: 6),
            Expanded(child: Text(m.text, style: TextStyle(fontSize: 11, color: m.done ? OC.text3 : OC.text2,
              decoration: m.done ? TextDecoration.lineThrough : null), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]))),
          if (ms.length > 3) Text('  +${ms.length - 3}개 마일스톤', style: const TextStyle(fontSize: 10, color: OC.text3)),
        ],
      ]),
    ));
  }

  // ═══ 4. NFC TIMELINE (COLLAPSED) ═══
  Widget _nfcTile() {
    final rt = data.routineTarget;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final roles = [('기상','☀️',rt.wakeTime??'05:30','wake',OC.amber), ('외출','🚶',rt.outingTime??'07:00','outing',OC.success),
      ('공부','📚',rt.studyTime??'08:00','study',OC.race), ('수면','🌙',rt.sleepTime??'23:00','sleep',OC.marathon)];
    final rec = nfcActualTimes.length;
    return Container(
      decoration: BoxDecoration(color: OC.card, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OC.border.withOpacity(.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 16, offset: const Offset(0, 6))]),
      child: Theme(data: ThemeData(dividerColor: Colors.transparent), child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        leading: const Icon(Icons.timeline_rounded, size: 18, color: OC.accent),
        title: const Text('루틴 타임라인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: OC.text1)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(rec > 0 ? '$rec/4 기록' : '미기록', style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w600, color: rec > 0 ? OC.success : OC.text3)),
          const SizedBox(width: 4), const Icon(Icons.expand_more_rounded, size: 20, color: OC.text3),
        ]),
        children: roles.map((r) {
          final actual = nfcActualTimes[r.$4]; final tMin = _toMin(r.$3);
          final isRec = actual != null; final isPast = nowMin > tMin + 30;
          int off = 0; Color dc = OC.text4; String lbl = isPast ? '미기록' : '대기';
          if (isRec) { off = _toMin(actual) - tMin; dc = off.abs() <= 10 ? OC.success : off.abs() <= 30 ? OC.amber : OC.error; lbl = actual; }
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            Container(width: 30, height: 30,
              decoration: BoxDecoration(color: isRec ? r.$5.withOpacity(.12) : OC.bgSub,
                borderRadius: BorderRadius.circular(9), border: Border.all(color: isRec ? r.$5.withOpacity(.3) : OC.border)),
              child: Center(child: Text(r.$2, style: const TextStyle(fontSize: 14)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OC.text1)),
              Text('목표 ${r.$3} → $lbl', style: TextStyle(fontSize: 10, color: OC.text3)),
            ])),
            if (isRec) Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                color: off.abs() <= 10 ? OC.successBg : off.abs() <= 30 ? OC.amberBg : OC.errorBg),
              child: Text(off == 0 ? '정시' : off > 0 ? '+${off}분' : '${off}분',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: dc))),
          ]));
        }).toList(),
      )));
  }

  int _toMin(String t) { final p = t.split(':'); return p.length < 2 ? 0 : int.parse(p[0]) * 60 + int.parse(p[1]); }
}

// ═══ RING PAINTER ═══
class _RingPainter extends CustomPainter {
  final double ratio; final Color color;
  _RingPainter({required this.ratio, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = min(cx, cy) - 6;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(rect, 0, 2 * pi, false, Paint()..color = const Color(0xFFE8E2DA)
      ..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
    if (ratio > 0) canvas.drawArc(rect, -pi / 2, 2 * pi * ratio, false, Paint()
      ..color = ratio >= 1.0 ? const Color(0xFF34C759) : color
      ..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) => old.ratio != ratio || old.color != color;
}
