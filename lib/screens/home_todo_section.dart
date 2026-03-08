part of 'home_screen.dart';

/// =====================================================
/// HOME - Todo (Glassmorphism Design)
/// viewInsets.bottom + SafeArea padding required for sheets/dialogs
/// =====================================================
extension _HomeTodoSection on _HomeScreenState {

  // --------------------------------------------------
  // Theme-aware colors
  // --------------------------------------------------
  Color get _todoGreen => _dk ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color get _todoAmber => _dk ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get _todoDanger => const Color(0xFFEF4444);

  Color _todoRateColor(double rate) =>
      rate >= 0.8 ? _todoGreen : rate >= 0.5 ? _todoAmber : _todoDanger;

  // --------------------------------------------------
  // Glassmorphism helper (inline, part file)
  // --------------------------------------------------
  Widget _todoGlass({
    required Widget child,
    double blur = 10,
    double radius = 16,
    EdgeInsets? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _dk
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: _dk
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.4),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // Completion circle widget
  // --------------------------------------------------
  Widget _completionCircle(double rate, int completed, int total) {
    final color = _todoRateColor(rate);
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: total > 0 ? rate : 0,
          strokeWidth: 5,
          backgroundColor: color.withOpacity(0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$completed',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text('/$total',
              style: TextStyle(fontSize: 10, color: _textMuted)),
        ]),
      ]),
    );
  }

  // ==================================================
  //  Main page
  // ==================================================
  Widget _todoPage() {
    final todos = _todayTodos;
    final items = todos?.items ?? [];
    final rate = todos?.completionRate ?? 0.0;
    final completed = todos?.completedCount ?? 0;
    final total = todos?.totalCount ?? 0;

    return RefreshIndicator(
      color: BotanicalColors.primary,
      onRefresh: () => _loadTodosOnly(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // -- Header: date + completion circle --
          _todoHeader(rate, completed, total),
          const SizedBox(height: 20),

          // -- Todo list --
          if (items.isEmpty)
            _todoEmptyState()
          else
            ...items.asMap().entries.map((e) => _todoItemTile(e.value, e.key)),

          const SizedBox(height: 12),

          // -- Inline add --
          _todoInlineAdd(),

          const SizedBox(height: 16),

          // -- Tomorrow prep --
          _tomorrowPrepButton(),

          const SizedBox(height: 20),

          // -- Stats button --
          _todoStatsButton(),

          const SizedBox(height: 16),

          // -- Weekly history --
          _weeklyHistory(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==================================================
  //  Header (date nav + completion circle)
  // ==================================================
  Widget _todoHeader(double rate, int completed, int total) {
    final selectedDt = DateFormat('yyyy-MM-dd').parse(_todoSelectedDate);
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateLabel =
        '${selectedDt.month}월 ${selectedDt.day}일 (${weekdays[selectedDt.weekday - 1]})';
    final isToday = _todoSelectedDate == StudyDateUtils.todayKey();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // -- Title row --
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('Todo',
            style: BotanicalTypo.heading(
                size: 26, weight: FontWeight.w800, color: _textMain)),
        const Spacer(),
        _completionCircle(rate, completed, total),
      ]),
      const SizedBox(height: 16),

      // -- Date navigation with glassmorphism chips --
      Row(children: [
        // < prev
        GestureDetector(
          onTap: () {
            final prev = selectedDt.subtract(const Duration(days: 1));
            _loadTodosForDate(DateFormat('yyyy-MM-dd').format(prev));
          },
          child: _todoGlass(
            radius: 10,
            blur: 8,
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.chevron_left_rounded,
                size: 20, color: _textSub),
          ),
        ),
        const SizedBox(width: 6),
        // today chip
        GestureDetector(
          onTap: isToday
              ? null
              : () {
                  final today = StudyDateUtils.todayKey();
                  _loadTodosForDate(today);
                },
          child: _todoGlass(
            radius: 10,
            blur: 8,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(dateLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isToday ? BotanicalColors.primary : _textSub)),
          ),
        ),
        const SizedBox(width: 6),
        // > next
        GestureDetector(
          onTap: () {
            final next = selectedDt.add(const Duration(days: 1));
            _loadTodosForDate(DateFormat('yyyy-MM-dd').format(next));
          },
          child: _todoGlass(
            radius: 10,
            blur: 8,
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.chevron_right_rounded,
                size: 20, color: _textSub),
          ),
        ),
        const Spacer(),
        // rate percentage badge
        _todoGlass(
          radius: 8,
          blur: 6,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            total > 0 ? '${(rate * 100).round()}%' : '-',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: total > 0 ? _todoRateColor(rate) : _textMuted),
          ),
        ),
      ]),
    ]);
  }

  // ==================================================
  //  Empty state
  // ==================================================
  Widget _todoEmptyState() {
    return _todoGlass(
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(children: [
        Icon(Icons.checklist_rounded,
            size: 48, color: _textMuted.withOpacity(0.3)),
        const SizedBox(height: 12),
        Text('아직 할일이 없습니다',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textMuted)),
        const SizedBox(height: 4),
        Text('아래에서 바로 입력하세요',
            style:
                TextStyle(fontSize: 12, color: _textMuted.withOpacity(0.6))),
      ]),
    );
  }

  // ==================================================
  //  Todo item tile (glassmorphism + animated checkbox)
  // ==================================================
  Widget _todoItemTile(TodoItem item, int index) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
            color: _todoDanger.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16)),
        child: Icon(Icons.delete_outline_rounded,
            color: _todoDanger, size: 22),
      ),
      onDismissed: (_) => _deleteTodoItem(item.id),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _todoGlass(
          radius: 16,
          blur: 10,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _editTodoItem(item),
            onLongPress: () => _confirmDeleteTodo(item),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                // -- Circular checkbox with scale animation --
                GestureDetector(
                  onTap: () => _toggleTodoItem(item),
                  child: AnimatedScale(
                    scale: item.completed ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: item.completed
                            ? _todoGreen.withOpacity(0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: item.completed
                              ? _todoGreen
                              : _textMuted.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: item.completed
                          ? Icon(Icons.check_rounded,
                              size: 16, color: _todoGreen)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // -- Title --
                Expanded(
                  child: Text(item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: item.completed ? _textMuted : _textMain,
                        decoration: item.completed
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: _textMuted.withOpacity(0.5),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Long-press delete confirmation dialog
  void _confirmDeleteTodo(TodoItem item) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('삭제 확인'),
        content: Text('"${item.title}" 을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteTodoItem(item.id);
              },
              child: const Text('삭제',
                  style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  /// Inline add (delegates to StatefulWidget)
  Widget _todoInlineAdd() {
    return _TodoInlineAddWidget(
      dk: _dk,
      border: _border,
      textMain: _textMain,
      textMuted: _textMuted,
      onAdd: (title) => _addTodoItem(title),
    );
  }

  // ==================================================
  //  Tomorrow prep button (glassmorphism)
  // ==================================================
  Widget _tomorrowPrepButton() {
    return GestureDetector(
      onTap: () => _showTomorrowPrepSheet(),
      child: _todoGlass(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(Icons.wb_sunny_outlined,
              size: 20, color: _todoAmber),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('내일 준비',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textMain)),
                Text('미완료 이월 + 새 할일 추가',
                    style: TextStyle(fontSize: 11, color: _textMuted)),
              ])),
          Icon(Icons.chevron_right_rounded, size: 20, color: _textMuted),
        ]),
      ),
    );
  }

  // ==================================================
  //  Weekly history (mini bar chart, rounded tops, color-coded)
  // ==================================================
  Widget _weeklyHistory() {
    final history = _weeklyHistoryCache;
    if (history == null || history.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedKeys = history.keys.toList()..sort();

    return _todoGlass(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('최근 7일',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _textMain)),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: sortedKeys.map((date) {
            final rate = history[date] ?? 0.0;
            final dayLabel = date.substring(8);
            final barColor = rate >= 0.8
                ? _todoGreen
                : rate >= 0.5
                    ? _todoAmber
                    : rate > 0
                        ? _todoDanger
                        : _border.withOpacity(0.4);
            final isToday = date == StudyDateUtils.todayKey();

            return Expanded(
                child: Column(children: [
              Container(
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    height: (rate * 60).clamp(4.0, 60.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          barColor.withOpacity(0.9),
                          barColor.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                        bottom: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(dayLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isToday ? _textMain : _textMuted)),
            ]));
          }).toList(),
        ),
      ]),
    );
  }

  // ==================================================
  //  Todo interactions
  // ==================================================

  void _toggleTodoItem(TodoItem item) {
    final existing = _todayTodos;
    if (existing == null) return;
    final newCompleted = !item.completed;

    // 1) Optimistic UI: swap to new object immediately
    final updated = TodoDaily(
      date: existing.date,
      items: existing.items
          .map((t) => t.id == item.id
              ? t.copyWith(
                  completed: newCompleted,
                  completedAt:
                      newCompleted ? DateTime.now().toIso8601String() : null)
              : t)
          .toList(),
      memo: existing.memo,
      createdAt: existing.createdAt,
    );
    _safeSetState(() => _todayTodos = updated);

    // 2) fire-and-forget (saveTodos updates cache + Firestore async)
    TodoService().saveTodos(updated);
  }

  void _deleteTodoItem(String id) async {
    final todos = _todayTodos;
    if (todos == null) return;

    final updated = TodoDaily(
      date: _todoSelectedDate,
      items: todos.items.where((t) => t.id != id).toList(),
      memo: todos.memo,
      createdAt: todos.createdAt,
    );

    _safeSetState(() => _todayTodos = updated);
    TodoService().saveTodos(updated);
  }

  Future<void> _addTodoItem(String title) async {
    final date = _todoSelectedDate;
    final existing = _todayTodos ?? TodoDaily(date: date);
    final newItem = TodoItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      order: existing.items.length,
    );

    final updated = TodoDaily(
      date: existing.date,
      items: [...existing.items, newItem],
      memo: existing.memo,
      createdAt: existing.createdAt,
    );

    _safeSetState(() => _todayTodos = updated);
    TodoService().saveTodos(updated);
  }

  // ==================================================
  //  Stats button (glassmorphism)
  // ==================================================
  Widget _todoStatsButton() {
    return GestureDetector(
      onTap: () => _showTodoStatsSheet(),
      child: _todoGlass(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(Icons.bar_chart_rounded, size: 20, color: BotanicalColors.gold),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('통계 & AI 분석',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textMain)),
                Text('날짜별 열람 · 달성율 · 학습 패턴 분석',
                    style: TextStyle(fontSize: 11, color: _textMuted)),
              ])),
          Icon(Icons.chevron_right_rounded, size: 20, color: _textMuted),
        ]),
      ),
    );
  }

  void _showTodoStatsSheet() async {
    final fb = FirebaseService();
    final data = await fb.getStudyData();
    final todosRaw = data?['todos'] as Map<String, dynamic>? ?? {};

    final entries = <String, TodoDaily>{};
    for (final entry in todosRaw.entries) {
      try {
        final td = TodoDaily.fromMap(
            Map<String, dynamic>.from(entry.value as Map));
        entries[entry.key] = td;
      } catch (_) {}
    }

    final sortedDates = entries.keys.toList()..sort((a, b) => b.compareTo(a));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _TodoStatsSheet(
        dk: _dk,
        textMain: _textMain,
        textMuted: _textMuted,
        border: _border,
        entries: entries,
        sortedDates: sortedDates,
      ),
    );
  }

  void _showTomorrowPrepSheet() async {
    final controller = TextEditingController();
    final additions = <String>[];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setSt) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final safeBottom = MediaQuery.of(ctx).padding.bottom;
          return Container(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: bottomInset + safeBottom + 16),
            decoration: BoxDecoration(
                color: _dk ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: _textMuted.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('내일 준비',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textMain)),
              const SizedBox(height: 4),
              Text('미완료 항목이 자동으로 이월됩니다',
                  style: TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                      hintText: '추가 할일...',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10)),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (controller.text.trim().isNotEmpty) {
                      setSt(() => additions.add(controller.text.trim()));
                      controller.clear();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: BotanicalColors.primary,
                        borderRadius: BorderRadius.circular(12)),
                    child:
                        const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ]),
              if (additions.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...additions.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Icon(Icons.add_circle_outline,
                            size: 16, color: BotanicalColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(a,
                                style: TextStyle(
                                    fontSize: 13, color: _textMain))),
                        GestureDetector(
                            onTap: () => setSt(() => additions.remove(a)),
                            child: Icon(Icons.close,
                                size: 16, color: _textMuted)),
                      ]),
                    )),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final items = additions
                        .asMap()
                        .entries
                        .map((e) => TodoItem(
                              id: '${DateTime.now().millisecondsSinceEpoch}_${e.key}',
                              title: e.value,
                            ))
                        .toList();
                    await TodoService()
                        .prepareTomorrowTodos(additionalItems: items);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('내일 할일이 준비되었습니다')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: BotanicalColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('내일 준비 완료',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// =====================================================
/// Todo Stats bottom sheet (date list + AI analysis)
/// =====================================================
class _TodoStatsSheet extends StatefulWidget {
  final bool dk;
  final Color textMain, textMuted, border;
  final Map<String, TodoDaily> entries;
  final List<String> sortedDates;

  const _TodoStatsSheet({
    required this.dk,
    required this.textMain,
    required this.textMuted,
    required this.border,
    required this.entries,
    required this.sortedDates,
  });

  @override
  State<_TodoStatsSheet> createState() => _TodoStatsSheetState();
}

class _TodoStatsSheetState extends State<_TodoStatsSheet> {
  String? _selectedDate;
  String? _aiResult;
  bool _aiLoading = false;

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

  // Theme-aware colors for stats sheet
  Color get _statsGreen =>
      widget.dk ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color get _statsAmber =>
      widget.dk ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get _statsDanger => const Color(0xFFEF4444);

  Color _rateColor(double rate) =>
      rate >= 0.8 ? _statsGreen : rate >= 0.5 ? _statsAmber : _statsDanger;

  Color _rateColorInt(int rate) =>
      rate >= 80 ? _statsGreen : rate >= 50 ? _statsAmber : _statsDanger;

  @override
  Widget build(BuildContext ctx) {
    final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
    final safeBottom = MediaQuery.of(ctx).padding.bottom;
    final bg = widget.dk ? const Color(0xFF1A1612) : Colors.white;
    final selected =
        _selectedDate != null ? widget.entries[_selectedDate] : null;

    // Weekly stats
    final now = DateTime.now();
    final weekAgo = DateFormat('yyyy-MM-dd')
        .format(now.subtract(const Duration(days: 7)));
    final weekEntries = widget.entries.entries
        .where((e) => e.key.compareTo(weekAgo) >= 0)
        .toList();
    final weekTotal =
        weekEntries.fold<int>(0, (s, e) => s + e.value.totalCount);
    final weekDone =
        weekEntries.fold<int>(0, (s, e) => s + e.value.completedCount);
    final weekRate =
        weekTotal > 0 ? (weekDone / weekTotal * 100).round() : 0;

    final monthAgo = DateFormat('yyyy-MM-dd')
        .format(now.subtract(const Duration(days: 30)));
    final monthEntries = widget.entries.entries
        .where((e) => e.key.compareTo(monthAgo) >= 0)
        .toList();
    final monthTotal =
        monthEntries.fold<int>(0, (s, e) => s + e.value.totalCount);
    final monthDone =
        monthEntries.fold<int>(0, (s, e) => s + e.value.completedCount);
    final monthRate =
        monthTotal > 0 ? (monthDone / monthTotal * 100).round() : 0;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
      padding: EdgeInsets.only(bottom: bottomInset + safeBottom + 16),
      decoration: BoxDecoration(
          color: bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: widget.textMuted.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Todo 통계',
            style: BotanicalTypo.heading(
                size: 20, weight: FontWeight.w800, color: widget.textMain)),
        const SizedBox(height: 16),

        // -- Weekly / Monthly summary --
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _statCard('주간', weekRate, weekDone, weekTotal),
            const SizedBox(width: 12),
            _statCard('월간', monthRate, monthDone, monthTotal),
          ]),
        ),
        const SizedBox(height: 16),

        // -- AI analysis card --
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _aiAnalysisCard(),
        ),
        const SizedBox(height: 16),

        // -- Date list header --
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('날짜별 기록',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: widget.textMain))),
        ),
        const SizedBox(height: 8),

        Expanded(
            child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: widget.sortedDates.length,
          itemBuilder: (_, i) {
            final date = widget.sortedDates[i];
            final td = widget.entries[date]!;
            final isSelected = _selectedDate == date;
            final rate = td.completionRate;
            final rc = _rateColor(rate);

            return Column(children: [
              GestureDetector(
                onTap: () => _safeSetState(
                    () => _selectedDate = isSelected ? null : date),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                      color: isSelected
                          ? (widget.dk
                              ? Colors.white.withOpacity(0.06)
                              : const Color(0xFFF0F4FF))
                          : (widget.dk
                              ? Colors.white.withOpacity(0.02)
                              : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color:
                                  BotanicalColors.primary.withOpacity(0.3))
                          : null),
                  child: Row(children: [
                    Text(date.substring(5),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: widget.textMain)),
                    const SizedBox(width: 12),
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: rc, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${(rate * 100).round()}%',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: rc)),
                    const Spacer(),
                    Text('${td.completedCount}/${td.totalCount}',
                        style: TextStyle(
                            fontSize: 12, color: widget.textMuted)),
                    const SizedBox(width: 8),
                    Icon(
                        isSelected
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: widget.textMuted),
                  ]),
                ),
              ),
              // Selected date detail
              if (isSelected && selected != null) _dateDetail(selected),
            ]);
          },
        )),
      ]),
    );
  }

  Widget _statCard(String label, int rate, int done, int total) {
    final rc = _rateColorInt(rate);
    return Expanded(
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: widget.dk
              ? Colors.white.withOpacity(0.04)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14)),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.textMuted)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$rate',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: rc)),
          Text('%',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: rc)),
          const Spacer(),
          Text('$done/$total',
              style:
                  TextStyle(fontSize: 11, color: widget.textMuted)),
        ]),
      ]),
    ));
  }

  Widget _dateDetail(TodoDaily td) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: widget.dk ? Colors.white.withOpacity(0.03) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.border.withOpacity(0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: td.items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(
                        item.completed
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: item.completed
                            ? _statsGreen
                            : widget.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(item.title,
                            style: TextStyle(
                                fontSize: 13,
                                color: item.completed
                                    ? widget.textMuted
                                    : widget.textMain,
                                decoration: item.completed
                                    ? TextDecoration.lineThrough
                                    : null))),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _aiAnalysisCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            BotanicalColors.primary.withOpacity(widget.dk ? 0.15 : 0.08),
            BotanicalColors.gold.withOpacity(widget.dk ? 0.1 : 0.05),
          ]),
          borderRadius: BorderRadius.circular(14)),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome,
              size: 18, color: BotanicalColors.gold),
          const SizedBox(width: 8),
          Text('AI 학습 패턴 분석',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.textMain)),
          const Spacer(),
          if (!_aiLoading && _aiResult == null)
            GestureDetector(
              onTap: _requestAiAnalysis,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: BotanicalColors.primary,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('분석',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
        ]),
        if (_aiLoading) ...[
          const SizedBox(height: 12),
          const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ],
        if (_aiResult != null) ...[
          const SizedBox(height: 10),
          Text(_aiResult!,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: widget.textMain)),
        ],
      ]),
    );
  }

  Future<void> _requestAiAnalysis() async {
    _safeSetState(() {
      _aiLoading = true;
      _aiResult = null;
    });

    // Recent 7 days data
    final now = DateTime.now();
    final weekAgo = DateFormat('yyyy-MM-dd')
        .format(now.subtract(const Duration(days: 7)));
    final recentData = <String, Map<String, dynamic>>{};
    for (final entry in widget.entries.entries) {
      if (entry.key.compareTo(weekAgo) >= 0) {
        recentData[entry.key] = {
          'total': entry.value.totalCount,
          'completed': entry.value.completedCount,
          'rate': '${(entry.value.completionRate * 100).round()}%',
          'items': entry.value.items
              .map((i) => {
                    'title': i.title,
                    'done': i.completed,
                  })
              .toList(),
        };
      }
    }

    final prompt =
        '''다음은 수험생의 최근 7일간 할일(Todo) 데이터입니다:
${jsonEncode(recentData)}

위 데이터를 분석해서:
1. 학습 패턴 (어떤 과목을 많이 했는지, 완료율 추이)
2. 약한 부분 (미완료가 많은 과목이나 패턴)
3. 시간 배분 조언
4. 짧은 격려 메시지

3~5문장으로 간결하게 한국어로 답변하세요. 이모지 1~2개만 사용.''';

    try {
      const apiKey =
          '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';
      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': 'claude-sonnet-4-5-20250929',
              'max_tokens': 400,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'] as List<dynamic>?;
        if (content != null && content.isNotEmpty) {
          _safeSetState(() => _aiResult =
              content[0]['text'] as String? ?? '분석 결과를 가져올 수 없습니다.');
        }
      } else {
        _safeSetState(
            () => _aiResult = '분석 요청 실패 (${response.statusCode})');
      }
    } catch (e) {
      _safeSetState(
          () => _aiResult = '네트워크 오류: 잠시 후 다시 시도해주세요.');
    }
    _safeSetState(() => _aiLoading = false);
  }
}

