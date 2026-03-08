import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/botanical_theme.dart';
import '../services/firebase_service.dart';
import '../utils/study_date_utils.dart';

/// ═══════════════════════════════════════════════
///  CHEONHONG STUDIO — 데일리 인사이트 기록
///  매일 학습 회고 + 인사이트 + 내일 계획
/// ═══════════════════════════════════════════════

class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  final _fb = FirebaseService();
  bool _dk = true;
  bool _loading = true;
  String _selectedDate = '';
  final Map<String, DailyInsight> _insights = {};
  final _scrollCtrl = ScrollController();

  // 입력 컨트롤러
  final _todayLearnCtrl = TextEditingController();
  final _todayInsightCtrl = TextEditingController();
  final _tomorrowPlanCtrl = TextEditingController();
  final _moodCtrl = TextEditingController();
  int _energyLevel = 3; // 1~5
  String _selectedMood = '😊';

  static const _moods = ['😊', '😤', '😴', '🤔', '😰', '🔥', '😌', '💪'];

  @override
  void initState() {
    super.initState();
    _selectedDate = _studyDate(DateTime.now());
    _loadInsights();
  }

  @override
  void dispose() {
    _todayLearnCtrl.dispose();
    _todayInsightCtrl.dispose();
    _tomorrowPlanCtrl.dispose();
    _moodCtrl.dispose();
    _scrollCtrl.dispose();
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

  /// 4AM 학습일 기준
  String _studyDate(DateTime dt) => StudyDateUtils.todayKey(dt);

  Future<void> _loadInsights() async {
    _safeSetState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(_fb.uid)
          .collection('insights').doc(_selectedDate).get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists) {
        final d = doc.data()!;
        final insight = DailyInsight.fromMap(d);
        _insights[_selectedDate] = insight;
        _todayLearnCtrl.text = insight.todayLearned;
        _todayInsightCtrl.text = insight.insight;
        _tomorrowPlanCtrl.text = insight.tomorrowPlan;
        _selectedMood = insight.mood;
        _energyLevel = insight.energyLevel;
      } else {
        _todayLearnCtrl.clear();
        _todayInsightCtrl.clear();
        _tomorrowPlanCtrl.clear();
        _selectedMood = '😊';
        _energyLevel = 3;
      }

      // 최근 7일 인사이트 로드
      final now = DateTime.now();
      for (int i = 1; i <= 7; i++) {
        final d = _studyDate(now.subtract(Duration(days: i)));
        if (_insights.containsKey(d)) continue;
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users').doc(_fb.uid)
              .collection('insights').doc(d).get()
              .timeout(const Duration(seconds: 3));
          if (snap.exists) {
            _insights[d] = DailyInsight.fromMap(snap.data()!);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Insight] Load error: $e');
    }
    if (mounted) _safeSetState(() => _loading = false);
  }

  Future<void> _save() async {
    final insight = DailyInsight(
      date: _selectedDate,
      todayLearned: _todayLearnCtrl.text.trim(),
      insight: _todayInsightCtrl.text.trim(),
      tomorrowPlan: _tomorrowPlanCtrl.text.trim(),
      mood: _selectedMood,
      energyLevel: _energyLevel,
      savedAt: DateTime.now(),
    );
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(_fb.uid)
          .collection('insights').doc(_selectedDate)
          .set(insight.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));
      _insights[_selectedDate] = insight;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('💾 인사이트 저장 완료'),
            backgroundColor: BotanicalColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    } catch (e) {
      debugPrint('[Insight] Save error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _dk = Theme.of(context).brightness == Brightness.dark;
    final bg = _dk ? const Color(0xFF0d1f16) : const Color(0xFFFCF9F3);
    final textMain = _dk ? Colors.white : const Color(0xFF1e293b);
    final textSub = _dk ? Colors.white54 : Colors.grey;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textMain),
          onPressed: () => Navigator.pop(context)),
        title: Text('데일리 인사이트', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, color: textMain)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.save_rounded, size: 22, color: BotanicalColors.primary),
            onPressed: _save),
        ],
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: BotanicalColors.primary))
        : SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── 날짜 선택 ──
              _datePicker(textMain, textSub),
              const SizedBox(height: 20),

              // ── 기분 + 에너지 ──
              _moodSection(textMain, textSub),
              const SizedBox(height: 20),

              // ── 오늘 배운 것 ──
              _inputCard(
                '📖 오늘 배운 것', '무엇을 공부했나요?', _todayLearnCtrl,
                textMain, textSub, maxLines: 3),
              const SizedBox(height: 16),

              // ── 오늘의 인사이트 ──
              _inputCard(
                '💡 오늘의 인사이트', '깨달은 점, 느낀 점을 적어보세요', _todayInsightCtrl,
                textMain, textSub, maxLines: 4),
              const SizedBox(height: 16),

              // ── 내일 계획 ──
              _inputCard(
                '🎯 내일 계획', '내일 집중할 과목과 목표', _tomorrowPlanCtrl,
                textMain, textSub, maxLines: 2),
              const SizedBox(height: 24),

              // ── 최근 인사이트 타임라인 ──
              _recentTimeline(textMain, textSub),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  Widget _datePicker(Color textMain, Color textSub) {
    final now = DateTime.now();
    final dates = List.generate(7, (i) => _studyDate(now.subtract(Duration(days: i))));

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        itemBuilder: (ctx, i) {
          final d = dates[i];
          final dt = DateTime.parse(d);
          final isSelected = d == _selectedDate;
          final hasData = _insights.containsKey(d);

          return GestureDetector(
            onTap: () {
              _safeSetState(() => _selectedDate = d);
              _loadInsights();
            },
            child: Container(
              width: 52, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? BotanicalColors.primary.withOpacity(0.15)
                    : (_dk ? Colors.white.withOpacity(0.04) : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? BotanicalColors.primary.withOpacity(0.4)
                      : Colors.transparent, width: 1.5)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(['월','화','수','목','금','토','일'][dt.weekday - 1],
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: isSelected ? BotanicalColors.primary : textSub)),
                const SizedBox(height: 2),
                Text('${dt.day}', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: isSelected ? BotanicalColors.primary : textMain)),
                if (hasData) Container(
                  width: 5, height: 5, margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: BotanicalColors.primary, shape: BoxShape.circle)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _moodSection(Color textMain, Color textSub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('기분 & 에너지', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: textMain)),
        const SizedBox(height: 12),

        // 기분 이모지 선택
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _moods.map((m) {
            final selected = m == _selectedMood;
            return GestureDetector(
              onTap: () => _safeSetState(() => _selectedMood = m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? BotanicalColors.primary.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? BotanicalColors.primary.withOpacity(0.4)
                        : Colors.transparent)),
                child: Center(child: Text(m, style: TextStyle(
                  fontSize: selected ? 22 : 18))),
              ),
            );
          }).toList()),

        const SizedBox(height: 16),

        // 에너지 레벨 바
        Row(children: [
          Text('에너지', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: textSub)),
          const Spacer(),
          ...List.generate(5, (i) {
            final level = i + 1;
            final active = level <= _energyLevel;
            return GestureDetector(
              onTap: () => _safeSetState(() => _energyLevel = level),
              child: Container(
                width: 32, height: 12, margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: active
                      ? BotanicalColors.primary.withOpacity(0.2 + level * 0.16)
                      : (_dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(4)),
              ),
            );
          }),
          const SizedBox(width: 8),
          Text('$_energyLevel/5', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: BotanicalColors.primary)),
        ]),
      ]),
    );
  }

  Widget _inputCard(String title, String hint, TextEditingController ctrl,
      Color textMain, Color textSub, {int maxLines = 3}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: textMain)),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          maxLines: maxLines, minLines: maxLines,
          style: TextStyle(fontSize: 14, color: textMain, height: 1.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: textSub.withOpacity(0.5)),
            border: InputBorder.none, isDense: true,
            contentPadding: EdgeInsets.zero),
        ),
      ]),
    );
  }

  Widget _recentTimeline(Color textMain, Color textSub) {
    final sorted = _insights.entries.where((e) => e.key != _selectedDate)
        .toList()..sort((a, b) => b.key.compareTo(a.key));
    if (sorted.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('📅 최근 인사이트', style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w800, color: textMain)),
      const SizedBox(height: 12),
      ...sorted.take(5).map((e) {
        final dt = DateTime.parse(e.key);
        final ins = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(ins.mood, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('${dt.month}/${dt.day}', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: textMain)),
              const Spacer(),
              // 에너지 바
              ...List.generate(5, (i) => Container(
                width: 12, height: 4, margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: i < ins.energyLevel
                      ? BotanicalColors.primary.withOpacity(0.4 + i * 0.12)
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2)),
              )),
            ]),
            if (ins.insight.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(ins.insight, style: TextStyle(
                fontSize: 12, color: textSub, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        );
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════
//  인사이트 데이터 모델
// ═══════════════════════════════════════════════

class DailyInsight {
  final String date;
  final String todayLearned;
  final String insight;
  final String tomorrowPlan;
  final String mood;
  final int energyLevel;
  final DateTime? savedAt;

  DailyInsight({
    required this.date,
    this.todayLearned = '',
    this.insight = '',
    this.tomorrowPlan = '',
    this.mood = '😊',
    this.energyLevel = 3,
    this.savedAt,
  });

  factory DailyInsight.fromMap(Map<String, dynamic> m) => DailyInsight(
    date: m['date'] ?? '',
    todayLearned: m['todayLearned'] ?? '',
    insight: m['insight'] ?? '',
    tomorrowPlan: m['tomorrowPlan'] ?? '',
    mood: m['mood'] ?? '😊',
    energyLevel: m['energyLevel'] ?? 3,
    savedAt: m['savedAt'] != null
        ? (m['savedAt'] as Timestamp).toDate()
        : null,
  );

  Map<String, dynamic> toMap() => {
    'date': date,
    'todayLearned': todayLearned,
    'insight': insight,
    'tomorrowPlan': tomorrowPlan,
    'mood': mood,
    'energyLevel': energyLevel,
    'savedAt': FieldValue.serverTimestamp(),
  };
}
