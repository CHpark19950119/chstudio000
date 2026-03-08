import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// TAB 4 — 회계 (VAULT · Expense Ledger)
/// 수험생활 비용 추적 · 월별 리포트 · 카테고리 분석 · 누적 잔고
/// ═══════════════════════════════════════════════════════════

class OrderExpenseTab extends StatefulWidget {
  final OrderData data;
  final void Function(VoidCallback fn) onUpdate;

  const OrderExpenseTab({
    super.key, required this.data, required this.onUpdate,
  });

  @override
  State<OrderExpenseTab> createState() => _OrderExpenseTabState();
}

class _OrderExpenseTabState extends State<OrderExpenseTab> {
  /// 현재 선택된 월 (null = 전체)
  String? _selectedMonth;

  OrderData get data => widget.data;
  void Function(VoidCallback fn) get onUpdate => widget.onUpdate;

  // ── 정렬된 비용 리스트 (최신순) ──
  List<StudyExpense> get _allSorted =>
      data.expenses.toList()..sort((a, b) => b.date.compareTo(a.date));

  List<StudyExpense> get _filtered {
    if (_selectedMonth == null) return _allSorted;
    return _allSorted.where((e) => e.date.startsWith(_selectedMonth!)).toList();
  }

  /// 사용 가능한 월 목록 (yyyy-MM)
  List<String> get _months {
    final set = <String>{};
    for (final e in data.expenses) {
      if (e.date.length >= 7) set.add(e.date.substring(0, 7));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
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

  int _totalOf(List<StudyExpense> list) =>
      list.fold(0, (s, e) => s + e.amount);

  Map<String, int> _catMapOf(List<StudyExpense> list) {
    final map = <String, int>{};
    for (final e in list) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = _totalOf(filtered);
    final allTotal = data.totalExpenseAmount;
    final catMap = _catMapOf(filtered);
    final months = _months;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        _vaultHeader(allTotal, total, filtered.length),
        const SizedBox(height: 14),
        _monthSelector(months),
        const SizedBox(height: 14),
        _monthlyOverview(filtered, total),
        const SizedBox(height: 14),
        _categoryBreakdown(catMap, total),
        const SizedBox(height: 14),
        _addButton(),
        const SizedBox(height: 14),
        _ledgerEntries(filtered),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  VAULT HEADER — 총 지출 카드
  // ═══════════════════════════════════════════

  Widget _vaultHeader(int allTotal, int filteredTotal, int count) {
    final isAll = _selectedMonth == null;
    final displayTotal = isAll ? allTotal : filteredTotal;
    final label = isAll ? '총 수험 비용' : '${_monthLabel(_selectedMonth!)} 지출';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0C1222), Color(0xFF1A2744)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.08),
            blurRadius: 32, offset: const Offset(0, 12)),
          BoxShadow(color: Colors.black.withOpacity(0.15),
            blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // VAULT 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFFD4AF37).withOpacity(0.2),
                const Color(0xFFF5C842).withOpacity(0.1),
              ]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('📒', style: TextStyle(fontSize: 11)),
              SizedBox(width: 5),
              Text('VAULT', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w900,
                color: Color(0xFFD4AF37), letterSpacing: 2)),
            ]),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8)),
            child: Text('$count건', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.4))),
          ),
        ]),
        const SizedBox(height: 22),
        Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500,
          color: Colors.white.withOpacity(0.4), letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text(_fmtFull(displayTotal), style: const TextStyle(
          fontSize: 34, fontWeight: FontWeight.w900,
          color: Colors.white, letterSpacing: -1)),
        if (!isAll) ...[
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 4, height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF94A3B8), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('누적 ${_fmtFull(allTotal)}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.3))),
          ]),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════
  //  MONTH SELECTOR — 월 선택 탭
  // ═══════════════════════════════════════════

  Widget _monthSelector(List<String> months) {
    if (months.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _monthChip(null, '전체'),
          ...months.map((m) => _monthChip(m, _monthLabel(m))),
        ],
      ),
    );
  }

  Widget _monthChip(String? month, String label) {
    final sel = _selectedMonth == month;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _safeSetState(() => _selectedMonth = month);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? OC.accent : OC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? OC.accent : OC.border),
          boxShadow: sel ? [BoxShadow(color: OC.accent.withOpacity(0.2),
            blurRadius: 8, offset: const Offset(0, 2))] : null),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: sel ? Colors.white : OC.text3)),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  MONTHLY OVERVIEW — 월 요약 통계
  // ═══════════════════════════════════════════

  Widget _monthlyOverview(List<StudyExpense> filtered, int total) {
    if (filtered.isEmpty) return const SizedBox.shrink();

    // 일평균 계산
    final dates = filtered.map((e) => e.date).toSet();
    final avgPerDay = dates.isNotEmpty ? total ~/ dates.length : 0;

    // 최대 지출 항목
    StudyExpense? maxItem;
    for (final e in filtered) {
      if (maxItem == null || e.amount > maxItem.amount) maxItem = e;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.border.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: [
        Expanded(child: _statCell(
          '거래일', '${dates.length}일',
          Icons.calendar_today_rounded, const Color(0xFF6366F1))),
        Container(width: 1, height: 40, color: OC.border.withOpacity(0.4)),
        Expanded(child: _statCell(
          '일 평균', _fmtShort(avgPerDay),
          Icons.trending_up_rounded, const Color(0xFF0EA5E9))),
        Container(width: 1, height: 40, color: OC.border.withOpacity(0.4)),
        Expanded(child: _statCell(
          '최대', maxItem != null ? _fmtShort(maxItem.amount) : '-',
          Icons.arrow_upward_rounded, const Color(0xFFF59E0B))),
      ]),
    );
  }

  Widget _statCell(String label, String value, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, size: 16, color: color.withOpacity(0.7)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.w800, color: OC.text1)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w500, color: OC.text3)),
    ]);
  }

  // ═══════════════════════════════════════════
  //  CATEGORY BREAKDOWN — 카테고리 비율 (도넛 스타일)
  // ═══════════════════════════════════════════

  Widget _categoryBreakdown(Map<String, int> catMap, int total) {
    if (catMap.isEmpty) return const SizedBox.shrink();

    final sorted = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.border.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.donut_large_rounded, size: 16, color: OC.accent),
          SizedBox(width: 8),
          Text('카테고리별', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800, color: OC.text1)),
        ]),
        const SizedBox(height: 14),
        // 스택형 진행 바
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: sorted.map((e) {
                final ratio = total > 0 ? e.value / total : 0.0;
                return Expanded(
                  flex: (ratio * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: _catColor(e.key),
                    margin: EdgeInsets.only(
                      right: e.key != sorted.last.key ? 1.5 : 0)),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...sorted.map((e) {
          final ratio = total > 0 ? e.value / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _catColor(e.key),
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Text(_catEmoji(e.key), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(e.key, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: OC.text1)),
              const Spacer(),
              Text(_fmtWon(e.value), style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: OC.text1)),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text(
                '${(ratio * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w600, color: OC.text3))),
            ]),
          );
        }),
      ]),
    );
  }

  // ═══════════════════════════════════════════
  //  ADD BUTTON — 기록 추가
  // ═══════════════════════════════════════════

  Widget _addButton() {
    return GestureDetector(
      onTap: () => _openAddSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5B5FE6), Color(0xFF7C7FF2)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: OC.accent.withOpacity(0.25),
            blurRadius: 16, offset: const Offset(0, 4))]),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('비용 기록', style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800, color: Colors.white,
              letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  LEDGER ENTRIES — 회계장부 스타일 거래 내역
  // ═══════════════════════════════════════════

  Widget _ledgerEntries(List<StudyExpense> sorted) {
    if (sorted.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: const Column(children: [
          Text('📒', style: TextStyle(fontSize: 44)),
          SizedBox(height: 14),
          Text('기록된 비용이 없습니다', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: OC.text3)),
          SizedBox(height: 4),
          Text('첫 비용을 기록하세요', style: TextStyle(
            fontSize: 11, color: OC.text4)),
        ]),
      );
    }

    // 날짜별 그룹핑
    final Map<String, List<StudyExpense>> grouped = {};
    for (final e in sorted) {
      grouped.putIfAbsent(e.date, () => []).add(e);
    }

    // 누적 잔고 계산 (위에서 아래로 = 최신 → 과거)
    int runningTotal = _totalOf(sorted);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.border.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Row(children: [
          const Icon(Icons.menu_book_rounded, size: 16, color: OC.text2),
          const SizedBox(width: 8),
          const Text('장부', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800, color: OC.text1)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: OC.bgSub, borderRadius: BorderRadius.circular(8)),
            child: Text('${sorted.length}건', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: OC.text3)),
          ),
        ]),
        const SizedBox(height: 6),
        // 테이블 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: OC.border.withOpacity(0.4)))),
          child: const Row(children: [
            SizedBox(width: 44),
            Expanded(child: Text('항목', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: OC.text4, letterSpacing: 0.5))),
            SizedBox(width: 70, child: Text('금액', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: OC.text4, letterSpacing: 0.5))),
            SizedBox(width: 70, child: Text('누적', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: OC.text4, letterSpacing: 0.5))),
          ]),
        ),
        // 엔트리
        ...grouped.entries.expand((g) {
          final dayWidgets = <Widget>[];
          final dayTotal = g.value.fold(0, (s, e) => s + e.amount);

          // 날짜 구분선
          dayWidgets.add(Container(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(_fmtDate(g.key), style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: OC.text2)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 0.5,
                color: OC.border.withOpacity(0.3))),
              const SizedBox(width: 8),
              Text(_fmtShort(dayTotal), style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: OC.text3)),
            ]),
          ));

          // 개별 항목
          for (final e in g.value) {
            dayWidgets.add(_ledgerRow(e, runningTotal));
            runningTotal -= e.amount;
          }
          return dayWidgets;
        }),
      ]),
    );
  }

  Widget _ledgerRow(StudyExpense e, int cumulative) {
    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(e),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: OC.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.delete_outline_rounded,
          color: OC.error, size: 18)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
            color: OC.border.withOpacity(0.15)))),
        child: Row(children: [
          // 카테고리 아이콘
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _catColor(e.category).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(_catEmoji(e.category),
              style: const TextStyle(fontSize: 15))),
          ),
          const SizedBox(width: 10),
          // 항목 + 카테고리
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: OC.text1),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Row(children: [
                Text(e.category, style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _catColor(e.category))),
                if (e.note != null && e.note!.isNotEmpty) ...[
                  Text(' · ', style: TextStyle(fontSize: 9, color: OC.text4)),
                  Expanded(child: Text(e.note!, style: const TextStyle(
                    fontSize: 9, color: OC.text4),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ],
          )),
          // 금액
          SizedBox(width: 70, child: Text(
            '-${_fmtShort(e.amount)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w800, color: Color(0xFFEF4444)))),
          // 누적
          SizedBox(width: 70, child: Text(
            _fmtShort(cumulative),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: OC.text3))),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  ADD SHEET
  // ═══════════════════════════════════════════

  void _openAddSheet(BuildContext context) {
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String selectedCat = StudyExpense.categories.first;
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          decoration: const BoxDecoration(color: OC.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.fromLTRB(
            20, 8, 20, sheetBottomPad(ctx, extra: 32)),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              sheetHandle(),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: OC.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.edit_note_rounded,
                    size: 18, color: OC.accent)),
                const SizedBox(width: 10),
                const Text('비용 기록', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1)),
              ]),
              const SizedBox(height: 20),

              sheetField('항목명', titleC, '예: 조훈 자료해석 모의고사'),
              _amountField(amountC),
              const SizedBox(height: 14),

              // 카테고리
              const Align(alignment: Alignment.centerLeft,
                child: Text('카테고리', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: OC.text2))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: StudyExpense.categories.map((cat) {
                  final sel = selectedCat == cat;
                  return GestureDetector(
                    onTap: () => setS(() => selectedCat = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? _catColor(cat) : OC.bgSub,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel
                            ? _catColor(cat) : OC.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_catEmoji(cat),
                          style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(cat, style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : OC.text2)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // 날짜
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) setS(() => selectedDate = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: OC.bgSub,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OC.border)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                      size: 16, color: OC.text3),
                    const SizedBox(width: 10),
                    Text(DateFormat('yyyy년 M월 d일 (E)', 'ko')
                        .format(selectedDate),
                      style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: OC.text1)),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                      size: 18, color: OC.text4),
                  ]),
                ),
              ),
              const SizedBox(height: 10),

              sheetField('메모 (선택)', noteC, ''),
              const SizedBox(height: 20),

              SizedBox(width: double.infinity,
                child: sheetBtn('기록하기', OC.accent, Colors.white, () {
                  final title = titleC.text.trim();
                  final amount = int.tryParse(
                    amountC.text.trim().replaceAll(',', '')
                        .replaceAll('원', '').replaceAll('만', '')) ?? 0;
                  if (title.isEmpty || amount <= 0) return;
                  onUpdate(() {
                    data.expenses.add(StudyExpense(
                      id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
                      title: title,
                      amount: amount,
                      category: selectedCat,
                      date: DateFormat('yyyy-MM-dd').format(selectedDate),
                      note: noteC.text.trim().isEmpty
                          ? null : noteC.text.trim(),
                    ));
                  });
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                })),
              const SizedBox(height: 16),
            ],
          )),
        ),
      ),
    );
  }

  // ═══ AMOUNT FIELD ═══
  Widget _amountField(TextEditingController c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('금액', style: TextStyle(fontSize: 12,
        fontWeight: FontWeight.w600, color: OC.text2)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: OC.bgSub,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OC.border)),
        child: Row(children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Text('₩', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w800, color: OC.accent))),
          Expanded(child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18,
              fontWeight: FontWeight.w800, color: OC.text1),
            decoration: const InputDecoration(
              hintText: '180,000',
              hintStyle: TextStyle(color: OC.text4, fontWeight: FontWeight.w400),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14)),
          )),
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Text('원', style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: OC.text3))),
        ]),
      ),
    ]);
  }

  // ═══ DELETE ═══
  Future<bool> _confirmDelete(StudyExpense e) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('비용 삭제', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('${e.title} ${_fmtWon(e.amount)}을 삭제할까요?',
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
              style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (result == true) {
      onUpdate(() { data.expenses.removeWhere((x) => x.id == e.id); });
      HapticFeedback.lightImpact();
    }
    return result ?? false;
  }

  // ═══ FORMATTERS ═══

  String _fmtWon(int amount) {
    if (amount >= 10000) {
      final man = amount ~/ 10000;
      final rest = amount % 10000;
      return rest == 0 ? '${man}만원' : '${man}만${_numFmt(rest)}원';
    }
    return '${_numFmt(amount)}원';
  }

  String _fmtFull(int amount) {
    if (amount == 0) return '₩0';
    return '₩${_numFmt(amount)}';
  }

  String _fmtShort(int amount) {
    if (amount >= 10000) {
      final man = amount ~/ 10000;
      final rest = amount % 10000;
      return rest == 0 ? '${man}만' : '${man}.${(rest ~/ 1000)}만';
    }
    return '${_numFmt(amount)}';
  }

  String _numFmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fmtDate(String date) {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    return DateFormat('M/d (E)', 'ko').format(d);
  }

  String _monthLabel(String ym) {
    final parts = ym.split('-');
    if (parts.length < 2) return ym;
    return '${int.parse(parts[1])}월';
  }

  String _catEmoji(String cat) {
    switch (cat) {
      case '모의고사': return '📝';
      case '교재': return '📚';
      case '인강': return '🎧';
      case '문구': return '✏️';
      default: return '💰';
    }
  }

  Color _catColor(String cat) {
    switch (cat) {
      case '모의고사': return const Color(0xFF6366F1);
      case '교재': return const Color(0xFF0EA5E9);
      case '인강': return const Color(0xFFF59E0B);
      case '문구': return const Color(0xFF22C55E);
      default: return const Color(0xFF94A3B8);
    }
  }
}
