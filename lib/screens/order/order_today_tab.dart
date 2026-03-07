import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// TAB 1 — 오늘 (Today)
/// Daily Score · Routine (NFC 연동) · Radar · Habits · AI Coach
/// ═══════════════════════════════════════════════════════════

class OrderTodayTab extends StatelessWidget {
  final OrderData data;
  final void Function(VoidCallback fn) onUpdate;
  final Future<void> Function() onLoad;

  /// NFC 이벤트 기반 실제 시간 (role → "HH:mm")
  /// 예: { "wake": "05:45", "ready": "06:12", ... }
  final Map<String, String> nfcActualTimes;

  const OrderTodayTab({
    super.key, required this.data,
    required this.onUpdate, required this.onLoad,
    this.nfcActualTimes = const {},
  });

  String get _today => todayStr();

  // ── Score ──
  int get _dailyOrderScore {
    if (data.habits.isEmpty) return 0;
    final active = data.habits.where((h) => !h.archived).toList();
    if (active.isEmpty) return 0;
    int done = active.where((h) => h.isDoneOn(_today)).length;
    double base = (done / active.length) * 70;
    double streakBonus = 0;
    for (var h in active) {
      if (h.currentStreak >= 7) streakBonus += 5;
      if (h.currentStreak >= 21) streakBonus += 5;
    }
    final todayStress = data.stressLogs.where((s) {
      final d = s.dateTime;
      final now = DateTime.now();
      return d.year == now.year && d.month == now.month && d.day == now.day
          && s.type != StressType.alternative;
    }).length;
    double penalty = todayStress * 10.0;
    return (base + streakBonus - penalty).clamp(0, 100).round();
  }

  /// 레이더 값: NFC 실제 데이터 기반 달성률 계산
  List<double> get _radarValues {
    final rt = data.routineTarget;
    final targets = {
      '기상': rt.wakeTime ?? '05:30',
      '준비': rt.readyTime ?? '06:00',
      '외출': rt.outingTime ?? '07:00',
      '공부': rt.studyTime ?? '08:00',
      '수면': rt.sleepTime ?? '23:00',
    };
    final roleMap = {
      '기상': 'wake', '준비': 'ready', '외출': 'outing',
      '공부': 'study', '수면': 'sleep',
    };

    return targets.entries.map((e) {
      final role = roleMap[e.key]!;
      final actual = nfcActualTimes[role];
      if (actual == null) return 0.3; // 미기록 → 낮은 값

      final targetMin = _parseTimeToMin(e.value);
      final actualMin = _parseTimeToMin(actual);
      final diff = (actualMin - targetMin).abs();

      // 0분 차이=1.0, 60분 이상=0.2
      return (1.0 - (diff / 60.0)).clamp(0.2, 1.0);
    }).toList();
  }

