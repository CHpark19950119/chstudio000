import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../theme/botanical_theme.dart';

/// 3순위: 학습 진행도 화면
/// Firebase progressGoals 스키마 호환 (웹앱 ↔ Flutter)
/// v8.12: UL-4 양방향 실시간 동기화 + UL-5 새로고침
/// v9: Glassmorphism design remodel
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with TickerProviderStateMixin {
  final _fb = FirebaseService();
  List<ProgressGoal> _goals = [];
  bool _loading = true;
  String _typeFilter = 'all'; // all, lecture, textbook
  final Set<String> _expandedGroups = {}; // 펼쳐진 그룹 ID 추적
  bool _initialGroupsSet = false;
  StreamSubscription? _progressSub; // UL-4: 실시간 스트림
  int _retryDelay = 5; // 지수 백오프 (초)
  bool _completedExpanded = false; // 완료 섹션 접기/펼치기

  // 과목별 디자인 설정
  static const _subjectConfig = {
    '자료해석': _SubjCfg(0xFF34547A, 0xFFEBF1F6, '📊', 'DATA'),
    '언어논리': _SubjCfg(0xFF8B575C, 0xFFF6EBEB, '📝', 'LANG'),
    '상황판단': _SubjCfg(0xFF2D5A4C, 0xFFE7EFEA, '🧩', 'SITU'),
    '헌법': _SubjCfg(0xFF10B981, 0xFFECFDF5, '⚖️', 'LAW'),
    '영어': _SubjCfg(0xFF0EA5E9, 0xFFF0F9FF, '🌐', 'ENG'),
  };

  _SubjCfg _cfgFor(String subj) =>
      _subjectConfig[subj] ?? const _SubjCfg(0xFF6366F1, 0xFFF0F0FF, '📚', 'ETC');

  // ─── Theme-aware colors ───
  Color _indigo(bool isDark) => isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  Color _emerald(bool isDark) => isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color _amber(bool isDark) => isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

  @override
  void initState() {
    super.initState();
    _loadGoals();
    _startRealtimeSync(); // UL-4
  }

  @override
  void dispose() {
    _progressSub?.cancel(); // UL-4
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

  /// UL-4: 실시간 동기화 — 웹앱에서 수정하면 자동 반영
  void _startRealtimeSync() {
    _progressSub?.cancel();
    _progressSub = _fb.watchProgressGoals().listen((goals) {
      _retryDelay = 5; // 성공 시 리셋
      _safeSetState(() {
        _goals = goals;
        _loading = false;
      });
    }, onError: (e) {
      debugPrint('[Progress] Realtime sync error: $e — retry ${_retryDelay}s');
      if (mounted) {
        Future.delayed(Duration(seconds: _retryDelay), () {
          _retryDelay = (_retryDelay * 2).clamp(5, 60);
          if (mounted) _startRealtimeSync();
        });
      }
    });
  }

  Future<void> _loadGoals() async {
    _safeSetState(() => _loading = true);
    try {
      _goals = await _fb.getProgressGoals();
    } catch (e) {
      debugPrint('[Progress] Load error: $e');
    }
    _safeSetState(() => _loading = false);
  }

  List<ProgressGoal> get _activeGoals => _goals.where((g) => !g.completed).toList();
  List<ProgressGoal> get _completedGoals => _goals.where((g) => g.completed).toList();

  List<ProgressGoal> get _filteredActive {
    if (_typeFilter == 'lecture') {
      return _activeGoals.where((g) => g.goalType == 'lecture').toList();
    }
    if (_typeFilter == 'textbook') {
      return _activeGoals.where((g) => g.goalType == 'textbook').toList();
    }
    return _activeGoals;
  }

  /// 다음 강의: 미완료 lecture 중 진행률 가장 높은
  ProgressGoal? get _nextLectureGoal {
    final lectures = _activeGoals.where((g) => g.goalType == 'lecture').toList();
    if (lectures.isEmpty) return null;
    lectures.sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    return lectures.firstWhere((g) => g.progressPercent < 100, orElse: () => lectures.first);
  }

  /// #4: 전체 강의 목록 (미완료 우선, 진행률 높은 순)
  List<ProgressGoal> get _allLectureGoals {
    final lectures = _activeGoals.where((g) => g.goalType == 'lecture').toList();
    lectures.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return b.progressPercent.compareTo(a.progressPercent);
    });
    return lectures;
  }

  // ═══════════════════════════════════════════════════════════
  //  Glassmorphism helpers
  // ═══════════════════════════════════════════════════════════

  Widget _glass({
    required Widget child,
    double blur = 10,
    double opacity = 0.06,
    double radius = 16,
    EdgeInsets? padding,
    Border? border,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(opacity)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(radius),
            border: border ??
                Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.white.withOpacity(0.3),
                ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _overallDonut(double avgPct, bool isDark) {
    final color = _indigo(isDark);
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: avgPct / 100,
          strokeWidth: 5,
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
        Text('${avgPct.round()}%',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  Widget _gradientProgressBar(double pct, Color color, {double height = 8}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (pct / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [color.withOpacity(0.6), color]),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  전체 강의 리스트
  // ═══════════════════════════════════════════════════════════

  Widget _buildAllLecturesList(bool isDark) {
    final lectures = _allLectureGoals;
    final nextId = _nextLectureGoal?.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _glass(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🎧', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text('전체 강의 (${lectures.length})',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 10),
          ...lectures.map((goal) {
            final isNext = goal.id == nextId;
            final cfg = _cfgFor(goal.subject);
            final color = Color(cfg.color);
            final unitLabel =
                goal.unitName.isNotEmpty ? goal.unitName : '강';
            final next = goal.currentUnit + 1;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: isNext
                    ? LinearGradient(colors: [
                        color.withOpacity(isDark ? 0.15 : 0.08),
                        color.withOpacity(isDark ? 0.05 : 0.02)
                      ])
                    : null,
                color: isNext
                    ? null
                    : (isDark
                        ? Colors.white.withOpacity(0.02)
                        : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(12),
                border:
                    isNext ? Border.all(color: color.withOpacity(0.3)) : null,
              ),
              child: Row(children: [
                SizedBox(
                    width: 32,
                    height: 32,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                          value: goal.progressPercent / 100,
                          strokeWidth: 2.5,
                          backgroundColor: color.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation(color)),
                      Text('${goal.progressPercent.round()}%',
                          style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              color: color)),
                    ])),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        if (isNext)
                          Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4)),
                              child: Text('NEXT',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: color))),
                        Expanded(
                            child: Text(goal.title,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                      ]),
                      Text(
                          '${goal.subject} · ${next}$unitLabel부터 · ${goal.currentUnit}/${goal.totalUnits}$unitLabel',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade500)),
                    ])),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _buildNextLectureBanner(bool isDark) {
    final goal = _nextLectureGoal!;
    final cfg = _cfgFor(goal.subject);
    final color = Color(cfg.color);
    final unitLabel = goal.unitName.isNotEmpty ? goal.unitName : '강';
    final next = goal.currentUnit + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('🎧', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('다음 강의',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(goal.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : const Color(0xFF1E293B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${next}$unitLabel부터 · ${goal.currentUnit}/${goal.totalUnits}$unitLabel 완료',
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ])),
          // 미니 진행률
          SizedBox(
              width: 36,
              height: 36,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                    value: goal.progressPercent / 100,
                    strokeWidth: 2.5,
                    backgroundColor: color.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation(color)),
                Text('${goal.progressPercent.round()}%',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation(_indigo(isDark))))
          : RefreshIndicator(
              onRefresh: _loadGoals,
              color: _indigo(isDark),
              child: CustomScrollView(
                slivers: [
                  // ─── 헤더 ───
                  SliverToBoxAdapter(child: _buildHeader(isDark)),
                  // ─── 전체 강의 리스트 ───
                  if (_allLectureGoals.isNotEmpty)
                    SliverToBoxAdapter(
                        child: _buildAllLecturesList(isDark)),
                  // ─── 과목별 요약 ───
                  if (_activeGoals.isNotEmpty)
                    SliverToBoxAdapter(
                        child: _buildSubjectSummary(isDark)),
                  // ─── 타입 필터 ───
                  SliverToBoxAdapter(child: _buildTypeFilter(isDark)),
                  // ─── 목표 목록 (그룹핑) ───
                  if (_filteredActive.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState(isDark)),
                  if (_filteredActive.isNotEmpty)
                    ..._buildGroupedGoals(isDark),
                  // ─── 완료 섹션 ───
                  if (_completedGoals.isNotEmpty)
                    SliverToBoxAdapter(
                        child: _buildCompletedSection(isDark)),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
      floatingActionButton: _buildGlassFAB(isDark),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Glassmorphism FAB
  // ═══════════════════════════════════════════════════════════

  Widget _buildGlassFAB(bool isDark) {
    return GestureDetector(
      onTap: _showAddGoalModal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _indigo(isDark),
                  _indigo(isDark).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: _indigo(isDark).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Text('목표 추가',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  헤더 — large title + overall donut + glassmorphism summary
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(bool isDark) {
    final totalActive = _activeGoals.length;
    final avgPct = totalActive > 0
        ? (_activeGoals.fold<double>(0, (s, g) => s + g.progressPercent) /
            totalActive)
        : 0.0;
    final totalCompleted = _completedGoals.length;
    final lecCount =
        _activeGoals.where((g) => g.goalType == 'lecture').length;
    final bookCount =
        _activeGoals.where((g) => g.goalType == 'textbook').length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with donut
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('학습 진행도',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                        )),
                    const SizedBox(height: 2),
                    Text(
                        '진행 $totalActive개 · 완료 $totalCompleted개',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              // Refresh button
              GestureDetector(
                onTap: _loadGoals,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.refresh_rounded,
                      size: 18,
                      color: isDark
                          ? Colors.white54
                          : Colors.grey.shade500),
                ),
              ),
              // Overall donut
              if (totalActive > 0) _overallDonut(avgPct, isDark),
            ],
          ),
          const SizedBox(height: 14),
          // Glassmorphism summary card
          if (totalActive > 0)
            _glass(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem(
                      '평균 진행률', '${avgPct.round()}%', _indigo(isDark)),
                  Container(
                      width: 1,
                      height: 28,
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.grey.shade200),
                  _summaryItem(
                      '강의', '$lecCount개', const Color(0xFF7C3AED)),
                  Container(
                      width: 1,
                      height: 28,
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.grey.shade200),
                  _summaryItem(
                      '교재', '$bookCount개', _emerald(isDark)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white54 : Colors.grey.shade500)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════
  //  과목별 요약 카드 — glassmorphism horizontal scroll
  // ═══════════════════════════════════════════════════════════

  Widget _buildSubjectSummary(bool isDark) {
    final subjStats = <String, _SubjStat>{};
    for (final g in _activeGoals) {
      final s = g.subject;
      subjStats.putIfAbsent(s, () => _SubjStat());
      subjStats[s]!.count++;
      subjStats[s]!.pctSum += g.progressPercent;
      if (g.isOverdue) subjStats[s]!.delayed++;
    }
    for (final g in _completedGoals) {
      subjStats.putIfAbsent(g.subject, () => _SubjStat());
      subjStats[g.subject]!.completed++;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: subjStats.entries.map((e) {
            final cfg = _cfgFor(e.key);
            final color = Color(cfg.color);
            final avgPct = e.value.count > 0
                ? (e.value.pctSum / e.value.count).round()
                : 0;
            return Container(
              width: 140,
              margin: const EdgeInsets.only(right: 10, bottom: 12),
              child: _glass(
                padding: const EdgeInsets.all(14),
                border: Border(
                  left: BorderSide(color: color, width: 3),
                  top: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.3)),
                  right: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.3)),
                  bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(cfg.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(e.key,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color)),
                      if (e.value.delayed > 0) ...[
                        const SizedBox(width: 4),
                        Text('⚠${e.value.delayed}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade600)),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    Text('$avgPct%',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Text(
                        '${e.value.count}개 진행 · ${e.value.completed}개 완료',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    _gradientProgressBar(avgPct.toDouble(), color, height: 4),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  타입 필터
  // ═══════════════════════════════════════════════════════════

  Widget _buildTypeFilter(bool isDark) {
    final lecCount =
        _activeGoals.where((g) => g.goalType == 'lecture').length;
    final bookCount =
        _activeGoals.where((g) => g.goalType == 'textbook').length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _filterChip('전체 ${_activeGoals.length}', 'all',
              _indigo(isDark), isDark),
          const SizedBox(width: 8),
          _filterChip('🎬 강의 $lecCount', 'lecture',
              const Color(0xFF7C3AED), isDark),
          const SizedBox(width: 8),
          _filterChip('📖 교재 $bookCount', 'textbook',
              _emerald(isDark), isDark),
        ],
      ),
    );
  }

  Widget _filterChip(
      String label, String type, Color color, bool isDark) {
    final selected = _typeFilter == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => _safeSetState(() => _typeFilter = type),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: selected ? 8 : 0, sigmaY: selected ? 8 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? color
                    : (isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white.withOpacity(0.7)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected
                        ? color
                        : (isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.grey.shade300),
                    width: 1),
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : Colors.grey.shade600)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  그룹핑된 목표 리스트
  // ═══════════════════════════════════════════════════════════

  List<Widget> _buildGroupedGoals(bool isDark) {
    // 그룹별 분류
    final Map<String?, List<ProgressGoal>> groups = {};
    for (final g in _filteredActive) {
      final key = g.groupId;
      groups.putIfAbsent(key, () => []).add(g);
    }

    // 그룹 정렬: 그룹 있는 것 먼저, 없는 것(null) 마지막
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });

    final List<Widget> slivers = [];

    for (final key in sortedKeys) {
      final goalsInGroup = groups[key]!;
      final hasGroup = key != null;
      final groupName =
          hasGroup ? (goalsInGroup.first.groupName ?? '그룹') : null;
      final isExpanded =
          !hasGroup || _expandedGroups.contains(key);

      // 그룹 헤더 (그룹이 있는 경우만)
      if (hasGroup) {
        final groupProgress = _groupProgress(goalsInGroup);
        slivers.add(SliverToBoxAdapter(
          child: GestureDetector(
            onTap: () => _safeSetState(() {
              if (_expandedGroups.contains(key)) {
                _expandedGroups.remove(key);
              } else {
                _expandedGroups.add(key!);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: _glass(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: _indigo(isDark).withOpacity(
                            isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Center(
                        child: Text('📁',
                            style: TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(groupName!,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B))),
                      const SizedBox(height: 2),
                      Text(
                          '${goalsInGroup.length}개 · ${groupProgress.round()}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500)),
                    ],
                  )),
                  // 미니 프로그레스
                  SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                                value: groupProgress / 100,
                                strokeWidth: 3,
                                backgroundColor:
                                    _indigo(isDark).withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation(
                                    _indigo(isDark))),
                            Text('${groupProgress.round()}%',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white70
                                        : _indigo(isDark))),
                          ])),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: Colors.grey.shade400)),
                ]),
              ),
            ),
          ),
        ));
      }

      // 그룹 내 목표들
      if (isExpanded) {
        slivers.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildGoalCard(goalsInGroup[i], isDark),
            childCount: goalsInGroup.length,
          ),
        ));
      }
    }

    // 초기: 새 그룹 자동 펼침 (이미 펼침 설정된 건 유지)
    for (final k in groups.keys) {
      if (k != null &&
          !_expandedGroups.contains(k) &&
          !_initialGroupsSet) {
        _expandedGroups.add(k);
      }
    }
    if (groups.keys.any((k) => k != null)) _initialGroupsSet = true;

    return slivers;
  }

  double _groupProgress(List<ProgressGoal> goals) {
    if (goals.isEmpty) return 0;
    final total =
        goals.fold<double>(0, (s, g) => s + g.progressPercent);
    return total / goals.length;
  }

  // ═══════════════════════════════════════════════════════════
  //  개별 목표 카드 — glassmorphism + color stripe + gradient bar
  // ═══════════════════════════════════════════════════════════

  Widget _buildGoalCard(ProgressGoal goal, bool isDark) {
    final cfg = _cfgFor(goal.subject);
    final pct = goal.progressPercent.round();
    final isTextbook = goal.goalType == 'textbook';
    final unitLabel = isTextbook
        ? 'p'
        : (goal.unitName.isNotEmpty ? goal.unitName : '강');
    final color = Color(cfg.color);
    final hasGroup = goal.groupId != null;
    final isComplete = pct >= 100;

    return Container(
      margin: EdgeInsets.fromLTRB(hasGroup ? 28 : 16, 3, 16, 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(14),
              border: isComplete
                  ? Border.all(
                      color: const Color(0xFFD97706), width: 2)
                  : Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left color stripe
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  // Main content
                  Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(children: [
                      // 상단: 과목 태그 + 제목 + 메뉴
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius:
                                  BorderRadius.circular(4)),
                          child: Text('${cfg.emoji} ${cfg.tag}',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: color)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(goal.title,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        if (isComplete)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 2),
                            child: Icon(Icons.auto_awesome,
                                size: 16,
                                color: _amber(isDark)),
                          ),
                        if (goal.isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius:
                                    BorderRadius.circular(3)),
                            child: Text('🔥+${goal.overdueDays}일',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        Colors.red.shade600)),
                          ),
                        _goalMenu(goal),
                      ]),
                      const SizedBox(height: 8),
                      // 진행 바 + 퍼센트
                      Row(children: [
                        Expanded(
                            child: _gradientProgressBar(
                                pct.toDouble(), color,
                                height: 7)),
                        const SizedBox(width: 10),
                        Text('$pct%',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: color)),
                      ]),
                      const SizedBox(height: 4),
                      // 하단: 단위 + 날짜 + 액션
                      Row(children: [
                        Text(
                            '${goal.currentUnit}/${goal.totalUnits}$unitLabel',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600)),
                        if (goal.startDate != null &&
                            goal.endDate != null) ...[
                          const SizedBox(width: 8),
                          Text(
                              '${goal.startDate!.substring(5)}~${goal.endDate!.substring(5)}',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade500)),
                        ],
                        const Spacer(),
                        _actionBtn(
                            '📝', color, () => _showLogModal(goal)),
                        const SizedBox(width: 4),
                        _actionBtn('🔧', Colors.grey.shade600,
                            () => _showDirectEditModal(goal)),
                        if (goal.totalStudyMinutes > 0) ...[
                          const SizedBox(width: 6),
                          Text('⏱${goal.totalStudyFormatted}',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      color.withOpacity(0.7))),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      ),
    );
  }

  Widget _goalMenu(ProgressGoal goal) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          color: Colors.grey.shade400, size: 20),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('✏️ 목표 수정')),
        PopupMenuItem(
            value: 'group',
            child: Text('📁 그룹 ${goal.groupName ?? '지정'}')),
        const PopupMenuItem(
            value: 'complete', child: Text('✅ 완료 처리')),
        const PopupMenuItem(
            value: 'delete',
            child:
                Text('🗑️ 삭제', style: TextStyle(color: Colors.red))),
      ],
      onSelected: (v) async {
        if (v == 'edit') _showEditGoalModal(goal);
        if (v == 'group') _showGroupAssignModal(goal);
        if (v == 'complete') _completeGoal(goal);
        if (v == 'delete') _deleteGoal(goal);
      },
    );
  }

  /// 기존 목표에 그룹 지정/변경
  void _showGroupAssignModal(ProgressGoal goal) {
    final existingGroups = <String, String>{};
    for (final g in _goals) {
      if (g.groupId != null && g.groupName != null) {
        existingGroups[g.groupId!] = g.groupName!;
      }
    }
    String? selectedId = goal.groupId;
    final newGroupCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
              MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('📁 그룹 지정',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(goal.title,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _groupChip('없음', selectedId == null,
                  () => setLocal(() => selectedId = null)),
              ...existingGroups.entries.map((e) => _groupChip(
                  e.value,
                  selectedId == e.key,
                  () =>
                      setLocal(() => selectedId = e.key))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                controller: newGroupCtrl,
                decoration: InputDecoration(
                  hintText: '새 그룹명...',
                  hintStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                style: const TextStyle(fontSize: 13),
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final name = newGroupCtrl.text.trim();
                  if (name.isEmpty) return;
                  final id =
                      'grp_${DateTime.now().millisecondsSinceEpoch}';
                  existingGroups[id] = name;
                  setLocal(() {
                    selectedId = id;
                    newGroupCtrl.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF6366F1)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('+ 추가',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6366F1))),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    goal.groupId = selectedId;
                    goal.groupName = selectedId != null
                        ? existingGroups[selectedId]
                        : null;
                    await _fb.saveProgressGoals(_goals);
                    Navigator.pop(ctx);
                    _safeSetState(() {});
                    _snack('📁 그룹 변경 완료');
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12))),
                  child: const Text('저장',
                      style:
                          TextStyle(fontWeight: FontWeight.w700)),
                )),
          ]),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _glass(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('📈', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text('진행 중인 학습 목표가 없습니다',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('교재나 강의를 등록하고 진행도를 추적해보세요',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  완료 섹션 — collapsible with AnimatedSize
  // ═══════════════════════════════════════════════════════════

  Widget _buildCompletedSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: _glass(
        padding: const EdgeInsets.all(16),
        border: Border(
          top: BorderSide(color: _emerald(isDark), width: 3),
          left: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.3)),
          right: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.3)),
          bottom: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(
                  () => _completedExpanded = !_completedExpanded),
              child: Row(children: [
                Text('✅ 완료된 학습',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1E293B))),
                const SizedBox(width: 8),
                Text('${_completedGoals.length}개',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                AnimatedRotation(
                  turns: _completedExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: Colors.grey.shade400),
                ),
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _completedExpanded
                  ? Column(
                      children: [
                        const SizedBox(height: 12),
                        ..._completedGoals.map((g) {
                          final cfg = _cfgFor(g.subject);
                          final rounds =
                              g.completionHistory.length;
                          final gColor = Color(cfg.color);
                          return Container(
                            margin:
                                const EdgeInsets.only(bottom: 8),
                            padding:
                                const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? gColor.withOpacity(0.08)
                                  : Color(cfg.light),
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: gColor
                                      .withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Text(cfg.emoji,
                                    style: const TextStyle(
                                        fontSize: 20)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(g.title,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight
                                                      .w700,
                                              color: isDark
                                                  ? Colors
                                                      .white
                                                  : const Color(
                                                      0xFF1E293B))),
                                      Text(
                                        '${g.goalType == "textbook" ? "교재" : "강의"} · ${g.totalUnits}${g.goalType == "textbook" ? "p" : g.unitName}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey
                                                .shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                          horizontal: 8,
                                          vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.green.shade50,
                                    borderRadius:
                                        BorderRadius.circular(
                                            6),
                                  ),
                                  child: Text(
                                      '✓ ${rounds > 0 ? rounds : 1}회',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.w700,
                                          color: Colors.green
                                              .shade700)),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () =>
                                      _restartGoal(g),
                                  child: Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 8,
                                        vertical: 4),
                                    decoration: BoxDecoration(
                                      color: gColor
                                          .withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius
                                              .circular(6),
                                    ),
                                    child: const Text('🔄',
                                        style: TextStyle(
                                            fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  새 목표 추가
  // ═══════════════════════════════════════════════════════════

  void _showAddGoalModal() {
    String subject = '자료해석';
    String goalType = 'lecture';
    String? selectedGroupId;
    String? selectedGroupName;
    final titleCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    final startPageCtrl = TextEditingController(text: '0');
    final endPageCtrl = TextEditingController();
    final startDateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final endDateCtrl = TextEditingController();
    final newGroupCtrl = TextEditingController();

    // 기존 그룹 목록 추출
    final existingGroups = <String, String>{}; // id -> name
    for (final g in _goals) {
      if (g.groupId != null && g.groupName != null) {
        existingGroups[g.groupId!] = g.groupName!;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius:
                                BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('➕ 새 학습 목표',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  // 과목 선택
                  DropdownButtonFormField<String>(
                    value: subject,
                    decoration: _inputDeco('과목'),
                    items: _subjectConfig.keys
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                                '${_subjectConfig[s]!.emoji} $s')))
                        .toList(),
                    onChanged: (v) => setModalState(
                        () => subject = v ?? subject),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: titleCtrl,
                      decoration: _inputDeco('교재/강의명')),
                  const SizedBox(height: 12),
                  // ── 그룹 선택 ──
                  Row(children: [
                    Text('📁 그룹',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                          _groupChip(
                              '없음',
                              selectedGroupId == null,
                              () => setModalState(() {
                                    selectedGroupId = null;
                                    selectedGroupName = null;
                                  })),
                          ...existingGroups.entries.map((e) =>
                              _groupChip(
                                  e.value,
                                  selectedGroupId == e.key,
                                  () => setModalState(() {
                                        selectedGroupId =
                                            e.key;
                                        selectedGroupName =
                                            e.value;
                                      }))),
                        ])),
                  ]),
                  const SizedBox(height: 8),
                  // 새 그룹 생성
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: newGroupCtrl,
                      decoration: InputDecoration(
                        hintText: '새 그룹명...',
                        hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    )),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final name =
                            newGroupCtrl.text.trim();
                        if (name.isEmpty) return;
                        final id =
                            'grp_${DateTime.now().millisecondsSinceEpoch}';
                        existingGroups[id] = name;
                        setModalState(() {
                          selectedGroupId = id;
                          selectedGroupName = name;
                          newGroupCtrl.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(10)),
                        child: const Text('+ 추가',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6366F1))),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // 유형 토글
                  Row(children: [
                    _typeToggle(
                        '🎬 강의',
                        goalType == 'lecture',
                        () => setModalState(
                            () => goalType = 'lecture')),
                    const SizedBox(width: 8),
                    _typeToggle(
                        '📖 교재',
                        goalType == 'textbook',
                        () => setModalState(
                            () => goalType = 'textbook')),
                  ]),
                  const SizedBox(height: 12),
                  if (goalType == 'lecture')
                    TextField(
                        controller: totalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco('총 강의 수'))
                  else
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: startPageCtrl,
                              keyboardType:
                                  TextInputType.number,
                              decoration:
                                  _inputDeco('시작 페이지'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: endPageCtrl,
                              keyboardType:
                                  TextInputType.number,
                              decoration:
                                  _inputDeco('종료 페이지'))),
                    ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: startDateCtrl,
                            decoration: _inputDeco('시작일'),
                            onTap: () => _pickDate(
                                ctx, startDateCtrl))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: endDateCtrl,
                            decoration: _inputDeco('종료일'),
                            onTap: () =>
                                _pickDate(ctx, endDateCtrl))),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _saveNewGoal(
                        subject: subject,
                        title: titleCtrl.text,
                        goalType: goalType,
                        totalStr: totalCtrl.text,
                        startPage: startPageCtrl.text,
                        endPage: endPageCtrl.text,
                        startDate: startDateCtrl.text,
                        endDate: endDateCtrl.text,
                        groupId: selectedGroupId,
                        groupName: selectedGroupName,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      child: const Text('📈 등록',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _groupChip(
      String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1).withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? const Color(0xFF6366F1).withOpacity(0.4)
                  : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF6366F1)
                    : Colors.grey.shade600)),
      ),
    );
  }

  Widget _typeToggle(
      String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF6366F1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : Colors.grey.shade600))),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          TextStyle(fontSize: 13, color: Colors.grey.shade500),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<void> _pickDate(
      BuildContext ctx, TextEditingController ctrl) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate:
          DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2028),
    );
    if (d != null) ctrl.text = DateFormat('yyyy-MM-dd').format(d);
  }

  Future<void> _saveNewGoal({
    required String subject,
    required String title,
    required String goalType,
    required String totalStr,
    required String startPage,
    required String endPage,
    required String startDate,
    required String endDate,
    String? groupId,
    String? groupName,
  }) async {
    if (title.trim().isEmpty) {
      _snack('교재/강의명을 입력하세요');
      return;
    }

    int totalUnits;
    int sp = 0, ep = 0;
    String unitName;

    if (goalType == 'lecture') {
      totalUnits = int.tryParse(totalStr) ?? 0;
      if (totalUnits <= 0) {
        _snack('총 강의 수를 입력하세요');
        return;
      }
      unitName = '강';
    } else {
      sp = int.tryParse(startPage) ?? 0;
      ep = int.tryParse(endPage) ?? 0;
      if (ep <= sp) {
        _snack('종료 페이지가 시작보다 커야 합니다');
        return;
      }
      totalUnits = ep - sp;
      unitName = 'p';
    }

    final goal = ProgressGoal(
      id: 'goal_${DateTime.now().millisecondsSinceEpoch}',
      subject: subject,
      title: title.trim(),
      totalUnits: totalUnits,
      unitName: unitName,
      goalType: goalType,
      startPage: sp,
      endPage: ep,
      startDate: startDate.isNotEmpty ? startDate : null,
      endDate: endDate.isNotEmpty ? endDate : null,
      groupId: groupId,
      groupName: groupName,
    );

    _goals.add(goal);
    await _fb.saveProgressGoals(_goals);
    Navigator.pop(context);
    _safeSetState(() {});
    _snack('📈 학습 목표 등록 완료!');
  }

  // ═══════════════════════════════════════════════════════════
  //  학습 기록 (로그)
  // ═══════════════════════════════════════════════════════════

  void _showLogModal(ProgressGoal goal) {
    final isTextbook = goal.goalType == 'textbook';
    final fromCtrl = TextEditingController(
        text: isTextbook
            ? '${goal.startPage + goal.currentUnit}'
            : '${goal.currentUnit}');
    final toCtrl = TextEditingController(
        text: isTextbook
            ? '${min(goal.startPage + goal.currentUnit + 10, goal.startPage + goal.totalUnits)}'
            : '${min(goal.currentUnit + 1, goal.totalUnits)}');
    final hoursCtrl = TextEditingController();
    final minsCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📝 오늘 학습 기록',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(goal.title,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: fromCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco(
                          isTextbook ? '시작 페이지' : '시작 위치'))),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  child: const Text('→',
                      style: TextStyle(fontSize: 20))),
              Expanded(
                  child: TextField(
                      controller: toCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco(
                          isTextbook ? '완료 페이지' : '종료 위치'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('시간'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: minsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('분'))),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _saveLog(goal,
                    from: int.tryParse(fromCtrl.text) ?? 0,
                    to: int.tryParse(toCtrl.text) ?? 0,
                    hours: int.tryParse(hoursCtrl.text) ?? 0,
                    mins: int.tryParse(minsCtrl.text) ?? 0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('📝 기록 저장',
                    style:
                        TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLog(ProgressGoal goal,
      {required int from,
      required int to,
      required int hours,
      required int mins}) async {
    if (to <= from) {
      _snack('종료값이 시작보다 커야 합니다');
      return;
    }
    final isTextbook = goal.goalType == 'textbook';
    final studyMin = hours * 60 + mins;

    if (isTextbook) {
      final relTo = to - goal.startPage;
      if (relTo > goal.totalUnits) {
        _snack('최대 ${goal.startPage + goal.totalUnits}p까지입니다');
        return;
      }
      goal.currentUnit = relTo;
    } else {
      if (to > goal.totalUnits) {
        _snack('최대 ${goal.totalUnits}까지입니다');
        return;
      }
      goal.currentUnit = to;
    }

    goal.dailyLogs.add(ProgressLog(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      from: from,
      to: to,
      studyMinutes: studyMin,
      loggedAt: DateTime.now().toIso8601String(),
    ));
    goal.lastLogDate =
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    final pct = goal.progressPercent.round();
    if (pct >= 100) {
      _autoComplete(goal);
    }

    await _fb.saveProgressGoals(_goals);
    Navigator.pop(context);
    _safeSetState(() {});
    _snack(pct >= 100 ? '🎉 100% 달성!' : '📈 $pct% 달성!');
  }

  // ═══════════════════════════════════════════════════════════
  //  진행도 직접 수정
  // ═══════════════════════════════════════════════════════════

  void _showDirectEditModal(ProgressGoal goal) {
    final ctrl =
        TextEditingController(text: '${goal.currentUnit}');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔧 진척도 직접 수정',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${goal.title} (0 ~ ${goal.totalUnits})',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800),
                decoration: _inputDeco('현재 진행')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final val = int.tryParse(ctrl.text) ?? 0;
                  if (val < 0 || val > goal.totalUnits) {
                    _snack('0 ~ ${goal.totalUnits} 범위입니다');
                    return;
                  }
                  goal.currentUnit = val;
                  await _fb.saveProgressGoals(_goals);
                  Navigator.pop(context);
                  _safeSetState(() {});
                  _snack(
                      '진행도 ${goal.progressPercent.round()}%로 수정');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('✅ 저장',
                    style:
                        TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  목표 수정
  // ═══════════════════════════════════════════════════════════

  void _showEditGoalModal(ProgressGoal goal) {
    String subject = goal.subject;
    final titleCtrl = TextEditingController(text: goal.title);
    final totalCtrl =
        TextEditingController(text: '${goal.totalUnits}');
    final startDateCtrl =
        TextEditingController(text: goal.startDate ?? '');
    final endDateCtrl =
        TextEditingController(text: goal.endDate ?? '');
    final currentCtrl =
        TextEditingController(text: '${goal.currentUnit}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20,
              MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✏️ 학습 목표 수정',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: subject,
                  decoration: _inputDeco('과목'),
                  items: _subjectConfig.keys
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                              '${_subjectConfig[s]!.emoji} $s')))
                      .toList(),
                  onChanged: (v) => setModalState(
                      () => subject = v ?? subject),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: titleCtrl,
                    decoration: _inputDeco('제목')),
                const SizedBox(height: 12),
                TextField(
                    controller: totalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco(
                        '총 ${goal.goalType == "textbook" ? "페이지" : "강의"} 수')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: startDateCtrl,
                          decoration: _inputDeco('시작일'),
                          onTap: () => _pickDate(
                              ctx, startDateCtrl))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: endDateCtrl,
                          decoration: _inputDeco('종료일'),
                          onTap: () =>
                              _pickDate(ctx, endDateCtrl))),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: currentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('현재 진행도')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final t = titleCtrl.text.trim();
                      final tu =
                          int.tryParse(totalCtrl.text);
                      final newCur =
                          int.tryParse(currentCtrl.text);

                      final idx = _goals.indexWhere(
                          (g) => g.id == goal.id);
                      if (idx < 0) return;

                      final m = goal.toMap();

                      // final 필드 업데이트는 map에서만
                      m['subject'] = subject;
                      if (t.isNotEmpty) m['title'] = t;

                      if (tu != null && tu > 0) {
                        m['totalUnits'] = tu;

                        // totalUnits 줄이면 currentUnit도 같이 자르기
                        final cur = (m['currentUnit']
                                    as num?)
                                ?.toInt() ??
                            0;
                        if (cur > tu) m['currentUnit'] = tu;
                      }

                      // 날짜
                      if (startDateCtrl.text.isNotEmpty) {
                        m['startDate'] =
                            startDateCtrl.text;
                      } else {
                        m.remove('startDate');
                      }

                      if (endDateCtrl.text.isNotEmpty) {
                        m['endDate'] = endDateCtrl.text;
                      } else {
                        m.remove('endDate');
                      }

                      // currentUnit
                      if (newCur != null) {
                        final maxTu =
                            (m['totalUnits'] as num?)
                                    ?.toInt() ??
                                goal.totalUnits;
                        m['currentUnit'] =
                            newCur.clamp(0, maxTu);
                      }

                      _goals[idx] =
                          ProgressGoal.fromMap(m);

                      await _fb.saveProgressGoals(_goals);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _safeSetState(() {});
                      _snack('수정 완료');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                    child: const Text('💾 저장',
                        style: TextStyle(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  완료 / 재시작 / 삭제
  // ═══════════════════════════════════════════════════════════

  void _autoComplete(ProgressGoal goal) {
    if (goal.completed) return;
    final round = goal.completionHistory.length + 1;
    final totalMin = goal.dailyLogs
        .fold<int>(0, (s, l) => s + (l.studyMinutes ?? 0));
    goal.completionHistory.add(CompletionRecord(
      round: round,
      completedAt: DateTime.now().toIso8601String(),
      startDate: goal.startDate,
      endDate: goal.endDate,
      totalLogs: goal.dailyLogs.length,
      totalStudyMinutes: totalMin,
      finalUnit: goal.currentUnit,
    ));
    goal.completed = true;
    goal.completedAt = DateTime.now().toIso8601String();
    goal.completedRound = round;
  }

  Future<void> _completeGoal(ProgressGoal goal) async {
    final ok =
        await _confirm('이 학습 목표를 완료 처리하시겠습니까?');
    if (!ok) return;
    _autoComplete(goal);
    await _fb.saveProgressGoals(_goals);
    _safeSetState(() {});
    _snack('🎉 학습 완료!');
  }

  Future<void> _restartGoal(ProgressGoal goal) async {
    final ok = await _confirm(
        '"${goal.title}" 을(를) 다시 시작하시겠습니까?');
    if (!ok) return;
    goal.completed = false;
    goal.completedAt = null;
    goal.currentUnit = 0;
    goal.dailyLogs = [];
    goal.startDate =
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    goal.endDate = null;
    await _fb.saveProgressGoals(_goals);
    _safeSetState(() {});
    final round = goal.completionHistory.length + 1;
    _snack('🔄 ${round}회차 학습 시작!');
  }

  Future<void> _deleteGoal(ProgressGoal goal) async {
    final ok = await _confirm(
        '정말 삭제하시겠습니까? 기록이 모두 사라집니다.');
    if (!ok) return;
    _goals.removeWhere((g) => g.id == goal.id);
    await _fb.saveProgressGoals(_goals);
    _safeSetState(() {});
    _snack('삭제됨');
  }

  // ─── 유틸 ───

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('확인'),
            content: Text(msg),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('확인',
                      style:
                          TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating),
    );
  }
}

// ─── 내부 헬퍼 클래스 ───

class _SubjCfg {
  final int color;
  final int light;
  final String emoji;
  final String tag;
  const _SubjCfg(this.color, this.light, this.emoji, this.tag);
}

class _SubjStat {
  int count = 0;
  double pctSum = 0;
  int delayed = 0;
  int completed = 0;
}
