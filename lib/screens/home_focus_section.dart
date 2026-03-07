part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 포커스 섹션 (TAB 1)
/// ═══════════════════════════════════════════════════
extension _HomeFocusSection on _HomeScreenState {
  // ══════════════════════════════════════════
  //  TAB 1: 포커스 (애니메이션 + 세션 진입)
  // ══════════════════════════════════════════

  Widget _focusPage() {
    final isRunning = _ft.isRunning;
    final st = isRunning ? _ft.getCurrentState() : null;
    final mc = st != null ? BotanicalColors.subjectColor(st.subject) : BotanicalColors.primary;

    return RefreshIndicator(
      color: BotanicalColors.primary,
      onRefresh: () => _load(),
      child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // 타이틀
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('포커스', style: BotanicalTypo.heading(
              size: 26, weight: FontWeight.w800, color: _textMain)),
            const SizedBox(height: 2),
            Text('깊은 집중의 시간', style: BotanicalTypo.label(
              size: 13, color: _textMuted)),
          ])),
        ]),
        const SizedBox(height: 20),

        // ── 애니메이션 + 상태 표시 ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: _dk
                ? [mc.withOpacity(0.08), mc.withOpacity(0.03)]
                : [mc.withOpacity(0.04), mc.withOpacity(0.01)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: mc.withOpacity(_dk ? 0.2 : 0.1))),
          child: Column(children: [
            // Lottie 책 애니메이션
            SizedBox(
              height: 160,
              child: Lottie.asset(
                'assets/books_focus.json',
                animate: true,
                repeat: true,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => Icon(
                  Icons.menu_book_rounded,
                  size: 80, color: mc.withOpacity(0.3)),
              ),
            ),
            const SizedBox(height: 16),

            if (isRunning && st != null) ...[
              // 진행 중 상태
              Text('${st.mode == 'study' ? '📖 집중공부' : st.mode == 'lecture' ? '🎧 강의' : '☕ 휴식'}',
                style: BotanicalTypo.label(size: 13, weight: FontWeight.w700, color: mc)),
              const SizedBox(height: 4),
              Text(st.subject, style: BotanicalTypo.heading(
                size: 20, weight: FontWeight.w800, color: _textMain)),
              const SizedBox(height: 12),
              // 타이머
              Text(st.mainTimerFormatted, style: BotanicalTypo.number(
                size: 48, weight: FontWeight.w200, color: mc)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: mc.withOpacity(_dk ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Text('순공 ${st.effectiveTimeFormatted}',
                  style: BotanicalTypo.label(size: 13, weight: FontWeight.w800, color: mc)),
              ),
              const SizedBox(height: 16),
              // 포커스존 이동 버튼
              SizedBox(width: double.infinity, height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FocusScreen()))
                    .then((_) => _load()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('포커스존 열기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mc,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                )),
            ] else ...[
              // 대기 상태
              Text('집중할 준비가 되었나요?', style: BotanicalTypo.heading(
                size: 18, weight: FontWeight.w700, color: _textMain)),
              const SizedBox(height: 6),
              Text('포커스존에서 타이머를 시작하세요', style: BotanicalTypo.label(
                size: 13, color: _textMuted)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FocusScreen()))
                    .then((_) => _load()),
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: const Text('포커스 시작', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BotanicalColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0),
                )),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // ── 오늘의 순공 요약 ──
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BotanicalDeco.card(_dk),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('${_effMin ~/ 60}', style: BotanicalTypo.number(
                size: 22, weight: FontWeight.w800, color: BotanicalColors.primary))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('오늘의 순공시간', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700, color: _textMuted)),
              const SizedBox(height: 2),
              Text('${_effMin ~/ 60}시간 ${_effMin % 60}분',
                style: BotanicalTypo.heading(size: 18, weight: FontWeight.w800, color: _textMain)),
            ])),
            // 진행도 링
            SizedBox(width: 44, height: 44,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: (_effMin / 480).clamp(0.0, 1.0),
                  strokeWidth: 3,
                  backgroundColor: _dk ? Colors.white.withOpacity(0.06) : BotanicalColors.primary.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation(BotanicalColors.primary)),
                Text('${(_effMin / 480 * 100).toInt()}%', style: BotanicalTypo.label(
                  size: 10, weight: FontWeight.w800, color: BotanicalColors.primary)),
              ])),
          ]),
        ),
        const SizedBox(height: 14),

        // ── 빠른 접근: 수동 추가 ──
        Row(children: [
          Expanded(child: _focusQuickBtn(
            icon: Icons.add_circle_outline_rounded, label: '수동 추가',
            onTap: () => _showManualAddSheet(),
          )),
        ]),
        const SizedBox(height: 20),

        // ── 포커스 기록 (날짜별) ──
        FocusRecordsWidget(dk: _dk, textMain: _textMain, textMuted: _textMuted,
          textSub: _textSub, border: _border, accent: _accent,
          onRefresh: () => _load()),
        const SizedBox(height: 40),
      ],
    ));
  }

  /// 수동 세션 추가 바텀시트
  Future<void> _showManualAddSheet() async {
    final subjects = SubjectConfig.subjects;
    if (!mounted) return;

    String selSubject = subjects.keys.first;
    int studyMin = 60, lectureMin = 0, restMin = 10;
    final dateStr = _studyDate();
    int startH = 9, startM = 0;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final dk = _dk;
        final bg = dk ? const Color(0xFF1a2332) : const Color(0xFFFCF9F3);
        final txt = dk ? Colors.white : const Color(0xFF1e293b);
        final muted = dk ? Colors.white54 : Colors.grey;
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final bottomPad = MediaQuery.of(ctx).padding.bottom;

        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: BoxDecoration(color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24, right: 24, top: 20,
                bottom: bottomInset + bottomPad + 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: muted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('수동 세션 추가', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: txt)),
                const SizedBox(height: 4),
                Text('과거 세션을 수동으로 기록합니다', style: TextStyle(
                  fontSize: 11, color: muted)),
                const SizedBox(height: 20),

                // 과목 선택
                Wrap(spacing: 8, runSpacing: 8,
                  children: subjects.entries.map((e) {
                    final sel = selSubject == e.key;
                    final c = Color(e.value.colorValue);
                    return GestureDetector(
                      onTap: () => setLocal(() => selSubject = e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.withOpacity(0.15) : (dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? c : Colors.transparent, width: 1.5)),
                        child: Text('${e.value.emoji} ${e.key}', style: TextStyle(
                          fontSize: 13, fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                          color: sel ? c : txt)),
                      ),
                    );
                  }).toList()),
                const SizedBox(height: 20),

                // 시작시간
                Row(children: [
                  Text('시작시간', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: txt)),
                  const Spacer(),
                  _manualTimeBtn(startH, (v) => setLocal(() => startH = v), 23, txt, dk),
                  Text(' : ', style: TextStyle(fontSize: 18, color: txt)),
                  _manualTimeBtn(startM, (v) => setLocal(() => startM = v), 59, txt, dk),
                ]),
                const SizedBox(height: 16),

                // 시간 입력
                _manualMinRow('📖 집중공부', studyMin,
                  (v) => setLocal(() => studyMin = v), txt, muted, dk),
                _manualMinRow('🎧 강의듣기', lectureMin,
                  (v) => setLocal(() => lectureMin = v), txt, muted, dk),
                _manualMinRow('☕ 휴식', restMin,
                  (v) => setLocal(() => restMin = v), txt, muted, dk),

                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BotanicalColors.primary.withOpacity(dk ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Text('순공시간', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: txt)),
                    const Spacer(),
                    Text('${studyMin + (lectureMin * 0.5).round()}분',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                        color: BotanicalColors.primary)),
                  ]),
                ),

                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'subject': selSubject,
                      'studyMin': studyMin,
                      'lectureMin': lectureMin,
                      'restMin': restMin,
                      'startH': startH,
                      'startM': startM,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D5F2D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('세션 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  )),
              ]),
            ),
          ),
        );
      }),
    );
    if (result == null || !mounted) return;

    final now = DateTime.now();
    final startStr = '${result['startH'].toString().padLeft(2, '0')}:${result['startM'].toString().padLeft(2, '0')}';
    final totalMin = result['studyMin'] + result['lectureMin'] + result['restMin'];
    final endDt = DateTime(now.year, now.month, now.day, result['startH'], result['startM']).add(Duration(minutes: totalMin));
    final endStr = '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';

    final cycle = FocusCycle(
      id: 'fc_manual_${now.millisecondsSinceEpoch}',
      date: dateStr,
      startTime: startStr,
      endTime: endStr,
      subject: result['subject'],
      studyMin: result['studyMin'],
      lectureMin: result['lectureMin'],
      effectiveMin: result['studyMin'] + (result['lectureMin'] * 0.5).round(),
      restMin: result['restMin'],
    );
    final fb = FirebaseService();
    await fb.saveFocusCycle(dateStr, cycle);

    // studyTimeRecords 업데이트 (순공시간 반영)
    try {
      final strs = await fb.getStudyTimeRecords();
      final existing = strs[dateStr];
      final totalMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
      await fb.updateStudyTimeRecord(dateStr, StudyTimeRecord(
        date: dateStr,
        effectiveMinutes: (existing?.effectiveMinutes ?? 0) + cycle.effectiveMin,
        totalMinutes: (existing?.totalMinutes ?? 0) + totalMin,
        studyMinutes: (existing?.studyMinutes ?? 0) + cycle.studyMin,
        lectureMinutes: (existing?.lectureMinutes ?? 0) + cycle.lectureMin,
      ));
    } catch (_) {}

    _load();
  }

  Widget _manualTimeBtn(int value, ValueChanged<int> onChange, int max, Color txt, bool dk) {
    return GestureDetector(
      onTap: () async {
        final ctrl = TextEditingController(text: value.toString().padLeft(2, '0'));
        final r = await showDialog<int>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: dk ? const Color(0xFF1e2a3a) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: SizedBox(width: 80, child: TextField(
              controller: ctrl, autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center, maxLength: 2,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: txt),
              decoration: const InputDecoration(counterText: '',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
              TextButton(onPressed: () {
                Navigator.pop(c, (int.tryParse(ctrl.text) ?? 0).clamp(0, max));
              }, child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        );
        if (r != null) onChange(r);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: dk ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10)),
        child: Text(value.toString().padLeft(2, '0'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
            color: txt, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }

  Widget _manualMinRow(String label, int value, ValueChanged<int> onChange,
      Color txt, Color muted, bool dk) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: txt))),
        const Spacer(),
        GestureDetector(
          onTap: () => onChange((value - 10).clamp(0, 600)),
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
              shape: BoxShape.circle),
            child: Icon(Icons.remove, size: 16, color: muted)),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 50, child: Text('${value}분',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: txt))),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => onChange((value + 10).clamp(0, 600)),
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
              shape: BoxShape.circle),
            child: Icon(Icons.add, size: 16, color: muted)),
        ),
      ]),
    );
  }

  Widget _focusQuickBtn({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: _textSub),
          const SizedBox(width: 8),
          Text(label, style: BotanicalTypo.label(
            size: 12, weight: FontWeight.w700, color: _textSub)),
        ]),
      ),
    );
  }

}