  int _parseTimeToMin(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onLoad, color: OC.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          _todayHeader(),
          const SizedBox(height: 16),
          _dailyScoreCard(),
          const SizedBox(height: 16),
          _routineTimeline(context),
          const SizedBox(height: 16),
          _pentagonRadar(),
          const SizedBox(height: 16),
          _todayHabitsSection(context),
          const SizedBox(height: 16),
          _aiCoachingCard(),
          const SizedBox(height: 16),
          _upcomingGoalsSection(),
        ],
      ),
    );
  }

  // ═══ HEADER ═══
  Widget _todayHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [OC.accent, OC.accentLt]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: OC.accent.withOpacity(.2),
              blurRadius: 8, offset: const Offset(0, 3))]),
          child: const Text('COMPASS', style: TextStyle(color: Colors.white,
            fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('나침반', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w800, color: OC.text1)),
          Text(DateFormat('M월 d일 EEEE', 'ko').format(DateTime.now()),
            style: const TextStyle(fontSize: 12, color: OC.text3)),
        ]),
      ]),
    );
  }

  // ═══ DAILY ORDER SCORE (Compact Inline v4.2) ═══
  Widget _dailyScoreCard() {
    final score = _dailyOrderScore;
    final grade = score >= 90 ? 'S' : score >= 75 ? 'A'
        : score >= 60 ? 'B' : score >= 40 ? 'C' : 'D';
    final gradeColor = score >= 75 ? OC.success
        : score >= 50 ? OC.amber : OC.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.accent.withOpacity(.12)),
        boxShadow: [BoxShadow(color: OC.accent.withOpacity(.04),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: Row(children: [
        // 스코어
        Text('$score', style: const TextStyle(fontSize: 36,
          fontWeight: FontWeight.w900, color: OC.text1, height: 1)),
        const SizedBox(width: 4),
        Text('/100', style: TextStyle(fontSize: 12,
          color: OC.text4, fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        // 등급 배지
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: gradeColor.withOpacity(.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: gradeColor.withOpacity(.2))),
          child: Text(grade, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w900, color: gradeColor)),
        ),
        const Spacer(),
        // 미니 진행바
        SizedBox(width: 80, child: Column(
          crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('ORDER SCORE', style: TextStyle(fontSize: 8,
              fontWeight: FontWeight.w700, color: OC.text4,
              letterSpacing: 1)),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: score / 100,
                backgroundColor: OC.border,
                valueColor: AlwaysStoppedAnimation(gradeColor),
                minHeight: 4)),
          ],
        )),
      ]),
    );
  }

  // ═══ ROUTINE TIMELINE (NFC 실시간 연동) ═══
  Widget _routineTimeline(BuildContext context) {
    final rt = data.routineTarget;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    // (라벨, 이모지, 목표시간, role키, 색상)
    final roles = [
      ('기상', '☀️', rt.wakeTime ?? '05:30', 'wake', OC.amber),
      ('준비', '🪥', rt.readyTime ?? '06:00', 'ready', OC.accent),
      ('외출', '🚶', rt.outingTime ?? '07:00', 'outing', OC.success),
      ('공부', '📚', rt.studyTime ?? '08:00', 'study', OC.race),
      ('수면', '🌙', rt.sleepTime ?? '23:00', 'sleep', OC.marathon),
    ];

    return orderSectionCard(
      title: '루틴 타임라인', icon: Icons.timeline_rounded,
      trailing: GestureDetector(
        onTap: () => _openRoutineSettings(context),
        child: const Icon(Icons.tune_rounded, size: 18, color: OC.text3)),
      children: roles.map((r) {
        final targetStr = r.$3;
        final roleKey = r.$4;
        final actual = nfcActualTimes[roleKey];
        final targetMin = _parseTimeToMin(targetStr);

        // ── 상태 판별 ──
        String statusEmoji;
        String actualDisplay;
        int offset = 0;
        Color diffColor;
        bool isRecorded = actual != null;
        bool isPast = nowMin > targetMin + 30; // 목표시간 30분 경과

        if (isRecorded) {
          // NFC 기록 있음 → 실제 시간 표시
          final actualMin = _parseTimeToMin(actual);
          offset = actualMin - targetMin;
          actualDisplay = actual;

          if (offset.abs() <= 10) {
            statusEmoji = '✅';
            diffColor = OC.success;
          } else if (offset.abs() <= 30) {
            statusEmoji = '⚠️';
            diffColor = OC.amber;
          } else {
            statusEmoji = '🔴';
            diffColor = OC.error;
          }
        } else if (isPast) {
          // 시간 경과했는데 기록 없음 → 미수행
          statusEmoji = '⏳';
          actualDisplay = '미기록';
          diffColor = OC.text4;
        } else {
          // 아직 시간 안 됨 → 대기 중
          statusEmoji = '🔜';
          actualDisplay = '대기 중';
          diffColor = OC.text4;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            // 타임라인 도트
            Column(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isRecorded
                      ? r.$5.withOpacity(.12) : OC.bgSub,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isRecorded
                        ? r.$5.withOpacity(.3) : OC.border,
                    width: isRecorded ? 1.5 : 1)),
                child: Center(child: Text(r.$2,
                  style: const TextStyle(fontSize: 16))),
              ),
            ]),
            const SizedBox(width: 12),
            // 정보
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: OC.text1)),
                Row(children: [
                  Text('목표 $targetStr', style: const TextStyle(
                    fontSize: 11, color: OC.text3)),
                  const SizedBox(width: 8),
                  Text('→', style: TextStyle(fontSize: 11, color: OC.text4)),
                  const SizedBox(width: 8),
                  Text(isRecorded ? '실제 $actualDisplay' : actualDisplay,
                    style: TextStyle(fontSize: 11,
                      fontWeight: isRecorded
                          ? FontWeight.w600 : FontWeight.w400,
                      color: isRecorded ? diffColor : OC.text4)),
                ]),
              ],
            )),
            // 차이 뱃지
            if (isRecorded) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: offset.abs() <= 10 ? OC.successBg
                      : offset.abs() <= 30 ? OC.amberBg : OC.errorBg,
                  borderRadius: BorderRadius.circular(10)),
                child: Text(
                  offset == 0 ? '정시'
                      : offset > 0 ? '+${offset}분' : '${offset}분',
                  style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700, color: diffColor)),
              ),
              const SizedBox(width: 4),
            ],
            Text(statusEmoji, style: const TextStyle(fontSize: 14)),
          ]),
        );
      }).toList(),
    );
  }

  // ═══ PENTAGON RADAR ═══
  Widget _pentagonRadar() {
    return orderSectionCard(
      title: '균형 레이더', icon: Icons.pentagon_rounded,
      children: [
        SizedBox(height: 220, child: CustomPaint(
          size: const Size(double.infinity, 220),
          painter: RadarPainter(
            values: _radarValues,
            labels: ['기상', '준비', '외출', '공부', '수면']),
        )),
        // 레이더 범례
        if (nfcActualTimes.isEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: OC.amberBg,
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Text('📡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'NFC 태그를 터치하면 실제 달성률이 반영됩니다',
                style: TextStyle(fontSize: 11, color: OC.amber,
                  fontWeight: FontWeight.w600))),
            ]),
          ),
      ],
    );
  }

  // ═══ TODAY HABITS ═══
  Widget _todayHabitsSection(BuildContext context) {
    final active = data.habits.where((h) => !h.archived && !h.isSettled).toList();
    final focus = active.where((h) => h.rank == 1).toList();
    final queue = active.where((h) => h.rank > 1).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final unranked = active.where((h) => h.rank == 0).toList();

    // 완료 카운트
    final allActive = [...focus, ...queue, ...unranked];
    final doneCount = allActive.where((h) => h.isDoneOn(_today)).length;

    return orderSectionCard(
      title: '오늘의 습관', icon: Icons.check_circle_rounded,
      trailing: Text('$doneCount/${allActive.length}', style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: OC.text3)),
      children: [
        // ── 집중 습관 ──
        if (focus.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: OC.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: OC.amber.withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🔥', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 4),
                  const Text('집중', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: OC.amber, letterSpacing: 0.5)),
                ]),
              ),
            ]),
          ),
          ...focus.map((h) => _habitCheckRow(h, context, isFocusSection: true)),
        ],

        // ── 대기열 ──
        if (queue.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.only(top: focus.isNotEmpty ? 12 : 0, bottom: 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF94A3B8).withOpacity(0.15))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('⏳', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 4),
                  Text('대기열 ${queue.length}', style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8), letterSpacing: 0.5)),
                ]),
              ),
            ]),
          ),
          ...queue.map((h) => _habitCheckRow(h, context, isFocusSection: false)),
        ],

        // ── 미지정 ──
        if (unranked.isNotEmpty) ...[
          if (focus.isNotEmpty || queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(height: 1, color: OC.border.withOpacity(0.3))),
          ...unranked.map((h) => _habitCheckRow(h, context, isFocusSection: false)),
        ],
      ],
    );
  }

  Widget _habitCheckRow(OrderHabit h, BuildContext context,
      {bool isFocusSection = false}) {
    final done = h.isDoneOn(_today);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        // ★ 미완료 → 바로 완료 (원터치)
        // ★ 완료 → 확인 다이얼로그 후 취소 가능
        onTap: () {
          if (!done) {
            onUpdate(() { h.completedDates.add(_today); });
            HapticFeedback.mediumImpact();
          } else {
            _confirmUndoHabit(context, h);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: done ? OC.successBg
                : (isFocusSection ? OC.amberBg : OC.cardHi),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: done ? OC.success.withOpacity(.25)
                  : (isFocusSection ? OC.amber.withOpacity(.2) : OC.border.withOpacity(0.4)))),
          child: Row(children: [
            Text(h.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(h.title, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: OC.text1,
                    decoration: done ? TextDecoration.lineThrough : null),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (isFocusSection && h.daysToSettle > 0) ...[
                    const SizedBox(width: 6),
                    Text('${h.daysToSettle}일', style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700, color: OC.amber)),
                  ],
                ]),
                Text('${h.growthEmoji} ${h.currentStreak}일 연속',
                  style: const TextStyle(fontSize: 10, color: OC.text4)),
              ],
            )),
            // 체크 아이콘
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: done ? OC.success : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: done ? OC.success : OC.text4.withOpacity(0.5), width: 2)),
              child: done
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : null),
          ]),
        ),
      ),
    );
  }

  /// ★ 완료 취소 확인 다이얼로그
  void _confirmUndoHabit(BuildContext context, OrderHabit h) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${h.emoji} 완료 취소', style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('「${h.title}」 오늘 기록을 취소할까요?',
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('아니요')),
          TextButton(onPressed: () {
            onUpdate(() { h.completedDates.remove(_today); });
            HapticFeedback.lightImpact();
            Navigator.pop(ctx);
          }, child: const Text('취소하기',
            style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
  }

  // ═══ AI COACHING ═══
  Widget _aiCoachingCard() {
    final insights = <String>[];
    final active = data.habits.where((h) => !h.archived).toList();
    for (var h in active) {
      if (h.currentStreak >= 7) {
        insights.add('${h.emoji} ${h.title} ${h.currentStreak}일 연속 달성 중! 좋은 흐름입니다.');
      }
    }

    // NFC 기반 코칭
    if (nfcActualTimes.isNotEmpty) {
      final rt = data.routineTarget;
      final wakeTarget = rt.wakeTime ?? '05:30';
      final wakeActual = nfcActualTimes['wake'];
      if (wakeActual != null) {
        final diff = _parseTimeToMin(wakeActual) - _parseTimeToMin(wakeTarget);
        if (diff <= 5) {
          insights.add('🌅 오늘 기상 시간 우수합니다! 목표 대비 ${diff > 0 ? "+$diff" : "$diff"}분');
        } else if (diff > 30) {
          insights.add('⏰ 기상이 ${diff}분 지연되었습니다. 내일은 알람을 앞당겨보세요.');
        }
      }

      final recorded = nfcActualTimes.length;
      if (recorded >= 4) {
        insights.add('📊 루틴 $recorded/5 기록 완료! 훌륭한 추적력입니다.');
      }
    } else {
      insights.add('📡 NFC 태그를 터치해서 루틴을 기록해보세요.');
    }

    if (data.stressLogs
        .where((s) => s.type != StressType.alternative).length >= 3) {
      insights.add('⚠️ 최근 스트레스 행동이 잦습니다. 대체 행동을 시도해보세요.');
    }
    if (insights.isEmpty) {
      insights.add('💡 꾸준한 루틴 유지가 핵심입니다. 오늘도 질서를 지켜보세요.');
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [OC.accent.withOpacity(.08), OC.accentBg.withOpacity(.5)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OC.accent.withOpacity(.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: OC.accent.withOpacity(.12),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome_rounded,
              size: 18, color: OC.accent)),
          const SizedBox(width: 10),
          const Text('AI 코칭', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800, color: OC.text1)),
        ]),
        const SizedBox(height: 12),
        ...insights.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s, style: const TextStyle(
            fontSize: 12, color: OC.text2, height: 1.5)),
        )),
      ]),
    );
  }

  // ═══ UPCOMING GOALS ═══
  Widget _upcomingGoalsSection() {
    final upcoming = data.goals.where((g) => !g.isCompleted).take(3).toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return orderSectionCard(
      title: '진행 중 목표', icon: Icons.flag_rounded,
      children: upcoming.map((g) => _miniGoalRow(g)).toList(),
    );
  }

  Widget _miniGoalRow(OrderGoal g) {
    final c = tierColor(g.tier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tierBg(g.tier), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(.2))),
        child: Row(children: [
          Text(g.tierEmoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.title, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: OC.text1)),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: g.progress / 100,
                  backgroundColor: c.withOpacity(.15),
                  valueColor: AlwaysStoppedAnimation(c), minHeight: 4)),
            ],
          )),
          const SizedBox(width: 10),
          Column(children: [
            Text('${g.progress}%', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: c)),
            if (g.dDayLabel.isNotEmpty)
              Text(g.dDayLabel, style: const TextStyle(
                fontSize: 10, color: OC.text3)),
          ]),
        ]),
      ),
    );
  }

  // ═══ ROUTINE SETTINGS SHEET ═══
  void _openRoutineSettings(BuildContext context) {
    final rt = data.routineTarget;
    final wakeC = TextEditingController(text: rt.wakeTime ?? '05:30');
    final readyC = TextEditingController(text: rt.readyTime ?? '06:00');
    final outingC = TextEditingController(text: rt.outingTime ?? '07:00');
    final studyC = TextEditingController(text: rt.studyTime ?? '08:00');
    final sleepC = TextEditingController(text: rt.sleepTime ?? '23:00');

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(color: OC.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(
          20, 8, 20, sheetBottomPad(ctx, extra: 32)),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            sheetHandle(),
            const Text('이상적 루틴 설정', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1)),
            const SizedBox(height: 16),
            sheetField('☀️ 기상 시간', wakeC, 'HH:mm'),
            sheetField('🪥 준비 완료', readyC, 'HH:mm'),
            sheetField('🚶 외출 시간', outingC, 'HH:mm'),
            sheetField('📚 공부 시작', studyC, 'HH:mm'),
            sheetField('🌙 취침 시간', sleepC, 'HH:mm'),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: sheetBtn('저장', OC.accent, Colors.white, () {
                onUpdate(() {
                  rt.wakeTime = wakeC.text; rt.readyTime = readyC.text;
                  rt.outingTime = outingC.text; rt.studyTime = studyC.text;
                  rt.sleepTime = sleepC.text;
                });
                Navigator.pop(ctx);
              })),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

