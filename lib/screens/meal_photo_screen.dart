import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../theme/botanical_theme.dart';
import '../services/meal_photo_service.dart';

class MealPhotoScreen extends StatefulWidget {
  const MealPhotoScreen({super.key});
  @override
  State<MealPhotoScreen> createState() => _MealPhotoScreenState();
}

class _MealPhotoScreenState extends State<MealPhotoScreen> {
  final _svc = MealPhotoService();
  List<Map<String, dynamic>> _meals = [];
  bool _loading = true;
  bool _uploading = false;
  int _todayCalories = 0;
  bool _hasApiKey = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _card => _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

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
    _safeSetState(() => _loading = true);
    try {
      _meals = await _svc.getTodayMeals();
      _todayCalories = await _svc.getTodayTotalCalories();
      _hasApiKey = await _svc.hasOpenAIKey();
    } catch (_) {}
    _safeSetState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('식사 기록', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        actions: [
          IconButton(
            icon: Icon(Icons.key_rounded, size: 20,
              color: _hasApiKey ? BotanicalColors.success : _textMuted),
            onPressed: _showApiKeyDialog,
            tooltip: 'OpenAI API 키',
          ),
        ],
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: _accent))
        : RefreshIndicator(
            color: _accent,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _calorySummaryCard(),
                const SizedBox(height: 20),
                _captureSection(),
                const SizedBox(height: 24),
                _todayMealsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
    );
  }

  // ═══ 오늘 칼로리 요약 ═══
  Widget _calorySummaryCard() {
    const target = 2000;
    final ratio = (_todayCalories / target).clamp(0.0, 1.5);
    final over = _todayCalories > target;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            (over ? Colors.red : BotanicalColors.success).withOpacity(_dk ? 0.12 : 0.06),
            _accent.withOpacity(_dk ? 0.05 : 0.02),
          ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (over ? Colors.red : BotanicalColors.success).withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('🔥', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('오늘 섭취 칼로리', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (over ? Colors.red : BotanicalColors.success).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: Text(
              over ? '초과' : '적정',
              style: BotanicalTypo.label(size: 11, weight: FontWeight.w700,
                color: over ? Colors.red : BotanicalColors.success)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$_todayCalories', style: TextStyle(
            fontSize: 36, fontWeight: FontWeight.w800, color: _textMain,
            letterSpacing: -1)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('/ $target kcal', style: BotanicalTypo.label(
              size: 13, color: _textMuted)),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
            valueColor: AlwaysStoppedAnimation(over ? Colors.red : BotanicalColors.success),
          ),
        ),
      ]),
    );
  }

  // ═══ 촬영 섹션 ═══
  Widget _captureSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF8A65).withOpacity(_dk ? 0.15 : 0.08),
            const Color(0xFFFFCC80).withOpacity(_dk ? 0.08 : 0.04),
          ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF8A65).withOpacity(0.2))),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A65).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14)),
            child: const Text('📸', style: TextStyle(fontSize: 24))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('식사 기록하기', style: BotanicalTypo.heading(size: 16, color: _textMain)),
            Text('사진 + 음식 이름 → AI 칼로리 분석',
              style: BotanicalTypo.label(size: 12, color: _textMuted)),
          ])),
        ]),
        const SizedBox(height: 16),
        if (_uploading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
              const SizedBox(width: 10),
              Text('분석 중...', style: BotanicalTypo.label(size: 13, color: _textSub)),
            ]),
          )
        else
          Row(children: [
            Expanded(child: _mealTypeBtn('breakfast', '🌅', '아침')),
            const SizedBox(width: 8),
            Expanded(child: _mealTypeBtn('lunch', '☀️', '점심')),
            const SizedBox(width: 8),
            Expanded(child: _mealTypeBtn('dinner', '🌙', '저녁')),
            const SizedBox(width: 8),
            Expanded(child: _mealTypeBtn('snack', '🍪', '간식')),
          ]),
      ]),
    );
  }

  Widget _mealTypeBtn(String type, String emoji, String label) {
    final recorded = _meals.any((m) => m['mealType'] == type);
    final color = _mealColor(type);

    return GestureDetector(
      onTap: () => _showRecordSheet(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: recorded
            ? color.withOpacity(_dk ? 0.15 : 0.08)
            : (_dk ? Colors.white.withOpacity(0.04) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: recorded ? color.withOpacity(0.3) : _border)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: BotanicalTypo.label(
            size: 11, weight: FontWeight.w600,
            color: recorded ? color : _textMain)),
          if (recorded) ...[ 
            const SizedBox(height: 2),
            Text('✓', style: BotanicalTypo.label(
              size: 10, weight: FontWeight.w800, color: color)),
          ],
        ]),
      ),
    );
  }

  // ═══ 기록 바텀시트 (사진선택 → 음식이름 → AI분석) ═══
  void _showRecordSheet(String mealType) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RecordSheet(
        mealType: mealType, dk: _dk,
        textMain: _textMain, textSub: _textSub, textMuted: _textMuted,
        card: _card, border: _border, accent: _accent,
        onSave: (result) async {
          Navigator.pop(ctx);
          await _doSave(mealType, result);
        },
      ),
    );
  }

  Future<void> _doSave(String mealType, _RecordResult result) async {
    _safeSetState(() => _uploading = true);
    try {
      String photoUrl = '';

      // 1) 사진 업로드
      if (result.photo != null) {
        photoUrl = await _svc.uploadPhoto(result.photo!) ?? '';
      }

      // 2) AI 칼로리 분석
      int? calories, protein, carbs, fat;
      String? summary;

      if (result.foodName.isNotEmpty && _hasApiKey) {
        final analysis = await _svc.analyzeCalorie(result.foodName);
        if (analysis != null) {
          calories = analysis['calories'] as int?;
          protein = analysis['protein'] as int?;
          carbs = analysis['carbs'] as int?;
          fat = analysis['fat'] as int?;
          summary = analysis['summary'] as String?;
        }
      }

      // 3) 저장
      await _svc.saveMealRecord(
        mealType: mealType,
        photoUrl: photoUrl,
        foodName: result.foodName.isNotEmpty ? result.foodName : null,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        summary: summary,
        memo: result.memo.isNotEmpty ? result.memo : null,
      );

      if (mounted) {
        final calText = calories != null ? ' (${calories}kcal)' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${MealPhotoService.mealEmoji(mealType)} '
              '${MealPhotoService.mealLabel(mealType)} 기록 완료$calText')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')));
      }
    }
    _safeSetState(() => _uploading = false);
  }

  // ═══ 오늘 식사 기록 ═══
  Widget _todayMealsSection() {
    if (_meals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BotanicalDeco.card(_dk),
        child: Column(children: [
          const Text('🍽️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('오늘 식사 기록이 없습니다',
            style: BotanicalTypo.body(size: 14, color: _textMuted)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('오늘 식사', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BotanicalDeco.badge(_accent),
            child: Text('${_meals.length}끼 · ${_todayCalories}kcal',
              style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700, color: _accent))),
        ]),
        const SizedBox(height: 14),
        ..._meals.map((m) => _mealCard(m)),
      ]),
    );
  }

  Widget _mealCard(Map<String, dynamic> meal) {
    final type = meal['mealType'] as String? ?? 'meal';
    final time = meal['time'] as String? ?? '';
    final foodName = meal['foodName'] as String?;
    final memo = meal['memo'] as String?;
    final photoUrl = meal['photoUrl'] as String? ?? '';
    final calories = meal['calories'] as int?;
    final protein = meal['protein'] as int?;
    final carbs = meal['carbs'] as int?;
    final fat = meal['fat'] as int?;
    final summary = meal['summary'] as String?;
    final mealId = meal['id'] as String? ?? '';
    final color = _mealColor(type);

    return GestureDetector(
      onLongPress: () => _showMealActions(meal),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(_dk ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.12))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // 썸네일
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
              child: photoUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(photoUrl,
                      fit: BoxFit.cover, width: 44, height: 44,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(MealPhotoService.mealEmoji(type),
                          style: const TextStyle(fontSize: 20)))))
                : Center(child: Text(MealPhotoService.mealEmoji(type),
                    style: const TextStyle(fontSize: 20)))),
            const SizedBox(width: 12),
            // 정보
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(MealPhotoService.mealLabel(type),
                  style: BotanicalTypo.body(size: 13, weight: FontWeight.w700, color: _textMain)),
                if (foodName != null) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(foodName,
                    style: BotanicalTypo.label(size: 12, color: _textSub),
                    overflow: TextOverflow.ellipsis)),
                ],
                const Spacer(),
                Text(time, style: BotanicalTypo.label(size: 11, color: _textMuted)),
              ]),
              if (memo != null && memo.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(memo, style: BotanicalTypo.label(size: 12, color: _textSub),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ])),
          ]),
          // 칼로리 + 영양소 바
          if (calories != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                _nutriBadge('🔥', '${calories}kcal', color),
                if (protein != null) _nutriBadge('P', '${protein}g', Colors.blue),
                if (carbs != null) _nutriBadge('C', '${carbs}g', Colors.orange),
                if (fat != null) _nutriBadge('F', '${fat}g', Colors.purple),
              ]),
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary, style: BotanicalTypo.label(size: 11, color: _textMuted),
                maxLines: 2),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('칼로리 미분석', style: BotanicalTypo.label(
                size: 10, color: _textMuted)),
            ),
        ]),
      ),
    );
  }

  // ═══ 식사 수정/삭제 액션시트 ═══
  void _showMealActions(Map<String, dynamic> meal) {
    final mealId = meal['id'] as String? ?? '';
    final type = meal['mealType'] as String? ?? '';
    final foodName = meal['foodName'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: _textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('${MealPhotoService.mealEmoji(type)} ${foodName ?? MealPhotoService.mealLabel(type)}',
              style: BotanicalTypo.heading(size: 18, color: _textMain)),
            const SizedBox(height: 20),

            // 수정
            _actionTile(
              icon: Icons.edit_rounded, label: '수정',
              color: BotanicalColors.info,
              onTap: () {
                Navigator.pop(ctx);
                _showEditSheet(meal);
              }),
            const SizedBox(height: 10),

            // 삭제
            _actionTile(
              icon: Icons.delete_rounded, label: '삭제',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text('삭제 확인', style: BotanicalTypo.heading(size: 16)),
                    content: Text('이 식사 기록을 삭제할까요?',
                      style: BotanicalTypo.body(size: 14, color: _textSub)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false),
                        child: Text('취소', style: TextStyle(color: _textMuted))),
                      TextButton(onPressed: () => Navigator.pop(c, true),
                        child: const Text('삭제', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _svc.deleteMealRecord(mealId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🗑️ 삭제 완료')));
                  }
                  _load();
                }
              }),
          ]),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon, required String label,
    required Color color, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(_dk ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15))),
        child: Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 14),
          Text(label, style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w600, color: _textMain)),
        ]),
      ),
    );
  }

  // ═══ 식사 수정 시트 ═══
  void _showEditSheet(Map<String, dynamic> meal) {
    final mealId = meal['id'] as String? ?? '';
    final type = meal['mealType'] as String? ?? 'meal';
    final foodCtrl = TextEditingController(text: meal['foodName'] as String? ?? '');
    final memoCtrl = TextEditingController(text: meal['memo'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: sheetBottomPad(ctx, extra: 24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: _textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('${MealPhotoService.mealEmoji(type)} 수정',
              style: BotanicalTypo.heading(size: 18, color: _textMain)),
            const SizedBox(height: 20),

            TextField(
              controller: foodCtrl,
              decoration: InputDecoration(
                labelText: '음식 이름',
                prefixIcon: const Icon(Icons.restaurant_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memoCtrl,
              decoration: InputDecoration(
                labelText: '메모',
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mealColor(type),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
                onPressed: () async {
                  Navigator.pop(ctx);
                  _safeSetState(() => _uploading = true);

                  final newFood = foodCtrl.text.trim();
                  int? cal, pro, carb, fVal;
                  String? sum;

                  // 음식이름 바뀌었으면 재분석
                  if (newFood.isNotEmpty && newFood != (meal['foodName'] ?? '') && _hasApiKey) {
                    final a = await _svc.analyzeCalorie(newFood);
                    if (a != null) {
                      cal = a['calories'] as int?;
                      pro = a['protein'] as int?;
                      carb = a['carbs'] as int?;
                      fVal = a['fat'] as int?;
                      sum = a['summary'] as String?;
                    }
                  }

                  await _svc.updateMealRecord(
                    mealId: mealId, mealType: type,
                    foodName: newFood.isNotEmpty ? newFood : null,
                    calories: cal, protein: pro, carbs: carb, fat: fVal,
                    summary: sum,
                    memo: memoCtrl.text.trim().isNotEmpty ? memoCtrl.text.trim() : null,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✏️ 수정 완료')));
                  }
                  _safeSetState(() => _uploading = false);
                  _load();
                },
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text('수정 저장', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _nutriBadge(String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w800, color: color.withOpacity(0.7))),
        const SizedBox(height: 2),
        Text(value, style: BotanicalTypo.label(
          size: 11, weight: FontWeight.w700, color: _textMain)),
      ]),
    );
  }

  // ═══ API 키 설정 ═══
  void _showApiKeyDialog() async {
    final controller = TextEditingController();
    final current = await _svc.getOpenAIKey();
    if (current != null) controller.text = current;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('🤖 ', style: TextStyle(fontSize: 20)),
          Text('AI 칼로리 분석', style: BotanicalTypo.heading(size: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('OpenAI API 키를 입력하면\nAI가 음식 칼로리를 자동 분석합니다.',
            style: BotanicalTypo.label(size: 13, color: _textSub),
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'sk-...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                await _svc.setOpenAIKey(key);
                _safeSetState(() => _hasApiKey = key.startsWith('sk-'));
                if (mounted) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ API 키 저장 완료')));
                }
              }
            },
            child: const Text('저장')),
        ],
      ),
    );
  }

  // ═══ 유틸 ═══
  Color _mealColor(String type) {
    switch (type) {
      case 'breakfast': return const Color(0xFFFF8A65);
      case 'lunch': return const Color(0xFFFFA726);
      case 'dinner': return const Color(0xFF7E57C2);
      case 'snack': return const Color(0xFF66BB6A);
      default: return _textMuted;
    }
  }
}

