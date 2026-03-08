import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/order_models.dart';
import '../../data/plan_data.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// TAB 2 — 목표 (Goals)
/// Vision · Sprint Board · Milestone · Chain · CRUD · 수험표
/// ═══════════════════════════════════════════════════════════

class OrderGoalsTab extends StatefulWidget {
  final OrderData data;
  final void Function(VoidCallback fn) onUpdate;

  const OrderGoalsTab({
    super.key, required this.data, required this.onUpdate,
  });

  @override
  State<OrderGoalsTab> createState() => _OrderGoalsTabState();
}

class _OrderGoalsTabState extends State<OrderGoalsTab> {
  OrderData get data => widget.data;
  void Function(VoidCallback fn) get onUpdate => widget.onUpdate;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        _prioritySection(),
        const SizedBox(height: 16),
        _visionCard(),
        const SizedBox(height: 16),
        _currentPeriodCard(),
        const SizedBox(height: 16),
        _sprintBoard(),
        const SizedBox(height: 16),
        _milestoneTimeline(),
        const SizedBox(height: 16),
        _goalChainView(),
        const SizedBox(height: 16),
        _allGoalsList(context),
        const SizedBox(height: 16),
        _failedGoalsSection(context),
      ],
    );
  }

  // ═══ PRIORITY SECTION (1순위 · 2순위) ═══
  Widget _prioritySection() {
    final p1 = data.primaryGoal;
    final p2 = data.secondaryGoal;
    if (p1 == null && p2 == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OC.cardHi, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OC.border.withOpacity(0.5))),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: OC.text3),
          const SizedBox(width: 10),
          Expanded(child: Text('목표를 길게 눌러 1순위/2순위를 지정하세요',
            style: const TextStyle(fontSize: 12, color: OC.text3))),
        ]),
      );
    }

    return Column(children: [
      if (p1 != null) _priorityCard(p1, 1),
      if (p1 != null && p2 != null) const SizedBox(height: 10),
      if (p2 != null) _priorityCard(p2, 2),
    ]);
  }

  Widget _priorityCard(OrderGoal g, int rank) {
    final isFirst = rank == 1;
    final mainColor = isFirst
        ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8);
    final bgGrad = isFirst
        ? [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)]
        : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: bgGrad),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: mainColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(
          color: mainColor.withOpacity(0.08),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        // 순위 배지
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: mainColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: mainColor.withOpacity(0.3))),
          child: Center(child: Text(isFirst ? '🥇' : '🥈',
            style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${rank}순위', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800, color: mainColor,
                letterSpacing: 1)),
              const Spacer(),
              Text('${g.progress}%', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: mainColor)),
            ]),
            const SizedBox(height: 4),
            Text(g.title, style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800, color: OC.text1)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: g.progress / 100,
                backgroundColor: mainColor.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation(mainColor),
                minHeight: 6)),
            if (g.dDayLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(g.dDayLabel, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: mainColor.withOpacity(0.7))),
            ],
          ],
        )),
      ]),
    );
  }

  // ═══ CURRENT PERIOD CARD (planData 연동) ═══
  Widget _currentPeriodCard() {
    final today = todayStr();
    final period = StudyPlanData.periodForDate(today);
    final subPeriod = StudyPlanData.subPeriodForDate(today);
    final dailyPlan = StudyPlanData.dailyPlanForDate(today);
    final nearestDDay = StudyPlanData.primaryDDay();

    if (period == null && nearestDDay == null) return const SizedBox.shrink();

    return orderSectionCard(
      title: '학습 로드맵', icon: Icons.map_rounded,
      children: [
        // D-Day 카운터
        if (nearestDDay != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                nearestDDay.color.withOpacity(0.08),
                nearestDDay.color.withOpacity(0.02)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: nearestDDay.color.withOpacity(0.2))),
            child: Row(children: [
              Text('🎯', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text(nearestDDay.name,
                style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: OC.text1))),
              Text(nearestDDay.dDayLabel, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: nearestDDay.color)),
            ]),
          ),
        // 현재 기간
        if (period != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OC.cardHi, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OC.border.withOpacity(0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                orderChip('Period ${period.id}', OC.accent, OC.accentBg),
                const SizedBox(width: 8),
                Expanded(child: Text(period.name,
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: OC.text1))),
              ]),
              const SizedBox(height: 8),
              // 진행률 바
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: period.progressForDate(today),
                  backgroundColor: OC.accent.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation(OC.accent),
                  minHeight: 5)),
              const SizedBox(height: 4),
              Text('${period.start} ~ ${period.end}',
                style: const TextStyle(fontSize: 10, color: OC.text3)),
            ]),
          ),
        ],
        // 서브기간
        if (subPeriod != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OC.bgSub, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📌 ${subPeriod.name}', style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: OC.text1)),
              if (subPeriod.primaryGoal.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subPeriod.primaryGoal, style: const TextStyle(
                  fontSize: 11, color: OC.text2)),
              ],
            ]),
          ),
        ],
        // 오늘 학습 계획
        if (dailyPlan != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StudyPlanData.tagColor(dailyPlan.tag ?? 'rest')
                  .withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: StudyPlanData.tagColor(dailyPlan.tag ?? 'rest')
                    .withOpacity(0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (dailyPlan.label != null)
                  orderChip(dailyPlan.label!,
                    StudyPlanData.tagColor(dailyPlan.tag ?? 'rest'),
                    StudyPlanData.tagColor(dailyPlan.tag ?? 'rest')
                        .withOpacity(0.12)),
                const SizedBox(width: 8),
                Expanded(child: Text(dailyPlan.title ?? '',
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: OC.text1))),
              ]),
              if (dailyPlan.coaching != null) ...[
                const SizedBox(height: 6),
                Text(dailyPlan.coaching!, style: const TextStyle(
                  fontSize: 11, color: OC.text2, fontStyle: FontStyle.italic)),
              ],
              if (dailyPlan.tasks.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...dailyPlan.tasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    const Text('  • ', style: TextStyle(
                      fontSize: 10, color: OC.text3)),
                    Expanded(child: Text(t, style: const TextStyle(
                      fontSize: 11, color: OC.text2))),
                  ]),
                )),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  // ═══ VISION CARD (장기 Mesh Gradient) ═══
  Widget _visionCard() {
    final long = data.goals
        .where((g) => g.tier == GoalTier.marathon && !g.isFinished).toList();
    if (long.isEmpty) return const SizedBox.shrink();
    final g = long.first;

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
        boxShadow: [BoxShadow(
          color: const Color(0xFF667eea).withOpacity(.3),
          blurRadius: 20, offset: const Offset(0, 10))]),
      child: Stack(children: [
        Positioned(top: -30, right: -20,
          child: Container(width: 120, height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Colors.white.withOpacity(.15), Colors.transparent])))),
        Positioned(bottom: -40, left: -20,
          child: Container(width: 100, height: 100,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFFffd89b).withOpacity(.2), Colors.transparent])))),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.2),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text('🎯 VISION', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withOpacity(.9), letterSpacing: 1))),
                const Spacer(),
                if (g.dDayLabel.isNotEmpty) Text(g.dDayLabel,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(.9))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.title, style: const TextStyle(fontSize: 22,
                  fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: g.progress / 100,
                      backgroundColor: Colors.white.withOpacity(.2),
                      valueColor: AlwaysStoppedAnimation(
                        Colors.white.withOpacity(.9)),
                      minHeight: 6))),
                  const SizedBox(width: 12),
                  Text('${g.progress}%', style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: Colors.white)),
                ]),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  // ═══ SPRINT BOARD ═══
  Widget _sprintBoard() {
    final sprints = data.goals
        .where((g) => g.tier == GoalTier.sprint && !g.isFinished).toList();
    if (sprints.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(children: [
          const Icon(Icons.bolt_rounded, size: 18, color: OC.sprint),
          const SizedBox(width: 6),
          const Text('Sprint Board', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: OC.text1)),
        ]),
      ),
      SizedBox(height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: sprints.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final g = sprints[i];
            return Container(
              width: 200, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OC.card, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: OC.sprint.withOpacity(.2)),
                boxShadow: [BoxShadow(color: OC.sprint.withOpacity(.08),
                  blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Text('⚡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(g.title, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: OC.text1),
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (g.dDayLabel.isNotEmpty)
                        Text(g.dDayLabel, style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: OC.sprint)),
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: g.progress / 100,
                          backgroundColor: OC.sprintBg,
                          valueColor: const AlwaysStoppedAnimation(OC.sprint),
                          minHeight: 6)),
                      const SizedBox(height: 4),
                      Text('${g.progress}% 완료', style: const TextStyle(
                        fontSize: 10, color: OC.text3)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ═══ MILESTONE TIMELINE ═══
  Widget _milestoneTimeline() {
    final mids = data.goals
        .where((g) => g.tier == GoalTier.race).toList();
    if (mids.isEmpty) return const SizedBox.shrink();

    return orderSectionCard(
      title: '마일스톤 타임라인', icon: Icons.linear_scale_rounded,
      children: mids.map((g) {
        final c = OC.race;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 14, height: 14,
              decoration: BoxDecoration(
                color: g.isCompleted ? c : OC.card,
                shape: BoxShape.circle,
                border: Border.all(color: c, width: 2),
                boxShadow: g.isCompleted
                    ? [BoxShadow(color: c.withOpacity(.3), blurRadius: 6)]
                    : null)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.title, style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: OC.text1)),
                Row(children: [
                  if (g.dDayLabel.isNotEmpty) Text(g.dDayLabel,
                    style: TextStyle(fontSize: 10, color: c,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text('${g.progress}%', style: const TextStyle(
                    fontSize: 10, color: OC.text3)),
                ]),
              ],
            )),
            SizedBox(width: 60,
              child: ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: g.progress / 100,
                  backgroundColor: OC.raceBg,
                  valueColor: AlwaysStoppedAnimation(c), minHeight: 4))),
          ]),
        );
      }).toList(),
    );
  }

  // ═══ GOAL CHAIN VIEW ═══
  Widget _goalChainView() {
    final marathon = data.goals
        .where((g) => g.tier == GoalTier.marathon).toList();
    if (marathon.isEmpty) return const SizedBox.shrink();

    return orderSectionCard(
      title: '목표 체인', icon: Icons.account_tree_rounded,
      children: marathon.map((mg) {
        final children = data.goals
            .where((g) => g.parentGoalId == mg.id).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _chainNode(mg, 0),
          ...children.map((cg) {
            final grandChildren = data.goals
                .where((g) => g.parentGoalId == cg.id).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                _chainNode(cg, 1),
                ...grandChildren.map((gg) => _chainNode(gg, 2)),
              ],
            );
          }),
        ]);
      }).toList(),
    );
  }

  Widget _chainNode(OrderGoal g, int depth) {
    final c = tierColor(g.tier);
    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0, bottom: 8),
      child: Row(children: [
        if (depth > 0) ...[
          Container(width: 1, height: 20, color: OC.border),
          const SizedBox(width: 8),
          Container(width: 16, height: 1, color: OC.border),
          const SizedBox(width: 4),
        ],
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(g.title, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: g.isCompleted ? OC.text3 : OC.text1,
          decoration: g.isCompleted ? TextDecoration.lineThrough : null))),
        Text('${g.progress}%', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  // ═══ ALL GOALS LIST ═══
  Widget _allGoalsList(BuildContext context) {
    return orderSectionCard(
      title: '전체 목표', icon: Icons.list_alt_rounded,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // 리빌딩 초기화 버튼
        GestureDetector(
          onTap: () => _confirmReseed(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.restart_alt_rounded, size: 18,
              color: Color(0xFFD97706))),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _openGoalSheet(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: OC.accentBg, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.add_rounded, size: 18, color: OC.accent)),
        ),
      ]),
      children: data.goals.where((g) => !g.isFinished)
          .map((g) => _goalCard(g, context)).toList(),
    );
  }

  // ═══ FAILED GOALS SECTION (실패 목표) ═══
  Widget _failedGoalsSection(BuildContext context) {
    final failed = data.goals.where((g) => g.isFailed).toList();
    if (failed.isEmpty) return const SizedBox.shrink();

    return orderSectionCard(
      title: '실패 기록', icon: Icons.highlight_off_rounded,
      children: failed.map((g) => _goalCard(g, context)).toList(),
    );
  }

  Widget _goalCard(OrderGoal g, BuildContext context) {
    final c = g.isFailed ? const Color(0xFFEF4444) : tierColor(g.tier);
    return GestureDetector(
      onTap: () => _openGoalDetail(context, g),
      onLongPress: () => g.isFinished ? null : _cyclePriority(g),
      child: Opacity(
        opacity: g.isFailed ? 0.75 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: g.isFailed
                ? const Color(0xFFFEF2F2)
                : tierBg(g.tier),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: g.isFailed
                ? const Color(0xFFEF4444).withOpacity(.25)
                : g.priority > 0
                    ? (g.priority == 1 ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8))
                        .withOpacity(.4)
                    : c.withOpacity(.2)),
            boxShadow: g.priority > 0 && !g.isFinished
                ? [BoxShadow(
                    color: (g.priority == 1 ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8))
                        .withOpacity(.08),
                    blurRadius: 8, offset: const Offset(0, 2))]
                : null),
          child: Row(children: [
            // 실패 아이콘 or 순위 배지 or 이모지
            if (g.isFailed)
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(.12),
                  borderRadius: BorderRadius.circular(10)),
                child: const Center(child: Icon(Icons.close_rounded,
                  size: 18, color: Color(0xFFEF4444))),
              )
            else if (g.priority > 0)
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: g.priority == 1
                      ? const Color(0xFFFBBF24).withOpacity(.15)
                      : const Color(0xFF94A3B8).withOpacity(.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: g.priority == 1
                      ? const Color(0xFFFBBF24).withOpacity(.3)
                      : const Color(0xFF94A3B8).withOpacity(.3))),
                child: Center(child: Text('${g.priority}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                    color: g.priority == 1
                        ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8)))),
              )
            else
              Text(g.tierEmoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.title, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: g.isFailed ? const Color(0xFFEF4444) : OC.text1,
                  decoration: g.isFailed ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 4),
                Row(children: [
                  if (g.isFailed)
                    orderChip('실패', const Color(0xFFEF4444),
                        const Color(0xFFFEE2E2))
                  else
                    orderChip(g.tierLabel, c, c.withOpacity(.15)),
                  const SizedBox(width: 6),
                  if (g.dDayLabel.isNotEmpty)
                    orderChip(g.dDayLabel, OC.text2, OC.bgSub),
                  if (g.priority > 0 && !g.isFinished) ...[
                    const SizedBox(width: 6),
                    orderChip('${g.priority}순위',
                      g.priority == 1 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                      g.priority == 1
                          ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9)),
                  ],
                  if (g.isFailed && g.failedNote != null && g.failedNote!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(child: Text(g.failedNote!,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ]),
                if (!g.isFailed) ...[
                  const SizedBox(height: 6),
                  ClipRRect(borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: g.progress / 100,
                      backgroundColor: c.withOpacity(.15),
                      valueColor: AlwaysStoppedAnimation(c), minHeight: 5)),
                ],
              ],
            )),
            if (!g.isFailed) ...[
              const SizedBox(width: 10),
              Text('${g.progress}%', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: c)),
            ],
          ]),
        ),
      ),
    );
  }

  // ═══ 리빌딩 목표 초기화 ═══
  void _confirmReseed(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Text('🔄', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('리빌딩 목표 초기화', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          '2차 중간평가 기반 목표 체계로 초기화합니다.\n'
          '기존 목표와 습관이 모두 교체됩니다.',
          style: TextStyle(fontSize: 13, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
            child: const Text('취소')),
          TextButton(onPressed: () {
            onUpdate(() {
              data.goals
                ..clear()
                ..addAll(StudyPlanData.seedGoals());
              data.habits
                ..clear()
                ..addAll(StudyPlanData.seedHabits());
            });
            Navigator.pop(c);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('리빌딩 목표 + 습관 초기화 완료'),
              behavior: SnackBarBehavior.floating));
          }, child: const Text('초기화', style: TextStyle(
            color: Color(0xFFD97706), fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  /// 순위 순환: 0 → 1 → 2 → 0
  void _cyclePriority(OrderGoal g) {
    onUpdate(() {
      final oldPriority = g.priority;
      final newPriority = (oldPriority + 1) % 3;

      // 같은 순위의 기존 목표 해제
      if (newPriority > 0) {
        for (final other in data.goals) {
          if (other.id != g.id && other.priority == newPriority) {
            other.priority = 0;
          }
        }
      }
      g.priority = newPriority;
    });
  }

  // ═══ GOAL SHEET (Add / Edit) ═══
  void _openGoalSheet(BuildContext context, {OrderGoal? editing}) {
    final isEdit = editing != null;
    final titleC = TextEditingController(text: editing?.title ?? '');
    final descC = TextEditingController(text: editing?.desc ?? '');
    final deadlineC = TextEditingController(text: editing?.deadline ?? '');
    var selectedTier = editing?.tier ?? GoalTier.sprint;
    var selectedArea = editing?.area ?? GoalArea.study;
    var selectedPriority = editing?.priority ?? 0;
    String? parentId = editing?.parentGoalId;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .85),
          decoration: const BoxDecoration(color: OC.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.fromLTRB(
            20, 8, 20, sheetBottomPad(ctx)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              sheetHandle(),
              Text(isEdit ? '목표 수정' : '새 목표', style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1)),
              const SizedBox(height: 16),
              sheetField('제목', titleC, '목표명을 입력하세요'),
              sheetField('설명', descC, '상세 설명 (선택)', maxLines: 2),
              // 티어
              Row(children: GoalTier.values.map((t) {
                final sel = selectedTier == t;
                final c = tierColor(t);
                return Expanded(child: GestureDetector(
                  onTap: () => setS(() => selectedTier = t),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? c.withOpacity(.15) : OC.cardHi,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? c : OC.border)),
                    child: Column(children: [
                      Text(t == GoalTier.sprint ? '⚡'
                          : t == GoalTier.race ? '📌' : '🎯'),
                      Text(t == GoalTier.sprint ? '단기'
                          : t == GoalTier.race ? '중기' : '장기',
                        style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: sel ? c : OC.text3)),
                    ]),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 8),
              // 영역
              Row(children: GoalArea.values.map((a) => Expanded(
                child: areaBtn(
                  a == GoalArea.study ? '📚 공부' : '🏃 생활',
                  a, selectedArea, (v) => setS(() => selectedArea = v)),
              )).toList()),
              const SizedBox(height: 8),
              // 순위 선택
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setS(() => selectedPriority = 0),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selectedPriority == 0 ? OC.cardHi : OC.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedPriority == 0 ? OC.text3 : OC.border)),
                    child: const Center(child: Text('순위 없음',
                      style: TextStyle(fontSize: 11, color: OC.text3))),
                  ),
                )),
                Expanded(child: GestureDetector(
                  onTap: () => setS(() => selectedPriority = 1),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selectedPriority == 1
                          ? const Color(0xFFFEF3C7) : OC.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selectedPriority == 1
                          ? const Color(0xFFFBBF24) : OC.border)),
                    child: Center(child: Text('🥇 1순위',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: selectedPriority == 1
                            ? const Color(0xFFD97706) : OC.text3))),
                  ),
                )),
                Expanded(child: GestureDetector(
                  onTap: () => setS(() => selectedPriority = 2),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selectedPriority == 2
                          ? const Color(0xFFF1F5F9) : OC.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selectedPriority == 2
                          ? const Color(0xFF94A3B8) : OC.border)),
                    child: Center(child: Text('🥈 2순위',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: selectedPriority == 2
                            ? const Color(0xFF64748B) : OC.text3))),
                  ),
                )),
              ]),
              const SizedBox(height: 8),
              sheetField('기한', deadlineC, 'YYYY-MM-DD'),
              const SizedBox(height: 16),
              Row(children: [
                if (isEdit) ...[
                  Expanded(child: sheetBtn('삭제', OC.errorBg, OC.error, () {
                    onUpdate(() {
                      data.goals.removeWhere((g) => g.id == editing.id);
                    });
                    Navigator.pop(ctx);
                  })),
                  const SizedBox(width: 10),
                ],
                Expanded(child: sheetBtn(
                  isEdit ? '저장' : '추가', OC.accent, Colors.white, () {
                    if (titleC.text.isEmpty) return;
                    onUpdate(() {
                      if (isEdit) {
                        editing.title = titleC.text;
                        editing.desc = descC.text;
                        editing.tier = selectedTier;
                        editing.area = selectedArea;
                        editing.priority = selectedPriority;
                        editing.deadline = deadlineC.text.isNotEmpty
                            ? deadlineC.text : null;
                        editing.parentGoalId = parentId;
                        // 동일 순위 중복 방지
                        if (selectedPriority > 0) {
                          for (final g in data.goals) {
                            if (g.id != editing.id && g.priority == selectedPriority) {
                              g.priority = 0;
                            }
                          }
                        }
                      } else {
                        // 동일 순위 중복 방지
                        if (selectedPriority > 0) {
                          for (final g in data.goals) {
                            if (g.priority == selectedPriority) {
                              g.priority = 0;
                            }
                          }
                        }
                        data.goals.add(OrderGoal(
                          id: 'g_${DateTime.now().millisecondsSinceEpoch}',
                          title: titleC.text, desc: descC.text,
                          tier: selectedTier, area: selectedArea,
                          priority: selectedPriority,
                          deadline: deadlineC.text.isNotEmpty
                              ? deadlineC.text : null,
                          parentGoalId: parentId,
                        ));
                      }
                    });
                    Navigator.pop(ctx);
                  },
                )),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  // ═══ GOAL DETAIL SHEET ═══
  void _openGoalDetail(BuildContext context, OrderGoal g) {
    final c = tierColor(g.tier);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .75),
          decoration: const BoxDecoration(color: OC.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.fromLTRB(20, 8, 20, sheetBottomPad(ctx)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              sheetHandle(),
              const SizedBox(height: 8),
              Row(children: [
                Text(g.tierEmoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.title, style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800, color: OC.text1)),
                    Row(children: [
                      orderChip(g.tierLabel, c, tierBg(g.tier)),
                      const SizedBox(width: 6),
                      if (g.dDayLabel.isNotEmpty)
                        orderChip(g.dDayLabel, OC.text2, OC.bgSub),
                    ]),
                  ],
                )),
              ]),
              const SizedBox(height: 16),
              // 프로그레스
              Row(children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: g.progress / 100,
                    backgroundColor: tierBg(g.tier),
                    valueColor: AlwaysStoppedAnimation(c), minHeight: 10))),
                const SizedBox(width: 12),
                Text('${g.progress}%', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: c)),
              ]),
              const SizedBox(height: 16),
              // 마일스톤
              if (g.milestones.isNotEmpty) ...[
                const Align(alignment: Alignment.centerLeft,
                  child: Text('마일스톤', style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: OC.text1))),
                const SizedBox(height: 8),
                ...g.milestones.map((m) => GestureDetector(
                  onTap: () {
                    setS(() { m.done = !m.done; g.recalcFromMilestones(); });
                    onUpdate(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.done ? OC.successBg : OC.cardHi,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: m.done
                          ? OC.success.withOpacity(.2) : OC.border)),
                    child: Row(children: [
                      Icon(m.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: m.done ? OC.success : OC.text4),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m.text, style: TextStyle(
                        fontSize: 13, color: OC.text1,
                        decoration: m.done
                            ? TextDecoration.lineThrough : null))),
                    ]),
                  ),
                )),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: sheetBtn(
                  '수정', OC.accentBg, OC.accent, () {
                    Navigator.pop(ctx);
                    _openGoalSheet(context, editing: g);
                  },
                )),
                const SizedBox(width: 10),
                if (g.isFailed)
                  // 실패 → 재개
                  Expanded(child: sheetBtn(
                    '재개', const Color(0xFF22C55E), Colors.white, () {
                      onUpdate(() {
                        g.failedAt = null;
                        g.failedNote = null;
                      });
                      Navigator.pop(ctx);
                    },
                  ))
                else ...[
                  // 실패 처리 버튼
                  Expanded(child: sheetBtn(
                    '실패', const Color(0xFFEF4444), Colors.white, () {
                      Navigator.pop(ctx);
                      _showFailDialog(context, g);
                    },
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: sheetBtn(
                    g.isCompleted ? '재개' : '완료', OC.accent, Colors.white, () {
                      onUpdate(() {
                        g.completedAt = g.isCompleted
                            ? null : DateTime.now().toIso8601String();
                        if (!g.isCompleted) g.progress = 100;
                      });
                      Navigator.pop(ctx);
                    },
                  )),
                ],
              ]),
            ]),
          ),
        );
      }),
    );
  }

  /// ★ 실패 처리 다이얼로그 (사유 입력)
  Future<void> _showFailDialog(BuildContext context, OrderGoal g) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 20,
            color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          const Text('목표 실패 기록', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('「${g.title}」을(를) 실패로 기록합니다.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 14),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: '실패 사유 (선택)',
              labelStyle: TextStyle(fontSize: 12),
              hintText: '예: 응시 실패, 기한 초과...',
              hintStyle: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('실패 기록',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (confirmed == true) {
      onUpdate(() {
        g.failedAt = DateTime.now().toIso8601String();
        g.failedNote = noteCtrl.text.trim().isNotEmpty
            ? noteCtrl.text.trim() : null;
        g.priority = 0; // 실패 시 우선순위 해제
      });
    }
    noteCtrl.dispose();
  }
}