/// =====================================================
/// Inline todo add widget (glassmorphism + AnimatedContainer)
/// =====================================================
class _TodoInlineAddWidget extends StatefulWidget {
  final bool dk;
  final Color border, textMain, textMuted;
  final Future<void> Function(String title) onAdd;

  const _TodoInlineAddWidget({
    required this.dk,
    required this.border,
    required this.textMain,
    required this.textMuted,
    required this.onAdd,
  });

  @override
  State<_TodoInlineAddWidget> createState() => _TodoInlineAddWidgetState();
}

class _TodoInlineAddWidgetState extends State<_TodoInlineAddWidget> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;

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
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await widget.onAdd(text);
    // Keep focus for consecutive inputs
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: _expanded
                ? const EdgeInsets.all(12)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: widget.dk
                  ? Colors.white.withOpacity(0.06)
                  : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _expanded
                    ? BotanicalColors.primary.withOpacity(0.3)
                    : (widget.dk
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.4)),
              ),
              boxShadow: _expanded
                  ? [
                      BoxShadow(
                          color: BotanicalColors.primary.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]
                  : null,
            ),
            child: _expanded ? _buildExpandedInput() : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return GestureDetector(
      onTap: () => _safeSetState(() {
        _expanded = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _focus.requestFocus());
      }),
      child: Row(children: [
        Icon(Icons.add_circle_outline_rounded,
            size: 20, color: BotanicalColors.primary.withOpacity(0.6)),
        const SizedBox(width: 10),
        Text('할일 추가...',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.textMuted)),
      ]),
    );
  }

  Widget _buildExpandedInput() {
    return Row(children: [
      Expanded(
          child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
            hintText: '할일을 입력하세요',
            hintStyle:
                TextStyle(color: widget.textMuted, fontSize: 14),
            isDense: true,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
        style: TextStyle(fontSize: 14, color: widget.textMain),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _submit,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: BotanicalColors.primary,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.arrow_upward_rounded,
              color: Colors.white, size: 18),
        ),
      ),
    ]);
  }
}
