import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// TAB 4 — 통계 (Stats) v2
/// Overview · Goal Status · Habit Pipeline · Streak Ranking
/// Weekly Heatmap · Goal Progress Timeline
/// ═══════════════════════════════════════════════════════════

class OrderStatsTab extends StatelessWidget {
  final OrderData data;
  const OrderStatsTab({super.key, required this.data});

  List<OrderHabit> get _active => data.habits.where((h) => !h.archived).toList();
  List<OrderGoal> get _liveGoals => data.goals.where((g) => !g.isFinished).toList();
  int get _done => data.goals.where((g) => g.isCompleted).length;
  int get _failed => data.goals.where((g) => g.isFailed).length;
  int get _settled => _active.where((h) => h.isSettled).length;
  int get _avgStreak {
    final a = _active.where((h) => !h.isSettled).toList();
    if (a.isEmpty) return 0;
    return (a.map((h) => h.currentStreak).fold(0, (a, b) => a + b) / a.length).round();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    children: [
      _overview(), const SizedBox(height: 16),
      _goalStatus(), const SizedBox(height: 16),
      _pipeline(), const SizedBox(height: 16),
      _streakRank(), const SizedBox(height: 16),
      _heatmap(), const SizedBox(height: 16),
      _timeline(),
    ],
  );

  // ═══ 1. OVERVIEW ═══
  Widget _overview() => Row(children: [
    Expanded(child: _stat('${data.goals.length}', '', '목표 (완료 $_done)', OC.accent, OC.accentBg)),
    const SizedBox(width: 10),
    Expanded(child: _stat('${_active.length}', '', '습관 (정착 $_settled)', OC.success, OC.successBg)),
    const SizedBox(width: 10),
    Expanded(child: _stat('$_avgStreak', '일', '평균 스트릭', OC.amber, OC.amberBg)),
  ]);