// ═══ PENTAGON RADAR PAINTER ═══
class RadarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  RadarPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = min(cx, cy) - 30;
    final n = values.length;
    final angleStep = 2 * pi / n;
    final startAngle = -pi / 2;

    // 웹 그리드
    for (int level = 1; level <= 3; level++) {
      final lr = r * level / 3;
      final path = Path();
      for (int i = 0; i <= n; i++) {
        final a = startAngle + angleStep * (i % n);
        final x = cx + lr * cos(a), y = cy + lr * sin(a);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFFE8E2DA)
        ..style = PaintingStyle.stroke..strokeWidth = 1);
    }

    // 축선
    for (int i = 0; i < n; i++) {
      final a = startAngle + angleStep * i;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * cos(a), cy + r * sin(a)),
        Paint()..color = const Color(0xFFE8E2DA)..strokeWidth = 1);
    }

    // 데이터 영역
    final dataPath = Path();
    for (int i = 0; i <= n; i++) {
      final a = startAngle + angleStep * (i % n);
      final v = values[i % n].clamp(0.0, 1.0);
      final x = cx + r * v * cos(a), y = cy + r * v * sin(a);
      i == 0 ? dataPath.moveTo(x, y) : dataPath.lineTo(x, y);
    }
    canvas.drawPath(dataPath, Paint()
      ..color = OC.accent.withOpacity(.2)..style = PaintingStyle.fill);
    canvas.drawPath(dataPath, Paint()
      ..color = OC.accent..style = PaintingStyle.stroke..strokeWidth = 2.5);

    // 점
    for (int i = 0; i < n; i++) {
      final a = startAngle + angleStep * i;
      final v = values[i].clamp(0.0, 1.0);
      final x = cx + r * v * cos(a), y = cy + r * v * sin(a);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = OC.accent);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white);
    }

    // 라벨
    final textStyle = TextStyle(fontSize: 11,
      fontWeight: FontWeight.w600, color: OC.text2);
    for (int i = 0; i < n; i++) {
      final a = startAngle + angleStep * i;
      final lx = cx + (r + 20) * cos(a);
      final ly = cy + (r + 20) * sin(a);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: ui.TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}