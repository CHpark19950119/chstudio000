import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// TAB 4 — 통계 (Stats)
/// Summary · Distribution · Streak Ranking · Stress Summary
/// ═══════════════════════════════════════════════════════════

class OrderStatsTab extends StatelessWidget {
  final OrderData data;

  const OrderStatsTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final totalGoals = data.goals.length;
    final completedGoals = data.goals.where((g) => g.isCompleted).length;
    final activeHabits = data.habits.where((h) => !h.archived).toList();
    final totalHabits = activeHabits.length;
    final avgStreak = totalHabits > 0
        ? (activeHabits.map((h) => h.currentStreak)
            .fold(0, (a, b) => a + b) / totalHabits).round()
        : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // 요약 카드
        Row(children: [
          Expanded(child: _bigStat(
            '$totalGoals', '', '전체 목표', OC.accent, OC.accentBg)),
          const SizedBox(width: 10),
          Expanded(child: _bigStat(
            '$completedGoals', '', '완료', OC.success, OC.successBg)),
          const SizedBox(width: 10),
          Expanded(child: _bigStat(
            '$avgStreak', '일', '평균 스트릭', OC.amber, OC.amberBg)),
        ]),
        const SizedBox(height: 16),
        // 티어 분포
        orderSectionCard(
          title: '목표 분포', icon: Icons.pie_chart_rounded,
          children: [
            _distBar('단기 Sprint',
              data.goals.where((g) => g.tier == GoalTier.sprint).length,
              totalGoals, OC.sprint, OC.sprintBg),
            _distBar('중기 Race',
              data.goals.where((g) => g.tier == GoalTier.race).length,
              totalGoals, OC.race, OC.raceBg),
            _distBar('장기 Marathon',
              data.goals.where((g) => g.tier == GoalTier.marathon).length,
              totalGoals, OC.marathon, OC.marathonBg),
          ],
        ),
        const SizedBox(height: 16),
        // 스트릭 순위
        orderSectionCard(
          title: '스트릭 순위', icon: Icons.emoji_events_rounded,
          children: [
            ...(() {
              final sorted = activeHabits.toList()
                ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
              return sorted.take(5).map((h) => _streakRow(h)).toList();
            })(),
          ],
        ),
        const SizedBox(height: 16),
        // 스트레스 요약
        orderSectionCard(
          title: '스트레스 요약', icon: Icons.psychology_rounded,
          children: [
            _distBar('Release',
              data.stressLogs.where((s) =>
                s.type == StressType.release).length,
              max(1, data.stressLogs.length),
              OC.stressRel, OC.errorBg),
            _distBar('Escape',
              data.stressLogs.where((s) =>
                s.type == StressType.escape).length,
              max(1, data.stressLogs.length),
              OC.stressEsc, OC.amberBg),
            _distBar('대체행동',
              data.stressLogs.where((s) =>
                s.type == StressType.alternative).length,
              max(1, data.stressLogs.length),
              OC.stressAlt, OC.successBg),
          ],
        ),
      ],
    );
  }

  Widget _bigStat(String value, String unit, String label,
      Color c, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(.2))),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w900, color: c)),
            if (unit.isNotEmpty) Text(unit, style: TextStyle(
              fontSize: 14, color: c.withOpacity(.6))),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(
          fontSize: 11, color: OC.text3, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _distBar(String label, int count, int total,
      Color c, Color bg) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: OC.text2)),
          Text('$count개', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, backgroundColor: bg,
            valueColor: AlwaysStoppedAnimation(c), minHeight: 6)),
      ]),
    );
  }

  Widget _streakRow(OrderHabit h) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(h.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Text(h.title, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: OC.text1))),
        Text(h.growthEmoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text('${h.currentStreak}일', style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: OC.amber)),
      ]),
    );
  }
}