// ═══════════════════════════════════════════
//  기록 바텀시트 (사진 + 음식이름 + 메모)
// ═══════════════════════════════════════════

class _RecordResult {
  final dynamic photo; // XFile?
  final String foodName;
  final String memo;
  _RecordResult({this.photo, required this.foodName, required this.memo});
}

class _RecordSheet extends StatefulWidget {
  final String mealType;
  final bool dk;
  final Color textMain, textSub, textMuted, card, border, accent;
  final Future<void> Function(_RecordResult result) onSave;

  const _RecordSheet({
    required this.mealType, required this.dk,
    required this.textMain, required this.textSub,
    required this.textMuted, required this.card,
    required this.border, required this.accent,
    required this.onSave,
  });

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _svc = MealPhotoService();
  final _foodController = TextEditingController();
  final _memoController = TextEditingController();
  dynamic _photo; // XFile?
  bool _hasPhoto = false;

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
    _foodController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: sheetBottomPad(context, extra: 24)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: widget.textMuted, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text(
          '${MealPhotoService.mealEmoji(widget.mealType)} '
          '${MealPhotoService.mealLabel(widget.mealType)} 기록',
          style: BotanicalTypo.heading(size: 18, color: widget.textMain)),
        const SizedBox(height: 20),

        // 사진 선택 버튼
        Row(children: [
          Expanded(child: _photoBtn(
            Icons.camera_alt_rounded, '카메라',
            const Color(0xFFFF8A65),
            () async {
              final p = await _svc.capturePhoto();
              if (p != null) _safeSetState(() { _photo = p; _hasPhoto = true; });
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _photoBtn(
            Icons.photo_library_rounded, '갤러리',
            BotanicalColors.info,
            () async {
              final p = await _svc.pickFromGallery();
              if (p != null) _safeSetState(() { _photo = p; _hasPhoto = true; });
            },
          )),
        ]),
        if (_hasPhoto)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, size: 16, color: BotanicalColors.success),
              const SizedBox(width: 6),
              Text('사진 선택됨', style: BotanicalTypo.label(
                size: 12, weight: FontWeight.w600, color: BotanicalColors.success)),
            ]),
          ),
        const SizedBox(height: 16),

        // 음식 이름 (필수 - AI 분석용)
        TextField(
          controller: _foodController,
          decoration: InputDecoration(
            labelText: '음식 이름 *',
            hintText: '예: 김치찌개, 삼겹살, 라면...',
            prefixIcon: const Icon(Icons.restaurant_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        ),
        const SizedBox(height: 12),

        // 메모 (선택)
        TextField(
          controller: _memoController,
          decoration: InputDecoration(
            labelText: '메모 (선택)',
            hintText: '반찬, 양, 특이사항 등',
            prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        ),
        const SizedBox(height: 20),

        // 저장 버튼
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _mealColor(widget.mealType),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0),
            onPressed: () {
              widget.onSave(_RecordResult(
                photo: _photo,
                foodName: _foodController.text.trim(),
                memo: _memoController.text.trim(),
              ));
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.save_rounded, size: 20),
              const SizedBox(width: 8),
              const Text('기록 저장 + AI 분석', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _photoBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(widget.dk ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(label, style: BotanicalTypo.body(
            size: 13, weight: FontWeight.w600, color: widget.textMain)),
        ]),
      ),
    );
  }

  Color _mealColor(String type) {
    switch (type) {
      case 'breakfast': return const Color(0xFFFF8A65);
      case 'lunch': return const Color(0xFFFFA726);
      case 'dinner': return const Color(0xFF7E57C2);
      case 'snack': return const Color(0xFF66BB6A);
      default: return widget.textMuted;
    }
  }
}