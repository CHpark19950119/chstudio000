part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 포커스 섹션 (Full Setup + Records)
/// ═══════════════════════════════════════════════════
extension _HomeFocusSection on _HomeScreenState {

  void _pushFocusScreen() {
    if (_focusScreenOpen) return;
    _focusScreenOpen = true;
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => const FocusScreen()))
      .then((_) { _focusScreenOpen = false; _load(); _loadFocusRecords(); });
  }

  Future<void> _loadFocusRecords() async {
    _safeSetState(() => _focusRecordsLoading = true);
    try {
      final w = await _ft.getWeeklyStudyMinutes();
      await _ft.refreshTodaySessions();
      _safeSetState(() {
        _focusWeekly = w;
        _focusSessions = _ft.todaySessions;
        _focusRecordsLoading = false;
      });
    } catch (_) {
      _safeSetState(() => _focusRecordsLoading = false);
    }
  }

  Widget _focusPage() {
    // Auto-start cradle when focus tab is shown (so it's ready when session starts)
    if (_cradle.isCalibrated && !_cradle.isEnabled) {
      _cradle.start();
    }
    final isRunning = _ft.isRunning;
    final dk = _dk;
    _focusSessions = _ft.todaySessions;
    final sc = BotanicalColors.subjectColor(_focusSubj);
    final goalMin = 480;
    final pct = (_ft.todayStudyMinutes / goalMin).clamp(0.0, 1.0);
    final totalEff = _focusSessions.fold<int>(0, (s, c) => s + c.effectiveMin);

    // If running → auto-enter FocusScreen immersive (no intermediate card)
    if (isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ft.isRunning) _pushFocusScreen();
      });
      // Minimal placeholder while transition happens
      final mc = BotanicalColors.subjectColor(_ft.getCurrentState().subject);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 32, height: 32, child: CircularProgressIndicator(
          strokeWidth: 2, color: mc)),
        const SizedBox(height: 12),
        Text('포커스 진입 중...', style: TextStyle(
          fontSize: 13, color: _textMuted)),
      ]));
    }

    // Setup view (not running)
    return RefreshIndicator(
      onRefresh: () async { await _load(); await _loadFocusRecords(); },
      color: sc,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          // ── Header ──
          Row(children: [
            Text('포커스', style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: _textMain)),
            const Spacer(),
            GestureDetector(
              onTap: () => _manageSubjectsSheet(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _textMuted.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.tune_rounded, size: 18, color: _textMuted),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Hero time ──
          Center(child: ShaderMask(
            shaderCallback: (r) => LinearGradient(
              colors: [sc, sc.withOpacity(0.4), dk ? Colors.white54 : Colors.black38],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ).createShader(r),
            child: Text(
              _ft.todayStudyMinutes >= 60
                ? '${_ft.todayStudyMinutes ~/ 60}h ${(_ft.todayStudyMinutes % 60).toString().padLeft(2, '0')}m'
                : '${_ft.todayStudyMinutes}m',
              style: const TextStyle(
                fontSize: 56, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: -3, height: 1.0,
                fontFeatures: [FontFeature.tabularFigures()]),
            ),
          )),
          const SizedBox(height: 10),
          Center(child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sc.withOpacity(dk ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(10)),
                child: Text('${_ft.todaySessionCount}세션', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: sc,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 8),
              Text('순공시간', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: _textMuted)),
            ],
          )),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(height: 3, child: LinearProgressIndicator(
              value: pct,
              backgroundColor: dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
              valueColor: AlwaysStoppedAnimation(sc.withOpacity(0.60)),
            )),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${(pct * 100).toInt()}% of 8h', style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: _textMuted.withOpacity(0.45),
              fontFeatures: const [FontFeature.tabularFigures()]))),
          const SizedBox(height: 28),

          // ── Subject ──
          _fLabel('SUBJECT'),
          const SizedBox(height: 10),
          SizedBox(height: 38, child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: SubjectConfig.subjects.entries.map((e) {
              final sel = _focusSubj == e.key;
              final c = BotanicalColors.subjectColor(e.key);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _focusSubj = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? c.withOpacity(dk ? 0.18 : 0.10) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? c.withOpacity(0.45) : _textMuted.withOpacity(0.12),
                        width: sel ? 1.5 : 1),
                      boxShadow: sel ? [BoxShadow(color: c.withOpacity(0.10), blurRadius: 10)] : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(e.key, style: TextStyle(
                        fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? c : _textSub)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          )),
          const SizedBox(height: 24),

          // ── Mode ──
          _fLabel('MODE'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _fModeChip('📖', '집중', '순공 100%', 'study', sc)),
            const SizedBox(width: 10),
            Expanded(child: _fModeChip('🎧', '강의', '순공 50%', 'lecture', sc)),
          ]),
          const SizedBox(height: 20),

          // ── Cradle ──
          _fCradleCard(),
          const SizedBox(height: 28),

          // ── Start → 바로 이머시브 진입 ──
          GestureDetector(
            onTap: () async {
              // 세션 시작 후 바로 FocusScreen 이머시브로 진입
              await _ft.startSession(subject: _focusSubj, mode: _focusMode);
              if (mounted) _pushFocusScreen();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [sc.withOpacity(dk ? 0.18 : 0.12), sc.withOpacity(dk ? 0.08 : 0.04)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: sc.withOpacity(0.25)),
                    boxShadow: [BoxShadow(color: sc.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 34, height: 34,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: sc.withOpacity(0.22),
                        boxShadow: [BoxShadow(color: sc.withOpacity(0.15), blurRadius: 12)]),
                      child: Icon(Icons.play_arrow_rounded, size: 22, color: sc)),
                    const SizedBox(width: 10),
                    Text('시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: sc, letterSpacing: 0.5)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),

          // ── Records divider ──
          Container(height: 1,
            color: dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04)),
          const SizedBox(height: 24),

          // ── Today summary ──
          _fFrostCard(
            borderColor: sc.withOpacity(0.08),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [sc, sc.withOpacity(0.45)],
                ).createShader(r),
                child: Text(_fFmtMin(totalEff), style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white,
                  letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 8),
              Text('순공', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: sc.withOpacity(0.5))),
              const Spacer(),
              _fMiniStat('📖', _focusSessions.fold<int>(0, (s, c) => s + c.studyMin)),
              const SizedBox(width: 6),
              _fMiniStat('🎧', _focusSessions.fold<int>(0, (s, c) => s + c.lectureMin)),
              const SizedBox(width: 6),
              _fMiniStat('☕', _focusSessions.fold<int>(0, (s, c) => s + c.restMin)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Sessions ──
          Row(children: [
            _fLabel('TODAY'),
            const Spacer(),
            Text('${_focusSessions.length}세션', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: _textMuted,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 10),

          if (_focusRecordsLoading)
            const Padding(padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_focusSessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hourglass_empty_rounded, size: 36, color: _textMuted.withOpacity(0.18)),
                const SizedBox(height: 10),
                Text('아직 기록이 없어요', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: _textMuted.withOpacity(0.4))),
              ])),
            )
          else
            ..._focusSessions.reversed.toList().asMap().entries.map(
                (e) => _fSessionTile(e.value, _focusSessions.length - e.key)),

          // ── Manual add ──
          const SizedBox(height: 10),
          _focusQuickBtn(
            icon: Icons.add_circle_outline_rounded, label: '수동 추가',
            onTap: () => _showManualAddSheet(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _fLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(t, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w800,
      color: _textMuted.withOpacity(0.55), letterSpacing: 2.5)),
  );

  Widget _fFrostCard({required Widget child, Color? borderColor}) {
    final dk = _dk;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dk ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor ?? (dk ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.04)))),
          child: child,
        ),
      ),
    );
  }

  Widget _fModeChip(String emoji, String label, String desc, String m, Color accent) {
    final sel = _focusMode == m;
    final dk = _dk;
    final c = m == 'study' ? const Color(0xFF6366F1) : BotanicalColors.subjectData;
    return GestureDetector(
      onTap: () => setState(() => _focusMode = m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sel ? 14 : 8, sigmaY: sel ? 14 : 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(dk ? 0.10 : 0.05)
                  : (dk ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.65)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel ? c.withOpacity(0.35)
                    : (dk ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.04)))),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: sel ? c : _textMain)),
                Text(desc, style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w500, color: _textMuted)),
              ]),
              const Spacer(),
              if (sel) Container(width: 7, height: 7, decoration: BoxDecoration(
                shape: BoxShape.circle, color: c,
                boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 6)])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _fCradleCard() {
    final cal = _cradle.isCalibrated;
    final en = _cradle.isEnabled;
    final on = _cradle.isOnCradle;
    final dk = _dk;

    if (!cal) {
      return _fFrostCard(
        borderColor: Colors.orange.withOpacity(0.15),
        child: Row(children: [
          const Text('📐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('거치대를 설정하세요', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text('각도를 등록하면 자동 감지됩니다', style: TextStyle(
              fontSize: 10, color: _textMuted)),
          ])),
          GestureDetector(
            onTap: () => _showCradleCal(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.25))),
              child: const Text('거치대 등록', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange)),
            ),
          ),
        ]),
      );
    }

    final statusColor = on ? const Color(0xFF10B981) : (en ? _textMuted.withOpacity(0.6) : _textMuted.withOpacity(0.4));
    final statusMsg = on ? '거치 감지됨' : (en ? '대기 중' : '감지 OFF');

    return _fFrostCard(
      borderColor: statusColor.withOpacity(0.12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(on ? '✅' : '📐', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('거치대 등록됨', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
              if (_cradle.isChargingCalibrated) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5)),
                  child: const Text('🔌', style: TextStyle(fontSize: 10))),
              ],
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(
                shape: BoxShape.circle, color: statusColor,
                boxShadow: on ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6)] : null)),
              const SizedBox(width: 6),
              Text(statusMsg, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
              const SizedBox(width: 8),
              Text('현재 ${_cradle.lastAngle.toStringAsFixed(0)}°', style: TextStyle(
                fontSize: 10, color: _textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ])),
          GestureDetector(
            onTap: () => _showCradleCal(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _textMuted.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8)),
              child: Text('재등록', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _textMuted)),
            ),
          ),
        ]),
        if (!en) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async { await _cradle.setEnabled(true); _safeSetState(() {}); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.15))),
              child: const Center(child: Text('감지 켜기', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981)))),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _fStartButton(Color sc) {
    return GestureDetector(
      onTap: () async {
        await _ft.startSession(subject: _focusSubj, mode: _focusMode);
        if (mounted) {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FocusScreen()))
            .then((_) { _load(); _loadFocusRecords(); });
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  sc.withOpacity(_dk ? 0.18 : 0.12),
                  sc.withOpacity(_dk ? 0.08 : 0.04),
                ],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: sc.withOpacity(0.25)),
              boxShadow: [
                BoxShadow(color: sc.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sc.withOpacity(0.22),
                  boxShadow: [BoxShadow(color: sc.withOpacity(0.15), blurRadius: 12)]),
                child: Icon(Icons.play_arrow_rounded, size: 22, color: sc),
              ),
              const SizedBox(width: 10),
              Text('시작', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: sc, letterSpacing: 0.5)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _fMiniStat(String emoji, int min) {
    final dk = _dk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(7)),
      child: Text('$emoji ${min}m', style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700, color: _textSub,
        fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  Widget _fSessionTile(FocusCycle c, int idx) {
    final sc = BotanicalColors.subjectColor(c.subject);
    final dk = _dk;
    return GestureDetector(
      onLongPress: () => _fConfirmDelete(c),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(child: Row(children: [
          Container(width: 3, decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [sc, sc.withOpacity(0.2)]),
            borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: _fFrostCard(
            borderColor: sc.withOpacity(0.06),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sc.withOpacity(dk ? 0.12 : 0.06),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('${SubjectConfig.subjects[c.subject]?.emoji ?? '📚'} ${c.subject}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sc)),
                  ),
                  const Spacer(),
                  Text('#$idx', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                    color: _textMuted.withOpacity(0.3), fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 5),
                Text('${_fFmtTime(c.startTime)} → ${c.endTime != null ? _fFmtTime(c.endTime) : '...'}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _textSub,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 3),
                Text('공부 ${c.studyMin}m · 강의 ${c.lectureMin}m · 휴식 ${c.restMin}m',
                  style: TextStyle(fontSize: 9, color: _textMuted)),
                if (c.segments.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  ClipRRect(borderRadius: BorderRadius.circular(2),
                    child: SizedBox(height: 3, child: Row(
                      children: c.segments.map((seg) {
                        final segC = seg.mode == 'rest' ? Colors.orange
                            : seg.mode == 'lecture' ? BotanicalColors.subjectData : sc;
                        return Expanded(
                          flex: seg.durationMin.clamp(1, 999),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.5),
                            color: segC.withOpacity(dk ? 0.45 : 0.30)));
                      }).toList()))),
                ],
              ])),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fFmtMin(c.effectiveMin), style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: sc,
                  letterSpacing: -0.5, fontFeatures: const [FontFeature.tabularFigures()])),
                Text('순공', style: TextStyle(
                  fontSize: 8, fontWeight: FontWeight.w600, color: sc.withOpacity(0.45))),
              ]),
            ]),
          )),
        ])),
      ),
    );
  }

  void _fConfirmDelete(FocusCycle c) {
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: _dk ? const Color(0xFF18181E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('삭제할까요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textMain)),
      content: Text(
        '${c.subject} · ${_fFmtTime(c.startTime)}~${c.endTime != null ? _fFmtTime(c.endTime) : '...'} · 순공 ${c.effectiveMin}분',
        style: TextStyle(fontSize: 12, color: _textSub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: Text('취소', style: TextStyle(color: _textMuted))),
        TextButton(onPressed: () async {
          Navigator.pop(dCtx);
          await _ft.deleteFocusCycle(c.date, c.id);
          _safeSetState(() => _focusSessions = _ft.todaySessions);
        }, child: const Text('삭제', style: TextStyle(
          color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _showCradleCal() {
    final dk = _dk;
    bool calibrating = false;
    bool done = false;
    String calType = 'normal';
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setBS) {
        return SafeArea(child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: _textMuted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('거치대 각도 캘리브레이션', style: BotanicalTypo.heading(size: 17, color: _textMain)),
            const SizedBox(height: 6),
            Text('거치대에 올려놓고 시작 — 이 각도에서만 활성화됩니다', style: TextStyle(fontSize: 12, color: _textMuted)),
            const SizedBox(height: 16),
            // ── 모드 선택: 일반 / 충전 ──
            if (!calibrating && !done) ...[
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setBS(() => calType = 'normal'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: calType == 'normal' ? BotanicalColors.primary.withOpacity(0.12) : _textMuted.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: calType == 'normal' ? BotanicalColors.primary.withOpacity(0.35) : Colors.transparent)),
                    child: Column(children: [
                      const Text('📐', style: TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text('일반', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: calType == 'normal' ? BotanicalColors.primary : _textMuted)),
                      Text(_cradle.isCalibrated ? '등록됨' : '미등록', style: TextStyle(fontSize: 9,
                        color: _cradle.isCalibrated ? const Color(0xFF10B981) : _textMuted.withOpacity(0.5))),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => setBS(() => calType = 'charging'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: calType == 'charging' ? Colors.orange.withOpacity(0.12) : _textMuted.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: calType == 'charging' ? Colors.orange.withOpacity(0.35) : Colors.transparent)),
                    child: Column(children: [
                      const Text('🔌', style: TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text('충전용', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: calType == 'charging' ? Colors.orange : _textMuted)),
                      Text(_cradle.isChargingCalibrated ? '등록됨' : '미등록', style: TextStyle(fontSize: 9,
                        color: _cradle.isChargingCalibrated ? const Color(0xFF10B981) : _textMuted.withOpacity(0.5))),
                    ]),
                  ),
                )),
              ]),
              const SizedBox(height: 16),
            ],
            if (done) ...[
              const Text('✅', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(calType == 'charging' ? '충전용 등록 완료!' : '등록 완료!',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
              const SizedBox(height: 6),
              Text('기준 각도가 저장되었습니다', style: TextStyle(fontSize: 12, color: _textMuted)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _safeSetState(() {}); },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('닫기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
            ] else if (calibrating) ...[
              const SizedBox(height: 8),
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 16),
              Text('측정 중... 폰을 움직이지 마세요', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _textMain)),
              const SizedBox(height: 6),
              Text(calType == 'charging' ? '충전 상태 각도를 측정합니다 (5초)' : '5초간 가속도계 데이터를 수집합니다',
                style: TextStyle(fontSize: 11, color: _textMuted)),
              const SizedBox(height: 24),
            ] else ...[
              Icon(calType == 'charging' ? Icons.battery_charging_full_rounded : Icons.phone_android_rounded,
                size: 48, color: _textMuted.withOpacity(0.5)),
              const SizedBox(height: 12),
              Text(calType == 'charging'
                ? '충전 케이블을 꽂은 상태로\n거치대에 올려놓고 아래 버튼을 누르세요'
                : '폰을 거치대에 올려놓고\n아래 버튼을 누르세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _textSub, height: 1.5)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                onPressed: () async {
                  setBS(() => calibrating = true);
                  if (calType == 'charging') {
                    await _cradle.calibrateCharging();
                  } else {
                    await _cradle.calibrate();
                  }
                  await _cradle.setEnabled(true);
                  setBS(() { calibrating = false; done = true; });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: calType == 'charging' ? Colors.orange : BotanicalColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('측정 시작', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
            ],
            const SizedBox(height: 14),
          ]),
        ));
      }));
  }

  void _manageSubjectsSheet() {
    final dk = _dk;
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setBS) {
        final subjects = SubjectConfig.subjects;
        return SafeArea(child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: _textMuted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Row(children: [
              Text('과목 관리', style: BotanicalTypo.heading(size: 15, color: _textMain)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final ok = await showDialog<bool>(context: ctx,
                    builder: (_) => AlertDialog(title: const Text('초기화'), content: const Text('기본값으로?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
                      ]));
                  if (ok == true) { await SubjectConfig.resetToDefaults(); setBS(() {}); setState(() {}); }
                },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Text('초기화', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: Colors.orange))),
              ),
            ]),
            const SizedBox(height: 14),
            ...subjects.entries.map((e) {
              final c = Color(e.value.colorValue);
              return Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: c.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withOpacity(0.10))),
                child: Row(children: [
                  Text(e.value.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Text(e.key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
                  const Spacer(),
                  GestureDetector(onTap: () async {
                    await SubjectConfig.removeSubject(e.key);
                    setBS(() {}); setState(() {});
                  }, child: const Padding(padding: EdgeInsets.all(5),
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.redAccent))),
                ]),
              );
            }),
          ]),
        ));
      }));
  }

  String _fFmtMin(int m) {
    final h = m ~/ 60; final r = m % 60;
    if (h > 0 && r > 0) return '${h}h ${r}m';
    if (h > 0) return '${h}h';
    return '${r}m';
  }

  String _fFmtTime(String? raw) {
    if (raw == null) return '--:--';
    if (raw.contains('T')) {
      try {
        final dt = DateTime.parse(raw);
        return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }
    if (raw.length >= 5 && raw.contains(':')) return raw.substring(0, 5);
    return raw;
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
                Row(children: [
                  Text('시작시간', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: txt)),
                  const Spacer(),
                  _manualTimeBtn(startH, (v) => setLocal(() => startH = v), 23, txt, dk),
                  Text(' : ', style: TextStyle(fontSize: 18, color: txt)),
                  _manualTimeBtn(startM, (v) => setLocal(() => startM = v), 59, txt, dk),
                ]),
                const SizedBox(height: 16),
                _manualMinRow('📖 집중공부', studyMin, (v) => setLocal(() => studyMin = v), txt, muted, dk),
                _manualMinRow('🎧 강의듣기', lectureMin, (v) => setLocal(() => lectureMin = v), txt, muted, dk),
                _manualMinRow('☕ 휴식', restMin, (v) => setLocal(() => restMin = v), txt, muted, dk),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: BotanicalColors.primary)),
                  ]),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'subject': selSubject, 'studyMin': studyMin,
                      'lectureMin': lectureMin, 'restMin': restMin,
                      'startH': startH, 'startM': startM,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D5F2D), foregroundColor: Colors.white,
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
      date: dateStr, startTime: startStr, endTime: endStr,
      subject: result['subject'],
      studyMin: result['studyMin'], lectureMin: result['lectureMin'],
      effectiveMin: result['studyMin'] + (result['lectureMin'] * 0.5).round(),
      restMin: result['restMin'],
    );
    await FirebaseService().saveFocusCycle(dateStr, cycle);
    try {
      final fb = FirebaseService();
      final strs = await fb.getStudyTimeRecords();
      final existing = strs[dateStr];
      final tMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
      await fb.updateStudyTimeRecord(dateStr, StudyTimeRecord(
        date: dateStr,
        effectiveMinutes: (existing?.effectiveMinutes ?? 0) + cycle.effectiveMin,
        totalMinutes: (existing?.totalMinutes ?? 0) + tMin,
        studyMinutes: (existing?.studyMinutes ?? 0) + cycle.studyMin,
        lectureMinutes: (existing?.lectureMinutes ?? 0) + cycle.lectureMin,
      ));
    } catch (_) {}
    _load();
    _loadFocusRecords();
  }

  Widget _manualTimeBtn(int value, ValueChanged<int> onChange, int max, Color txt, bool dk) {
    return GestureDetector(
      onTap: () async {
        final ctrl = TextEditingController(text: value.toString().padLeft(2, '0'));
        final r = await showDialog<int>(context: context,
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
          ));
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
