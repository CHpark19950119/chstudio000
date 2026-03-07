import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../services/ai_calendar_service.dart';
import '../theme/botanical_theme.dart';
import 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// N1: AI 캘린더 대시보드 위젯
/// - 중요 일정: × 버튼으로 숨기기 (시험 제외)
/// - 메모: ← 스와이프로 삭제
/// ═══════════════════════════════════════════════════════════

class CalendarDashboardCard extends StatefulWidget {
  final VoidCallback? onAddMemo;
  const CalendarDashboardCard({super.key, this.onAddMemo});

  @override
  State<CalendarDashboardCard> createState() => _CalendarDashboardCardState();
}

class _CalendarDashboardCardState extends State<CalendarDashboardCard> {
  final _cal = AiCalendarService();
  CalendarDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    try {
      final d = await _cal.getDashboard();
      if (mounted) _safeSetState(() { _dashboard = d; _loading = false; });
    } catch (e) {
      debugPrint('[CalendarCard] Dashboard load error: $e');
      // 폴백: 빈 대시보드라도 생성하여 캘린더 그리드는 표시
      if (mounted) _safeSetState(() {
        _dashboard = CalendarDashboard(
          todayEvents: [], upcomingEvents: [], memos: [],
          coachingMessage: '', dDay: 0, lastUpdated: DateTime.now());
        _loading = false;
      });
    }
  }

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BotanicalDeco.card(_dk),
        child: Center(child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: BotanicalColors.primary.withOpacity(0.5)))));
    }

    if (_dashboard == null) return const SizedBox.shrink();
    final d = _dashboard!;

    // 이벤트 날짜 Set 구성
    final eventDates = <String>{};
    for (final e in [...d.todayEvents, ...d.upcomingEvents]) {
      eventDates.add(e.date);
    }

    return Container(
      decoration: BotanicalDeco.card(_dk),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 코칭 메시지 ──
        if (d.coachingMessage.isNotEmpty) _coachingBanner(d.coachingMessage),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── 미니 월간 캘린더 ──
            GestureDetector(
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CalendarScreen())),
              child: _miniMonthCalendar(eventDates),
            ),
            const SizedBox(height: 14),
            // ── 중요 일정 ──
            if (d.todayEvents.isNotEmpty || d.upcomingEvents.isNotEmpty) ...[
              _sectionLabel('📅 중요 일정'),
              const SizedBox(height: 8),
              ...d.todayEvents.map((e) => _eventRow(e, isToday: true)),
              ...d.upcomingEvents.take(3).map((e) => _eventRow(e)),
              const SizedBox(height: 12),
            ],

            // ── 메모 ──
            if (d.memos.isNotEmpty) ...[
              _sectionLabel('📝 메모'),
              const SizedBox(height: 8),
              ...d.memos.take(3).map(_memoChip),
            ],

            // ── 메모 추가 ──
            if (widget.onAddMemo != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: widget.onAddMemo,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: BotanicalColors.primary.withOpacity(_dk ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BotanicalColors.primary.withOpacity(0.1))),
                  child: Center(child: Text('+ 메모 추가',
                    style: BotanicalTypo.label(size: 12, weight: FontWeight.w600,
                      color: BotanicalColors.primary))),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }

  Widget _coachingBanner(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _dk
            ? [BotanicalColors.primary.withOpacity(0.15), BotanicalColors.gold.withOpacity(0.08)]
            : [BotanicalColors.primarySurface, BotanicalColors.goldSurface])),
      child: Text(msg, style: BotanicalTypo.body(
        size: 13, weight: FontWeight.w500, color: _textMain)),
    );
  }

  /// 미니 월간 캘린더 그리드
  Widget _miniMonthCalendar(Set<String> eventDates) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 일=0, 월=1...
    final todayDay = now.day;
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // ★ 공휴일 날짜 Set 구성
    final holidayDates = <String>{};
    for (final e in [...(_dashboard?.todayEvents ?? []), ...(_dashboard?.upcomingEvents ?? [])]) {
      if (e.importance == EventImportance.high && e.type == EventType.personal) {
        holidayDates.add(e.date);
      }
    }

    final weekLabels = ['일', '월', '화', '수', '목', '금', '토'];

    return Column(children: [
      // 월 헤더
      Row(children: [
        Text('${month}월 $year', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: _textMain)),
        const Spacer(),
        // 전체 보기 힌트
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('전체 보기', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: BotanicalColors.primary)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: BotanicalColors.primary),
        ]),
      ]),
      const SizedBox(height: 10),
      // 요일 헤더
      Row(children: weekLabels.map((w) => Expanded(
        child: Center(child: Text(w, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: w == '일' ? const Color(0xFFEF4444).withOpacity(0.7)
               : w == '토' ? const Color(0xFF3B82F6).withOpacity(0.7)
               : _textMuted))))).toList()),
      const SizedBox(height: 4),
      // 날짜 그리드
      ...List.generate(6, (week) {
        return Row(children: List.generate(7, (dow) {
          final dayIdx = week * 7 + dow - startWeekday + 1;
          if (dayIdx < 1 || dayIdx > daysInMonth) {
            return const Expanded(child: SizedBox(height: 30));
          }
          final dateStr = '$year-${month.toString().padLeft(2, '0')}-${dayIdx.toString().padLeft(2, '0')}';
          final isToday = dayIdx == todayDay;
          final hasEvent = eventDates.contains(dateStr);
          final isPast = dayIdx < todayDay;
          final isHoliday = holidayDates.contains(dateStr); // ★
          final isSunday = dow == 0;
          final isSaturday = dow == 6;

          return Expanded(child: Container(
            height: 30,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isToday
                ? BotanicalColors.primary.withOpacity(_dk ? 0.2 : 0.12)
                : null,
              borderRadius: BorderRadius.circular(6)),
            child: Stack(alignment: Alignment.center, children: [
              Text('$dayIdx', style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isToday ? BotanicalColors.primary
                     : (isHoliday || isSunday) ? const Color(0xFFEF4444).withOpacity(isPast ? 0.35 : 0.7)
                     : isSaturday ? const Color(0xFF3B82F6).withOpacity(isPast ? 0.35 : 0.7)
                     : isPast ? _textMuted.withOpacity(0.4)
                     : _textMain)),
              if (hasEvent)
                Positioned(bottom: 2, child: Container(
                  width: 4, height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withOpacity(0.7)))),
            ]),
          ));
        }));
      }),
    ]);
  }

  Widget _sectionLabel(String label) {
    return Text(label, style: BotanicalTypo.label(
      size: 11, weight: FontWeight.w700, letterSpacing: 1, color: _textMuted));
  }

  // ── 일정 행 (시험 제외 삭제 가능) ──

  Widget _eventRow(CalendarEvent event, {bool isToday = false}) {
    final Color importColor;
    switch (event.importance) {
      case EventImportance.critical:
        importColor = BotanicalColors.error;
        break;
      case EventImportance.high:
        importColor = BotanicalColors.gold;
        break;
      default:
        importColor = BotanicalColors.primary;
    }

    final canDelete = event.type != EventType.exam;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: importColor.withOpacity(_dk ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(event.emoji, style: const TextStyle(fontSize: 15))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.title, style: BotanicalTypo.label(
            size: 12, weight: FontWeight.w600, color: _textMain),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          if (event.details != null)
            Text(event.details!, style: BotanicalTypo.label(
              size: 10, color: _textMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        if (event.dDay != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: importColor.withOpacity(_dk ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8)),
            child: Text(
              event.dDay == 0 ? 'TODAY' : 'D-${event.dDay}',
              style: BotanicalTypo.label(
                size: 10, weight: FontWeight.w800, color: importColor)),
          ),
        if (canDelete) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _confirmHideEvent(event),
            child: Icon(Icons.close_rounded, size: 16,
              color: _textMuted.withOpacity(0.5))),
        ],
      ]),
    );
  }

  Future<void> _confirmHideEvent(CalendarEvent event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정 숨기기'),
        content: Text('"${event.title}"\n이 일정을 숨길까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('숨기기')),
        ],
      ),
    );

    if (confirm == true) {
      if (event.type == EventType.personal) {
        await _cal.deleteLocalEvent(event.title);
      } else {
        await _cal.hideEvent(event.title);
      }
      _cal.invalidate();
      await _load();
    }
  }

  // ── 메모 (← 스와이프 삭제) ──

  Widget _memoChip(String memo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: Key('memo_$memo'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: BotanicalColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.delete_outline_rounded,
            size: 18, color: BotanicalColors.error)),
        onDismissed: (_) async {
          final cleanMemo = memo.startsWith('📌 ') ? memo.substring(3) : memo;
          if (memo.startsWith('📌 ')) {
            await _cal.deletePinnedMemo(cleanMemo);
          } else {
            await _cal.deleteMemo(memo);
          }
          _cal.invalidate();
          _load();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight,
              width: 0.5)),
          child: Row(children: [
            Expanded(child: Text(memo, style: BotanicalTypo.body(size: 12, color: _textSub),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Icon(Icons.swipe_left_rounded, size: 12,
              color: _textMuted.withOpacity(0.3)),
          ]),
        ),
      ),
    );
  }
}