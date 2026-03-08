import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';

/// F2: 메모 CRUD + 리마인더 화면
class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});
  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  List<Memo> _memos = [];
  bool _showCompleted = false;
  bool _loading = true;
  StreamSubscription? _sub;
  int _retryDelay = 5;

  @override
  void initState() {
    super.initState();
    _startStream();
    _loadAll();
  }

  @override
  void dispose() {
    _sub?.cancel();
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

  void _startStream() {
    _sub?.cancel();
    _sub = FirebaseService().watchMemos().listen((memos) {
      _retryDelay = 5;
      if (mounted) _safeSetState(() { _memos = memos; _loading = false; });
    }, onError: (e) {
      debugPrint('[Memo] stream error: $e — retry ${_retryDelay}s');
      if (mounted) {
        Future.delayed(Duration(seconds: _retryDelay), () {
          _retryDelay = (_retryDelay * 2).clamp(5, 60);
          if (mounted) _startStream();
        });
      }
    });
  }

  Future<void> _loadAll() async {
    final memos = await FirebaseService().getMemos(includeCompleted: _showCompleted);
    if (mounted) _safeSetState(() { _memos = memos; _loading = false; });
  }

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('메모', style: BotanicalTypo.heading(size: 18,
          color: _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain)),
        actions: [
          IconButton(
            icon: Icon(_showCompleted ? Icons.visibility_off : Icons.visibility,
              size: 20, color: _textMuted),
            tooltip: _showCompleted ? '완료 숨기기' : '완료 보기',
            onPressed: () {
              _safeSetState(() => _showCompleted = !_showCompleted);
              _loadAll();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: BotanicalColors.primary,
        foregroundColor: Colors.white,
        onPressed: _addMemo,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _memos.isEmpty
              ? _emptyState()
              : _memoList(),
    );
  }

  Widget _emptyState() {
    return Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('💡', style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('메모가 없습니다', style: BotanicalTypo.body(
          size: 15, weight: FontWeight.w600, color: _textMuted)),
        const SizedBox(height: 4),
        Text('+ 버튼을 눌러 메모를 추가하세요', style: BotanicalTypo.label(
          size: 12, color: _textMuted)),
      ],
    ));
  }

  Widget _memoList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _memos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _memoTile(_memos[i]),
    );
  }

  Widget _memoTile(Memo memo) {
    final catEmoji = Memo.categoryEmoji(memo.category);
    final hasReminder = memo.reminderAt != null;
    final isOverdue = hasReminder && memo.reminderAt!.isBefore(DateTime.now());
    final color = memo.pinned ? BotanicalColors.gold
        : memo.category == 'important' ? BotanicalColors.error
        : memo.category == 'study' ? BotanicalColors.primary
        : _textSub;

    return Dismissible(
      key: Key(memo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: BotanicalColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16)),
        child: Icon(Icons.delete_rounded, color: BotanicalColors.error),
      ),
      confirmDismiss: (_) => _confirmDelete(memo),
      child: GestureDetector(
        onTap: () => _editMemo(memo),
        onLongPress: () => _showMemoActions(memo),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: memo.completed
              ? (_dk ? Colors.white.withOpacity(0.02) : Colors.grey.withOpacity(0.04))
              : (_dk ? BotanicalColors.cardDark : BotanicalColors.cardLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: memo.pinned
                ? BotanicalColors.gold.withOpacity(0.3)
                : (_dk ? BotanicalColors.borderDark : BotanicalColors.borderLight),
              width: memo.pinned ? 1.2 : 0.6),
            boxShadow: memo.completed ? null : [
              BoxShadow(
                color: _dk ? Colors.black.withOpacity(0.15) : color.withOpacity(0.05),
                blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 완료 체크
            GestureDetector(
              onTap: () => _toggleComplete(memo),
              child: Container(
                width: 24, height: 24,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: memo.completed ? color.withOpacity(0.15) : Colors.transparent,
                  border: Border.all(color: color.withOpacity(0.4), width: 1.5)),
                child: memo.completed
                  ? Icon(Icons.check_rounded, size: 14, color: color)
                  : null,
              ),
            ),
            // 내용
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(catEmoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  if (memo.pinned) ...[
                    Icon(Icons.push_pin_rounded, size: 11,
                      color: BotanicalColors.gold),
                    const SizedBox(width: 4),
                  ],
                  Expanded(child: Text(
                    memo.content,
                    style: BotanicalTypo.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: memo.completed ? _textMuted : _textMain),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text(DateFormat('M/d HH:mm').format(memo.createdAt),
                    style: BotanicalTypo.label(size: 10, color: _textMuted)),
                  if (hasReminder) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOverdue
                          ? BotanicalColors.error.withOpacity(0.1)
                          : BotanicalColors.info.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.alarm_rounded, size: 10,
                          color: isOverdue ? BotanicalColors.error : BotanicalColors.info),
                        const SizedBox(width: 3),
                        Text(DateFormat('M/d HH:mm').format(memo.reminderAt!),
                          style: BotanicalTypo.label(size: 9, weight: FontWeight.w700,
                            color: isOverdue ? BotanicalColors.error : BotanicalColors.info)),
                      ]),
                    ),
                  ],
                ]),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  // ── CRUD Actions ──

  Future<void> _addMemo() async {
    final result = await _showMemoEditor(null);
    if (result == null) return;
    final memo = Memo(
      id: 'memo_${DateTime.now().millisecondsSinceEpoch}',
      content: result['content'] as String,
      createdAt: DateTime.now(),
      reminderAt: result['reminderAt'] as DateTime?,
      category: result['category'] as String?,
      pinned: result['pinned'] as bool? ?? false,
    );
    await FirebaseService().saveMemo(memo);
    _loadAll();
  }

  Future<void> _editMemo(Memo memo) async {
    final result = await _showMemoEditor(memo);
    if (result == null) return;
    final updated = memo.copyWith(
      content: result['content'] as String,
      reminderAt: result['reminderAt'] as DateTime?,
      category: result['category'] as String?,
      pinned: result['pinned'] as bool? ?? memo.pinned,
      clearReminder: result['reminderAt'] == null,
    );
    await FirebaseService().saveMemo(updated);
    _loadAll();
  }

  Future<void> _toggleComplete(Memo memo) async {
    final updated = memo.copyWith(completed: !memo.completed);
    await FirebaseService().saveMemo(updated);
    _loadAll();
  }

  Future<bool> _confirmDelete(Memo memo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('메모 삭제', style: BotanicalTypo.heading(size: 16)),
        content: Text('이 메모를 삭제할까요?', style: BotanicalTypo.body(size: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseService().deleteMemo(memo.id);
      _loadAll();
      return true;
    }
    return false;
  }

  Future<void> _showMemoActions(Memo memo) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _dk ? BotanicalColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _actionTile(
            icon: memo.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            label: memo.pinned ? '고정 해제' : '고정',
            onTap: () async {
              Navigator.pop(c);
              await FirebaseService().saveMemo(memo.copyWith(pinned: !memo.pinned));
              _loadAll();
            },
          ),
          _actionTile(
            icon: memo.completed ? Icons.undo : Icons.check_circle_outline,
            label: memo.completed ? '미완료로 변경' : '완료',
            onTap: () async {
              Navigator.pop(c);
              _toggleComplete(memo);
            },
          ),
          _actionTile(
            icon: Icons.delete_outline,
            label: '삭제',
            color: BotanicalColors.error,
            onTap: () async {
              Navigator.pop(c);
              _confirmDelete(memo);
            },
          ),
        ]),
      ),
    );
  }

  Widget _actionTile({required IconData icon, required String label,
      Color? color, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: color ?? _textMain),
      title: Text(label, style: BotanicalTypo.body(
        size: 15, weight: FontWeight.w600, color: color ?? _textMain)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ── Memo Editor Dialog ──

  Future<Map<String, dynamic>?> _showMemoEditor(Memo? existing) async {
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    String? selectedCat = existing?.category;
    DateTime? reminderAt = existing?.reminderAt;
    bool pinned = existing?.pinned ?? false;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(builder: (ctx, setBS) {
        return Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: sheetBottomPad(ctx, extra: 24)),
          decoration: BoxDecoration(
            color: _dk ? const Color(0xFF1a2332) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 핸들
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: _textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),

            Text(existing == null ? '새 메모' : '메모 수정',
              style: BotanicalTypo.heading(size: 16,
                color: _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain)),
            const SizedBox(height: 16),

            // 내용
            TextField(
              controller: contentCtrl,
              autofocus: existing == null,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '메모 내용...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: _dk ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 14),

            // 카테고리 칩
            Row(children: [
              Text('카테고리', style: BotanicalTypo.label(size: 11, color: _textMuted)),
              const Spacer(),
              for (final cat in [null, 'study', 'important', 'daily'])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => setBS(() => selectedCat = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: selectedCat == cat
                          ? BotanicalColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selectedCat == cat
                            ? BotanicalColors.primary
                            : _textMuted.withOpacity(0.2))),
                      child: Text(
                        '${Memo.categoryEmoji(cat)} ${Memo.categoryLabel(cat)}',
                        style: BotanicalTypo.label(size: 10,
                          weight: selectedCat == cat ? FontWeight.w800 : FontWeight.w600,
                          color: selectedCat == cat ? BotanicalColors.primary : _textMuted)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),

            // 리마인더 + 고정
            Row(children: [
              // 리마인더
              Expanded(child: GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: reminderAt ?? DateTime.now().add(const Duration(hours: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  if (!ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(
                      reminderAt ?? DateTime.now().add(const Duration(hours: 1))),
                  );
                  if (time == null) return;
                  setBS(() {
                    reminderAt = DateTime(date.year, date.month, date.day,
                      time.hour, time.minute);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: reminderAt != null
                      ? BotanicalColors.info.withOpacity(0.08)
                      : (_dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: reminderAt != null
                      ? BotanicalColors.info.withOpacity(0.3)
                      : _textMuted.withOpacity(0.15))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.alarm_rounded, size: 16,
                      color: reminderAt != null ? BotanicalColors.info : _textMuted),
                    const SizedBox(width: 6),
                    Text(reminderAt != null
                      ? DateFormat('M/d HH:mm').format(reminderAt!)
                      : '리마인더',
                      style: BotanicalTypo.label(size: 11,
                        color: reminderAt != null ? BotanicalColors.info : _textMuted)),
                    if (reminderAt != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setBS(() => reminderAt = null),
                        child: Icon(Icons.close, size: 14, color: BotanicalColors.info)),
                    ],
                  ]),
                ),
              )),
              const SizedBox(width: 10),
              // 고정 토글
              GestureDetector(
                onTap: () => setBS(() => pinned = !pinned),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: pinned
                      ? BotanicalColors.gold.withOpacity(0.1)
                      : (_dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pinned
                      ? BotanicalColors.gold.withOpacity(0.3)
                      : _textMuted.withOpacity(0.15))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 16,
                      color: pinned ? BotanicalColors.gold : _textMuted),
                    const SizedBox(width: 4),
                    Text('고정', style: BotanicalTypo.label(size: 11,
                      color: pinned ? BotanicalColors.gold : _textMuted)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // 저장 버튼
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (contentCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx, {
                    'content': contentCtrl.text.trim(),
                    'category': selectedCat,
                    'reminderAt': reminderAt,
                    'pinned': pinned,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: BotanicalColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
                child: Text(existing == null ? '추가' : '저장',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      }),
    );
  }
}
