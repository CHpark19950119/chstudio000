import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';

// ══════════════════════════════════════════
//  GPS 동선 위젯 (기록 탭용)
//  세로 타임라인 + 프로그레스 바 스타일
// ══════════════════════════════════════════

class GpsTimelineWidget extends StatefulWidget {
  final bool dk;
  final Color textMain, textMuted, textSub, border;

  const GpsTimelineWidget({
    super.key,
    required this.dk, required this.textMain, required this.textMuted,
    required this.textSub, required this.border,
  });

  @override
  State<GpsTimelineWidget> createState() => _GpsTimelineWidgetState();
}

class _GpsTimelineWidgetState extends State<GpsTimelineWidget>
    with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  List<BehaviorTimelineEntry> _timeline = [];
  bool _loading = true;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
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
    _safeSetState(() => _loading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final timeline = await LocationService().getTimelineByDate(dateStr);
      _safeSetState(() { _timeline = timeline; _loading = false; });
      _animCtrl.forward(from: 0);
    } catch (_) {
      _safeSetState(() { _timeline = []; _loading = false; });
    }
  }

  void _changeDate(int delta) {
    _selectedDate = _selectedDate.add(Duration(days: delta));
    _loadData();
  }

  String _fmtDur(int min) {
    final h = min ~/ 60; final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _fmtTime(String t) {
    if (t.contains('T')) {
      try { return DateFormat('HH:mm').format(DateTime.parse(t)); } catch (_) {}
    }
    if (t.length >= 5) return t.substring(0, 5);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final dk = widget.dk;
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) ==
      DateFormat('yyyy-MM-dd').format(_selectedDate);
    final wd = ['월','화','수','목','금','토','일'][_selectedDate.weekday - 1];

    final totalMin = _timeline.fold<int>(0, (s, t) => s + t.durationMinutes);
    final stayMin = _timeline.where((t) => t.type == 'stay')
      .fold<int>(0, (s, t) => s + t.durationMinutes);
    final moveMin = totalMin - stayMin;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 날짜 네비게이션
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: dk ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.border.withOpacity(0.2))),
        child: Row(children: [
          GestureDetector(
            onTap: () => _changeDate(-1),
            child: Icon(Icons.chevron_left_rounded, size: 20, color: widget.textSub)),
          Expanded(child: Center(child: Text(
            '${_selectedDate.month}월 ${_selectedDate.day}일 ($wd)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: widget.textMain)))),
          GestureDetector(
            onTap: isToday ? null : () => _changeDate(1),
            child: Icon(Icons.chevron_right_rounded, size: 20,
              color: isToday ? Colors.transparent : widget.textSub)),
        ]),
      ),
      const SizedBox(height: 10),

      if (_loading)
        const Center(child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_timeline.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: dk ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text('동선 기록 없음', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: widget.textMuted.withOpacity(0.5)))),
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dk ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.border.withOpacity(0.15))),
          child: Column(children: [
            // ── 상단 요약 ──
            Row(children: [
              Icon(Icons.route_rounded, size: 14,
                color: const Color(0xFF3B8A6B).withOpacity(0.7)),
              const SizedBox(width: 6),
              Text('동선 ${_timeline.length}건', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: widget.textMuted)),
              const Spacer(),
              _chip('📍', _fmtDur(stayMin), const Color(0xFF6366F1)),
              const SizedBox(width: 6),
              _chip('🚶', _fmtDur(moveMin), const Color(0xFF3B8A6B)),
            ]),
            const SizedBox(height: 14),

            // ── 가로 비율 바 ──
            if (totalMin > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(height: 8, child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (_, __) => Row(
                    children: _timeline.map((t) {
                      final ratio = t.durationMinutes / totalMin;
                      final isStay = t.type == 'stay';
                      return Expanded(
                        flex: (ratio * 1000).round().clamp(1, 1000),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: BoxDecoration(
                            color: (isStay
                              ? const Color(0xFF6366F1)
                              : const Color(0xFF3B8A6B))
                              .withOpacity(0.7 * _animCtrl.value),
                            borderRadius: BorderRadius.circular(4))),
                      );
                    }).toList()),
                ))),
              const SizedBox(height: 14),
            ],

            // ── 세로 타임라인 ──
            ...List.generate(_timeline.length, (i) {
              final t = _timeline[i];
              final isStay = t.type == 'stay';
              final isLast = i == _timeline.length - 1;
              final color = isStay
                ? const Color(0xFF6366F1) : const Color(0xFF3B8A6B);

              return AnimatedBuilder(
                animation: CurvedAnimation(
                  parent: _animCtrl,
                  curve: Interval(
                    (i / _timeline.length * 0.4).clamp(0.0, 1.0),
                    ((i + 1) / _timeline.length * 0.4 + 0.6).clamp(0.0, 1.0),
                    curve: Curves.easeOutCubic)),
                builder: (_, child) => Opacity(
                  opacity: _animCtrl.value.clamp(0.0, 1.0),
                  child: child),
                child: IntrinsicHeight(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시간 스탬프
                    SizedBox(width: 42, child: Text(
                      _fmtTime(t.startTime),
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: widget.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()]))),
                    const SizedBox(width: 6),
                    // 세로 타임라인 도트 + 라인
                    SizedBox(width: 20, child: Column(children: [
                      Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.15),
                          border: Border.all(color: color, width: 2))),
                      if (!isLast)
                        Expanded(child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color.withOpacity(0.3),
                                color.withOpacity(0.08)])))),
                    ])),
                    const SizedBox(width: 8),
                    // 내용
                    Expanded(child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                      child: Row(children: [
                        Text('${t.emoji ?? ""} ',
                          style: const TextStyle(fontSize: 14)),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.label, style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: widget.textMain),
                              overflow: TextOverflow.ellipsis),
                            Text(
                              '${_fmtTime(t.startTime)} ~ ${_fmtTime(t.endTime)}',
                              style: TextStyle(fontSize: 10,
                                color: widget.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()])),
                          ])),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(_fmtDur(t.durationMinutes),
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800,
                              color: color,
                              fontFeatures: const [
                                FontFeature.tabularFigures()]))),
                      ])),
                    ),
                  ],
                )),
              );
            }),
          ]),
        ),
    ]);
  }

  Widget _chip(String emoji, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(widget.dk ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 9)),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: color,
          fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}