  Widget _stat(String v, String u, String l, Color c, Color bg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withOpacity(.2))),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c)),
        if (u.isNotEmpty) Text(u, style: TextStyle(fontSize: 13, color: c.withOpacity(.6))),
      ]),
      const SizedBox(height: 3),
      Text(l, style: const TextStyle(fontSize: 10, color: OC.text3, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );

  // ═══ 2. GOAL STATUS ═══
  Widget _goalStatus() {
    final t = data.goals.length;
    if (t == 0) return orderSectionCard(title: '목표 상태 분포', icon: Icons.pie_chart_rounded,
      children: [_empty('등록된 목표가 없습니다')]);
    final ip = _liveGoals.length;
    return orderSectionCard(
      title: '목표 상태 분포', icon: Icons.pie_chart_rounded,
      trailing: Text('$t개', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OC.text3)),
      children: [
        _bar([_Seg(_done / t, OC.success), _Seg(ip / t, OC.accent), _Seg(_failed / t, OC.error)]),
        const SizedBox(height: 12),
        _leg('완료', _done, t, OC.success),
        const SizedBox(height: 5),
        _leg('진행 중', ip, t, OC.accent),
        const SizedBox(height: 5),
        _leg('실패', _failed, t, OC.error),
        const SizedBox(height: 10),
        const Divider(height: 1, color: OC.border),
        const SizedBox(height: 10),
        _dist('단기 Sprint', data.goals.where((g) => g.tier == GoalTier.sprint).length, t, OC.sprint, OC.sprintBg),
        _dist('중기 Race', data.goals.where((g) => g.tier == GoalTier.race).length, t, OC.race, OC.raceBg),
        _dist('장기 Marathon', data.goals.where((g) => g.tier == GoalTier.marathon).length, t, OC.marathon, OC.marathonBg),
      ],
    );
  }

  // ═══ 3. HABIT PIPELINE ═══
  Widget _pipeline() {
    final a = _active;
    if (a.isEmpty) return orderSectionCard(title: '습관 정착 파이프라인',
      icon: Icons.trending_up_rounded, children: [_empty('활성 습관이 없습니다')]);
    final pillar = a.where((h) => h.isSettled || h.growthStage == GrowthStage.pillar).toList();
    final growing = a.where((h) => !h.isSettled &&
      (h.growthStage == GrowthStage.tree || h.growthStage == GrowthStage.sprout)).toList();
    final seeds = a.where((h) => !h.isSettled && h.growthStage == GrowthStage.seed).toList();
    return orderSectionCard(
      title: '습관 정착 파이프라인', icon: Icons.trending_up_rounded,
      children: [
        _pipeGrp('정착 / 기둥', pillar, OC.success, OC.successBg),
        if (growing.isNotEmpty) const SizedBox(height: 8),
        _pipeGrp('성장 중', growing, OC.accent, OC.accentBg),
        if (seeds.isNotEmpty) const SizedBox(height: 8),
        _pipeGrp('시작 단계', seeds, OC.amber, OC.amberBg),
      ],
    );
  }

  Widget _pipeGrp(String label, List<OrderHabit> list, Color c, Color bg) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label (${list.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ]),
      const SizedBox(height: 5),
      ...list.map((h) => Padding(padding: const EdgeInsets.only(bottom: 5, left: 14),
        child: Row(children: [
          Text(h.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: OC.text1),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: h.settlementProgress,
                backgroundColor: bg, valueColor: AlwaysStoppedAnimation(c), minHeight: 4)),
          ])),
          const SizedBox(width: 6),
          Text(h.growthEmoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 3),
          Text(h.isSettled ? '정착' : '${h.currentStreak}/${h.targetDays}일',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: h.isSettled ? OC.success : OC.text2)),
        ]))),
    ]);
  }

  // ═══ 4. STREAK RANKING ═══
  Widget _streakRank() {
    final a = _active.where((h) => !h.isSettled).toList()
      ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
    if (a.isEmpty) return orderSectionCard(title: '스트릭 랭킹',
      icon: Icons.emoji_events_rounded, children: [_empty('활성 습관이 없습니다')]);
    final mx = max(a.first.currentStreak, 1);
    final bestAll = a.map((h) => h.bestStreak).reduce((a, b) => max(a, b));
    return orderSectionCard(
      title: '스트릭 랭킹', icon: Icons.emoji_events_rounded,
      trailing: Text('Best $bestAll일', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: OC.amber)),
      children: a.take(7).toList().asMap().entries.map((e) {
        final i = e.key; final h = e.value;
        final r = (h.currentStreak / mx).clamp(0.0, 1.0);
        final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '';
        return Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [
          SizedBox(width: 20, child: Text(medal, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center)),
          const SizedBox(width: 4),
          Text(h.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(h.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: OC.text1),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${h.currentStreak}일', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: OC.amber)),
              if (h.bestStreak > h.currentStreak) ...[
                const SizedBox(width: 3),
                Text('(max ${h.bestStreak})', style: const TextStyle(fontSize: 10, color: OC.text3)),
              ],
            ]),
            const SizedBox(height: 3),
            ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: r, backgroundColor: OC.amberBg,
                valueColor: AlwaysStoppedAnimation(Color.lerp(OC.amber, OC.success, r)!), minHeight: 5)),
          ])),
        ]));
      }).toList(),
    );
  }

  // ═══ 5. WEEKLY HEATMAP ═══
  Widget _heatmap() {
    final a = _active.where((h) => !h.isSettled).toList();
    if (a.isEmpty) return orderSectionCard(title: '주간 일관성',
      icon: Icons.grid_on_rounded, children: [_empty('활성 습관이 없습니다')]);
    final now = DateTime.now();
    final dates = List.generate(7, (i) => _fmt(now.subtract(Duration(days: 6 - i))));
    const dn = ['월', '화', '수', '목', '금', '토', '일'];
    final dayLabels = dates.map((d) {
      final dt = DateTime.tryParse(d);
      return dt != null ? dn[dt.weekday - 1] : '';
    }).toList();
    int checks = 0;
    for (final h in a) for (final d in dates) if (h.isDoneOn(d)) checks++;
    final pct = a.isEmpty ? 0 : (checks / (a.length * 7) * 100).round();
    return orderSectionCard(
      title: '주간 일관성', icon: Icons.grid_on_rounded,
      trailing: Text('$pct%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
        color: pct >= 80 ? OC.success : pct >= 50 ? OC.amber : OC.error)),
      children: [
        Row(children: [
          const SizedBox(width: 76),
          ...dayLabels.map((l) => Expanded(child: Center(child: Text(l,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OC.text3))))),
        ]),
        const SizedBox(height: 5),
        ...a.take(8).map((h) => Padding(padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(width: 76, child: Row(children: [
              Text(h.emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 3),
              Expanded(child: Text(h.title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: OC.text2),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            ])),
            ...dates.map((d) {
              final ok = h.isDoneOn(d);
              return Expanded(child: Center(child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(color: ok ? OC.success.withOpacity(.85) : OC.bgSub,
                  borderRadius: BorderRadius.circular(4)),
                child: ok ? const Icon(Icons.check_rounded, size: 11, color: Colors.white) : null,
              )));
            }),
          ]))),
        if (a.length > 8) Padding(padding: const EdgeInsets.only(top: 3),
          child: Text('+${a.length - 8}개 더', style: const TextStyle(fontSize: 10, color: OC.text3),
            textAlign: TextAlign.center)),
      ],
    );
  }

  // ═══ 6. GOAL TIMELINE ═══
  Widget _timeline() {
    final g = _liveGoals.toList()..sort((a, b) => b.progress.compareTo(a.progress));
    if (g.isEmpty) return orderSectionCard(title: '목표 진행 타임라인',
      icon: Icons.timeline_rounded, children: [_empty('진행 중인 목표가 없습니다')]);
    return orderSectionCard(
      title: '목표 진행 타임라인', icon: Icons.timeline_rounded,
      trailing: Text('${g.length}개', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: OC.text3)),
      children: g.take(8).map((gl) {
        final tc = tierColor(gl.tier); final tb = tierBg(gl.tier);
        final p = gl.progress.clamp(0, 100);
        final dl = _dlStr(gl);
        return Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(color: tb, borderRadius: BorderRadius.circular(9),
                border: Border.all(color: tc.withOpacity(.3))),
              child: Center(child: Text(gl.tierEmoji, style: const TextStyle(fontSize: 15)))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(gl.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OC.text1),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('$p%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tc)),
              ]),
              const SizedBox(height: 3),
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: p / 100, backgroundColor: tb,
                  valueColor: AlwaysStoppedAnimation(tc), minHeight: 5)),
              if (dl.isNotEmpty || gl.milestones.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
                  if (dl.isNotEmpty) ...[
                    Icon(Icons.schedule_rounded, size: 10, color: OC.text3),
                    const SizedBox(width: 2),
                    Text(dl, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                      color: _dlColor(gl))),
                  ],
                  if (dl.isNotEmpty && gl.milestones.isNotEmpty) const SizedBox(width: 6),
                  if (gl.milestones.isNotEmpty)
                    Text('${gl.milestones.where((m) => m.done).length}/${gl.milestones.length} 마일스톤',
                      style: const TextStyle(fontSize: 10, color: OC.text3)),
                ])),
            ])),
          ]));
      }).toList(),
    );
  }

  // ═══ SHARED ═══
  Widget _bar(List<_Seg> s) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(height: 10, child: Row(
      children: s.where((x) => x.r > 0).map((x) => Expanded(
        flex: (x.r * 1000).round().clamp(1, 1000),
        child: Container(color: x.c))).toList(),
    )),
  );

  Widget _leg(String l, int n, int t, Color c) {
    final p = t > 0 ? (n / t * 100).round() : 0;
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: OC.text2)),
      const Spacer(),
      Text('$n개', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      const SizedBox(width: 6),
      SizedBox(width: 34, child: Text('$p%', style: const TextStyle(fontSize: 11, color: OC.text3), textAlign: TextAlign.right)),
    ]);
  }

  Widget _dist(String l, int n, int t, Color c, Color bg) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: OC.text2)),
        Text('$n개', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: t > 0 ? n / t : 0, backgroundColor: bg,
          valueColor: AlwaysStoppedAnimation(c), minHeight: 6)),
    ]),
  );

  Widget _empty(String t) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(t, style: const TextStyle(fontSize: 13, color: OC.text3, fontWeight: FontWeight.w500))));

  String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dlStr(OrderGoal g) {
    final d = g.daysLeft;
    if (d == null) return '';
    if (d == 0) return 'D-Day';
    return d > 0 ? 'D-$d' : 'D+${d.abs()}';
  }

  Color _dlColor(OrderGoal g) {
    final d = g.daysLeft;
    if (d == null) return OC.text3;
    if (d <= 0) return OC.error;
    if (d <= 3) return OC.amber;
    return OC.text3;
  }
}

class _Seg {
  final double r;
  final Color c;
  const _Seg(this.r, this.c);
}
