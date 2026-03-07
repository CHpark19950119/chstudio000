part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — NFC 루틴 카드 + 외출/식사/일과종료
/// ═══════════════════════════════════════════════════
extension _HomeRoutineCard on _HomeScreenState {
  // ══════════════════════════════════════════
  //  ④ NFC 상태 카드 (프리미엄 리디자인)
  // ══════════════════════════════════════════

  Widget _nfcStatusCard() {
    final hasWake = _wake != null;
    final hasStudy = _studyStart != null;
    final bool isCurrentlyOut = _outing != null && _returnHome == null;
    final bool hasReturned = _outing != null && _returnHome != null;
    final hasBed = _bedTime != null;

    // 현재 상태 판별
    String currentPhase;
    Color phaseColor;
    IconData phaseIcon;
    if (_ft.isRunning) {
      currentPhase = '학습 중'; phaseColor = BotanicalColors.primary;
      phaseIcon = Icons.auto_stories_rounded;
    } else if (isCurrentlyOut) {
      currentPhase = '외출 중'; phaseColor = const Color(0xFF3B8A6B);
      phaseIcon = Icons.directions_walk_rounded;
    } else if (hasBed && _studyEnd != null && hasReturned) {
      // 취침: 공부종료 + 귀가완료 + 취침태그 모두 있어야 표시
      currentPhase = '취침'; phaseColor = const Color(0xFF6B5DAF);
      phaseIcon = Icons.bedtime_rounded;
    } else if (hasReturned) {
      currentPhase = '귀가 완료'; phaseColor = const Color(0xFF5B7ABF);
      phaseIcon = Icons.home_rounded;
    } else if (_studyEnd != null) {
      currentPhase = '공부 종료'; phaseColor = const Color(0xFF5B7ABF);
      phaseIcon = Icons.check_circle_rounded;
    } else if (hasStudy) {
      currentPhase = '대기'; phaseColor = _accent; phaseIcon = Icons.schedule_rounded;
    } else if (hasWake) {
      currentPhase = _noOuting ? '재택 중' : '준비 중';
      phaseColor = _noOuting ? const Color(0xFF5B7ABF) : const Color(0xFFF59E0B);
      phaseIcon = _noOuting ? Icons.home_rounded : Icons.wb_sunny_rounded;
    } else {
      currentPhase = '시작 전'; phaseColor = _textMuted; phaseIcon = Icons.wb_twilight_rounded;
    }

    final isLive = _ft.isRunning || isCurrentlyOut;

    // 메쉬 그라디언트 색상 세트
    final meshColors = _dk
      ? [const Color(0xFF0C1929), const Color(0xFF0F1F35), const Color(0xFF0A1525)]
      : [const Color(0xFFFDFAF4), const Color(0xFFF5EFE3), const Color(0xFFFAF6ED)];
    final meshAccent1 = _dk
      ? phaseColor.withOpacity(0.06)
      : phaseColor.withOpacity(0.03);
    final meshAccent2 = _dk
      ? BotanicalColors.gold.withOpacity(0.04)
      : BotanicalColors.gold.withOpacity(0.02);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: meshColors),
        border: Border.all(
          color: _dk ? phaseColor.withOpacity(0.08) : _border.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: _dk ? Colors.black.withOpacity(0.4) : phaseColor.withOpacity(0.06),
            blurRadius: 30, offset: const Offset(0, 10)),
          if (!_dk) BoxShadow(
            color: Colors.white.withOpacity(0.8),
            blurRadius: 20, offset: const Offset(-5, -5)),
        ],
      ),
      child: Stack(children: [
        // ── 메쉬 그라디언트 오버레이 ──
        Positioned(top: -30, left: -30,
          child: Container(width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [meshAccent1, Colors.transparent])))),
        Positioned(bottom: -20, right: -20,
          child: Container(width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [meshAccent2, Colors.transparent])))),
        // ── 그리드 패턴 (다크) ──
        if (_dk) Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: CustomPaint(painter: CyberGridPainter()))),

        // ── 콘텐츠 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── ROW 1: 타이틀 + 상태 뱃지 ──
            Row(children: [
              // 상태 아이콘 원형
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [phaseColor.withOpacity(0.25), phaseColor.withOpacity(0.08)]),
                  boxShadow: [BoxShadow(
                    color: phaseColor.withOpacity(0.15), blurRadius: 8)]),
                child: Icon(phaseIcon, size: 16, color: phaseColor),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('오늘의 상태', style: BotanicalTypo.label(
                  size: 12, weight: FontWeight.w600,
                  color: _dk ? Colors.white38 : _textMuted, letterSpacing: 1.5)),
                Text(currentPhase, style: BotanicalTypo.heading(
                  size: 18, weight: FontWeight.w800, color: phaseColor)),
              ]),
              const Spacer(),
              // GPS + LIVE 뱃지
              if (isLive) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: phaseColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: phaseColor.withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _pulseDot(phaseColor), const SizedBox(width: 4),
                  Text('LIVE', style: BotanicalTypo.label(
                    size: 9, weight: FontWeight.w800, color: phaseColor)),
                ]),
              ),
              if (_locationTracking) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B8A6B).withOpacity(_dk ? 0.10 : 0.05),
                    borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _pulseDot(const Color(0xFF3B8A6B)),
                    const SizedBox(width: 3),
                    Text('GPS', style: BotanicalTypo.label(
                      size: 8, weight: FontWeight.w700, color: const Color(0xFF3B8A6B))),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 18),

            // ── ROW 2: 기상루틴(LEFT 2×2) + 취침루틴(RIGHT) 나란히 ──
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── LEFT: 기상/공부 2×2 타일 ──
              Expanded(flex: 5, child: Column(children: [
                Row(children: [
                  Expanded(child: _statusTile(
                    emoji: '☀️', label: '기상',
                    value: hasWake ? _fmtBigTime(_wake) : '--:--',
                    sub: hasWake ? _ampm(_wake) : '',
                    color: BotanicalColors.gold,
                    active: hasWake,
                    onTap: () => _editTimeField('wake', '기상시간', _wake))),
                  const SizedBox(width: 6),
                  Expanded(child: _statusTile(
                    emoji: isCurrentlyOut ? '🚶' : (hasReturned ? '🏠' : '🚪'),
                    label: isCurrentlyOut ? '외출 중' : (hasReturned ? '귀가' : '외출'),
                    value: isCurrentlyOut ? _fmtBigTime(_outing)
                        : (hasReturned ? _fmtBigTime(_returnHome) : '--:--'),
                    sub: isCurrentlyOut ? '${_ampm(_outing)} ~' : (hasReturned ? _ampm(_returnHome) : ''),
                    color: const Color(0xFF3B8A6B),
                    active: isCurrentlyOut || hasReturned,
                    isLive: isCurrentlyOut,
                    onTap: () => _editTimeField('outing', '외출', _outing))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _statusTile(
                    emoji: '📖', label: '공부시작',
                    value: hasStudy ? _fmtBigTime(_studyStart) : '--:--',
                    sub: hasStudy ? _ampm(_studyStart) : '',
                    color: BotanicalColors.primary,
                    active: hasStudy || _ft.isRunning,
                    isLive: _ft.isRunning,
                    onTap: () => _editTimeField('study', '공부시작', _studyStart))),
                  const SizedBox(width: 6),
                  Expanded(child: _statusTile(
                    emoji: '✏️', label: '공부종료',
                    value: _studyEnd != null ? _fmtBigTime(_studyEnd) : '--:--',
                    sub: _studyEnd != null ? _ampm(_studyEnd) : '',
                    color: const Color(0xFF5B7ABF),
                    active: _studyEnd != null,
                    onTap: () => _editTimeField('studyEnd', '공부종료', _studyEnd))),
                ]),
              ])),

              const SizedBox(width: 8),

              // ── RIGHT: 취침+식사 컴팩트 ──
              Expanded(flex: 2, child: Column(children: [
                // 취침 타일
                GestureDetector(
                  onTap: () => _editTimeField('wake', '기상시간', _wake),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: hasBed
                        ? const Color(0xFF6B5DAF).withOpacity(_dk ? 0.08 : 0.04)
                        : (_dk ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasBed
                          ? const Color(0xFF6B5DAF).withOpacity(0.15)
                          : (_dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)))),
                    child: Row(children: [
                      Text('🌙', style: TextStyle(fontSize: hasBed ? 14 : 12)),
                      const SizedBox(width: 6),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('취침', style: BotanicalTypo.label(
                          size: 9, weight: FontWeight.w600, letterSpacing: 0.5,
                          color: hasBed ? const Color(0xFF6B5DAF).withOpacity(0.8) : _textMuted)),
                        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic, children: [
                          Text(hasBed ? _fmtBigTime(_bedTime) : '--:--',
                            style: TextStyle(
                              fontSize: hasBed ? 14 : 12,
                              fontWeight: FontWeight.w900,
                              color: hasBed
                                ? (_dk ? Colors.white.withOpacity(0.95) : const Color(0xFF6B5DAF))
                                : (_dk ? Colors.white30 : _textMuted.withOpacity(0.5)))),
                          if (hasBed) ...[
                            const SizedBox(width: 2),
                            Text(_ampm(_bedTime), style: BotanicalTypo.label(
                              size: 8, weight: FontWeight.w600,
                              color: const Color(0xFF6B5DAF).withOpacity(0.6))),
                          ],
                        ]),
                      ])),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                // 식사 타일
                GestureDetector(
                  onTap: () => _editTimeField('meal', '식사', null),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: (_todayMeals.isNotEmpty || _mealStart != null)
                        ? const Color(0xFFFF8A65).withOpacity(_dk ? 0.08 : 0.04)
                        : (_dk ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_todayMeals.isNotEmpty || _mealStart != null)
                          ? const Color(0xFFFF8A65).withOpacity(0.15)
                          : (_dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)))),
                    child: Row(children: [
                      Text('🍽️', style: TextStyle(fontSize: (_todayMeals.isNotEmpty || _mealStart != null) ? 14 : 12)),
                      const SizedBox(width: 6),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('식사', style: BotanicalTypo.label(
                          size: 9, weight: FontWeight.w600, letterSpacing: 0.5,
                          color: (_todayMeals.isNotEmpty || _mealStart != null)
                            ? const Color(0xFFFF8A65).withOpacity(0.8) : _textMuted)),
                        if (_todayMeals.isNotEmpty)
                          Text('${_todayMeals.length}회', style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: _dk ? Colors.white.withOpacity(0.9) : const Color(0xFFFF8A65)))
                        else if (_mealStart != null)
                          Text(_mealStart!, style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: _dk ? Colors.white.withOpacity(0.9) : const Color(0xFFFF8A65)))
                        else
                          Text('--', style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: _dk ? Colors.white30 : _textMuted.withOpacity(0.5))),
                      ])),
                    ]),
                  ),
                ),
              ])),
            ])),
            const SizedBox(height: 10),

            // ── 재택일 토글 ──
            if (_outing == null) GestureDetector(
              onTap: () async {
                final d = _studyDate();
                final newVal = !_noOuting;
                _safeSetState(() => _noOuting = newVal);
                try {
                  await FirebaseService().updateField(
                    'timeRecords.$d.noOuting', newVal);
                } catch (_) {}
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _noOuting
                      ? const Color(0xFF5B7ABF).withOpacity(_dk ? 0.12 : 0.06)
                      : (_dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _noOuting
                      ? const Color(0xFF5B7ABF).withOpacity(0.25)
                      : _border.withOpacity(0.15))),
                child: Row(children: [
                  Text(_noOuting ? '🏠' : '🚪', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(_noOuting ? '오늘은 재택일입니다' : '오늘은 외출 예정',
                    style: BotanicalTypo.label(
                      size: 11, weight: FontWeight.w600,
                      color: _noOuting
                          ? const Color(0xFF5B7ABF)
                          : (_dk ? Colors.white38 : Colors.grey.shade500))),
                  const Spacer(),
                  Container(
                    width: 36, height: 20,
                    decoration: BoxDecoration(
                      color: _noOuting
                          ? const Color(0xFF5B7ABF) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10)),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _noOuting ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 16, height: 16, margin: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle))),
                  ),
                ]),
              ),
            ),

            // ── ROW 3: 하단 진행 바 + 액션 ──
            // 타임라인 도트
            _dayProgressDots(hasWake, isCurrentlyOut || hasReturned, hasStudy, hasReturned, hasBed),
            const SizedBox(height: 14),

            // 액션 버튼 행
            Row(children: [
              _miniActionChip(
                icon: isCurrentlyOut ? Icons.home_rounded : Icons.directions_walk_rounded,
                label: isCurrentlyOut ? '귀가' : (hasReturned ? '완료' : '외출'),
                color: const Color(0xFF3B8A6B),
                enabled: !hasReturned,
                active: isCurrentlyOut,
                onTap: hasReturned ? null : () => _toggleOuting()),
              const SizedBox(width: 8),
              _miniActionChip(
                icon: Icons.nfc_rounded,
                label: 'NFC',
                color: _dk ? BotanicalColors.lanternGold : const Color(0xFFB05C8A),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => NfcScreen()))
                  .then((_) => _load())),
              const SizedBox(width: 8),
              _miniActionChip(
                icon: Icons.edit_rounded,
                label: '수정',
                color: _accent,
                onTap: () => _editTimeField('wake', '기상시간', _wake)),
              if (_outingMinutes != null && _outingMinutes! > 0) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B8A6B).withOpacity(_dk ? 0.10 : 0.05),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('외출 ${_formatMin(_outingMinutes!)}',
                    style: BotanicalTypo.label(size: 10, weight: FontWeight.w700,
                      color: const Color(0xFF3B8A6B)))),
              ] else if (isCurrentlyOut) ...[
                const Spacer(),
                Row(children: [
                  _pulseDot(const Color(0xFF3B8A6B)),
                  const SizedBox(width: 4),
                  Text('${_formatMin(_calcOutingElapsed())} 경과',
                    style: BotanicalTypo.label(size: 10, weight: FontWeight.w700,
                      color: const Color(0xFF3B8A6B))),
                ]),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  /// 컴팩트 상태 타일 (2×2 그리드 내 1셀)
  Widget _statusTile({
    required String emoji, required String label,
    required String value, required String sub,
    required Color color, required bool active,
    bool isLive = false, VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          // 글래스모피즘 배경
          color: active
            ? (_dk ? color.withOpacity(0.06) : color.withOpacity(0.03))
            : (_dk ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
              ? color.withOpacity(_dk ? 0.20 : 0.12)
              : (_dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03))),
          boxShadow: active ? [
            BoxShadow(color: color.withOpacity(_dk ? 0.06 : 0.04),
              blurRadius: 16, offset: const Offset(0, 4)),
          ] : (!_dk ? [
            BoxShadow(color: Colors.white.withOpacity(0.7),
              blurRadius: 8, offset: const Offset(-2, -2)),
            BoxShadow(color: Colors.black.withOpacity(0.02),
              blurRadius: 8, offset: const Offset(2, 2)),
          ] : null),
        ),
        child: Row(children: [
          // 이모지
          Text(emoji, style: TextStyle(fontSize: active ? 16 : 14)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 라벨
            Row(children: [
              Text(label, style: BotanicalTypo.label(
                size: 9, weight: FontWeight.w600,
                color: active ? color.withOpacity(0.8) : _textMuted,
                letterSpacing: 0.5)),
              if (isLive) ...[
                const SizedBox(width: 4),
                _pulseDot(color),
              ],
            ]),
            const SizedBox(height: 1),
            // 시간 + AM/PM
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
              Text(value, style: TextStyle(
                fontSize: active ? 17 : 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: active
                  ? (_dk ? Colors.white.withOpacity(0.95) : color)
                  : (_dk ? Colors.white30 : _textMuted.withOpacity(0.5)),
                height: 1.1)),
              if (sub.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(sub, style: BotanicalTypo.label(
                  size: 8, weight: FontWeight.w600,
                  color: active ? color.withOpacity(0.6) : _textMuted.withOpacity(0.4))),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }

  /// 타임라인 진행 도트 (5단계 컴팩트)
  Widget _dayProgressDots(bool wake, bool outing, bool study, bool returned, bool sleep) {
    final steps = [
      (done: wake, label: '기상', color: BotanicalColors.gold),
      (done: outing, label: '외출', color: const Color(0xFF3B8A6B)),
      (done: study, label: '공부', color: BotanicalColors.primary),
      (done: returned, label: '귀가', color: const Color(0xFF5B7ABF)),
      (done: sleep, label: '수면', color: const Color(0xFF6B5DAF)),
    ];
    final doneCount = steps.where((s) => s.done).length;
    return Row(children: [
      // 프로그레스 바
      Expanded(child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(2)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (doneCount / steps.length).clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(colors: [
                BotanicalColors.gold,
                BotanicalColors.primary,
                const Color(0xFF6B5DAF),
              ])),
          ),
        ),
      )),
      const SizedBox(width: 10),
      // 도트 인디케이터
      for (int i = 0; i < steps.length; i++) ...[
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: steps[i].done ? steps[i].color : (_dk ? Colors.white10 : Colors.grey.shade200),
            boxShadow: steps[i].done ? [BoxShadow(
              color: steps[i].color.withOpacity(0.4), blurRadius: 4)] : null)),
        if (i < steps.length - 1) const SizedBox(width: 4),
      ],
      const SizedBox(width: 8),
      Text('$doneCount/${steps.length}', style: BotanicalTypo.label(
        size: 10, weight: FontWeight.w700, color: _textMuted)),
    ]);
  }

  /// 미니 액션 칩
  Widget _miniActionChip({
    required IconData icon, required String label, required Color color,
    VoidCallback? onTap, bool enabled = true, bool active = false,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
            ? color.withOpacity(_dk ? 0.12 : 0.06)
            : (enabled
              ? (_dk ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7))
              : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color.withOpacity(0.25)
              : (enabled ? (_dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
                : Colors.transparent))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
            color: enabled ? (active ? color : _textSub) : _textMuted.withOpacity(0.2)),
          const SizedBox(width: 4),
          Text(label, style: BotanicalTypo.label(
            size: 10, weight: FontWeight.w700,
            color: enabled ? (active ? color : _textSub) : _textMuted.withOpacity(0.2))),
        ]),
      ),
    );
  }

  /// 시간 포맷: "7:00" (큰 숫자용)
  String _fmtBigTime(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return '--:--';
    try {
      final p = hhmm.split(':');
      final h = int.parse(p[0]); final m = p[1];
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$h12:$m';
    } catch (_) { return '--:--'; }
  }

  /// AM/PM 문자열
  String _ampm(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return '';
    try {
      final h = int.parse(hhmm.split(':')[0]);
      return h < 12 ? 'AM' : 'PM';
    } catch (_) { return ''; }
  }

  /// 외출/귀가 토글 (버튼으로 직접 실행)
  Future<void> _toggleOuting() async {
    final d = _studyDate();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final existing = records[d];

    if (_outing == null || (_outing != null && _returnHome != null)) {
      // 외출 시작
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: existing?.wake,
        study: existing?.study, studyEnd: existing?.studyEnd,
        outing: timeStr, returnHome: null,
        arrival: existing?.arrival, bedTime: existing?.bedTime,
        mealStart: existing?.mealStart, mealEnd: existing?.mealEnd,
        meals: existing?.meals,
      ));
      _nfc.forceOutState(true);

      // ★ #3: GPS 추적 시작 (수동 외출에서도 NFC와 동일하게 작동)
      if (!_ls.isTracking) {
        await _ls.startTracking();
        debugPrint('[Home] 📍 수동 외출 → GPS 추적 시작');
      }
      _ls.setTravelMode(true);

      // 즉시 UI 반영
      _safeSetState(() { _outing = timeStr; _returnHome = null; _outingMinutes = null; _locationTracking = true; });
    } else if (_outing != null && _returnHome == null) {
      // 귀가
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: existing?.wake,
        study: existing?.study, studyEnd: existing?.studyEnd,
        outing: existing?.outing, returnHome: timeStr,
        arrival: existing?.arrival, bedTime: existing?.bedTime,
        mealStart: existing?.mealStart, mealEnd: existing?.mealEnd,
        meals: existing?.meals,
      ));
      _nfc.forceOutState(false);

      // ★ #3: GPS 추적 종료 (수동 귀가에서도 NFC와 동일하게 작동)
      _ls.forceCurrentPlaceAsHome();
      if (_ls.isTracking) {
        await _ls.stopTracking();
        debugPrint('[Home] 📍 수동 귀가 → GPS 추적 종료');
      }
      _ls.setTravelMode(false);

      // 즉시 UI 반영 (outing 유지 + returnHome 설정 → hasReturned = true)
      final outMin = TimeRecord(date: d, outing: _outing, returnHome: timeStr).outingMinutes;
      _safeSetState(() {
        _returnHome = timeStr;
        _outingMinutes = outMin;
        _locationTracking = false;
      });
      // Firebase 재로드로 확실한 동기화
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _load();

      // 22시 이후 귀가 → 하루 마무리 제안
      if (now.hour >= 22 && mounted) {
        _showDayEndDialog(d);
      }
    }
  }

  /// 하루 마무리 다이얼로그 (22시 이후 귀가 시)
  Future<void> _showDayEndDialog(String dateStr) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('🌙 하루 마무리', style: BotanicalTypo.heading(
          size: 18, weight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('오늘 하루 수고하셨습니다.\n공부를 종료하고 하루를 마무리할까요?',
            style: TextStyle(fontSize: 14, color: _textSub, height: 1.5)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BotanicalColors.primary.withOpacity(_dk ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text('📚', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text('순공 ${_effMin ~/ 60}h ${_effMin % 60}m',
                style: BotanicalTypo.label(size: 14, weight: FontWeight.w800,
                  color: BotanicalColors.primary)),
              const Spacer(),
              if (_grade != null)
                Text('${_grade!.grade} ${_grade!.totalScore.toStringAsFixed(0)}점',
                  style: BotanicalTypo.label(size: 13, weight: FontWeight.w700,
                    color: BotanicalColors.gradeColor(_grade!.grade))),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('아직', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D5F2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('마무리', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      // 공부종료 기록
      final now = DateTime.now();
      final endStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      if (existing != null && existing.studyEnd == null) {
        await fb.updateTimeRecord(dateStr, TimeRecord(
          date: dateStr, wake: existing.wake,
          study: existing.study, studyEnd: endStr,
          outing: existing.outing, returnHome: existing.returnHome,
          arrival: existing.arrival, bedTime: existing.bedTime,
          mealStart: existing.mealStart, mealEnd: existing.mealEnd,
          meals: existing.meals,
        ));
      }
      _load();
    }
  }

  // _actionButton 제거됨 → _statusActionBtn으로 대체

  // _statusBlockTappable 제거됨 → _statusNode로 대체

  int _calcOutingElapsed() {
    if (_outing == null) return 0;
    try {
      final p = _outing!.split(':');
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day,
        int.parse(p[0]), int.parse(p[1]));
      return now.difference(start).inMinutes.clamp(0, 1440);
    } catch (_) { return 0; }
  }

  // _outingStatsBar 제거됨 → 상태카드 내 인라인으로 통합
  // _connector 제거됨 → _dayProgressDots로 대체

  Future<void> _editTimeField(String field, String label, String? current) async {
    final d = _studyDate();
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final existing = records[d];
    if (!mounted) return;

    final result = await showModalBottomSheet<TimeRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatusEditorSheet(existing: existing, dk: _dk, highlightField: field),
    );
    if (result == null) return;

    // ★ v11: TimeRecord 직접 반환 (식사 편집 포함)
    final updated = TimeRecord(
      date: d, wake: result.wake, study: result.study,
      studyEnd: result.studyEnd, outing: result.outing,
      returnHome: result.returnHome,
      arrival: result.arrival ?? existing?.arrival,
      bedTime: result.bedTime,
      mealStart: result.mealStart, mealEnd: result.mealEnd,
      meals: result.meals,
    );
    await fb.updateTimeRecord(d, updated);
    if (updated.outing != null && updated.returnHome == null) {
      _nfc.forceOutState(true);
      // ★ #4: 외출 상태 변경 시 GPS 자동 시작
      if (!_ls.isTracking) {
        await _ls.startTracking();
        debugPrint('[Home] 📍 상태 편집 → 외출 → GPS 추적 시작');
      }
      _ls.setTravelMode(true);
    } else {
      _nfc.forceOutState(false);
      // 귀가 상태면 GPS 종료
      if (updated.returnHome != null && _ls.isTracking) {
        _ls.forceCurrentPlaceAsHome();
        await _ls.stopTracking();
        _ls.setTravelMode(false);
        debugPrint('[Home] 📍 상태 편집 → 귀가 → GPS 추적 종료');
      }
    }
    if (updated.study != null && updated.studyEnd == null) {
      _nfc.forceStudyState(true);
    } else {
      _nfc.forceStudyState(false);
    }
    // ★ Rule C: _load() 재호출 없이 즉시 UI 반영 (Optimistic UI)
    _safeSetState(() {
      _wake = updated.wake;
      _studyStart = updated.study;
      _studyEnd = updated.studyEnd;
      _outing = updated.outing;
      _returnHome = updated.returnHome;
      _bedTime = updated.bedTime;
      _mealStart = updated.mealStart;
      _mealEnd = updated.mealEnd;
      if (updated.meals != null) _todayMeals = updated.meals!;
    });

    // 💌 다영에게 알리기 SnackBar
    final roleMap = {'wake': 'wake', 'outing': 'outing', 'study': 'study'};
    final timeMap = {'wake': updated.wake, 'outing': updated.outing, 'study': updated.study};
    final tgRole = roleMap[field];
    final tgTime = timeMap[field];
    if (tgRole != null && tgTime != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$tgTime 저장됨'),
        action: SnackBarAction(
          label: '📩 다영에게 알리기',
          onPressed: () => TelegramService().sendToGf(tgRole, tgTime),
        ),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  String _formatMin(int min) {
    final h = min ~/ 60; final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  // ★ v11: 식사 타입 헬퍼
  String _mealTypeEmoji(String? type) {
    switch (type) {
      case 'breakfast': return '🌅';
      case 'lunch': return '☀️';
      case 'dinner': return '🌙';
      case 'snack': return '🍪';
      default: return '🍽️';
    }
  }

  String _mealTypeLabel(String? type) {
    switch (type) {
      case 'breakfast': return '아침';
      case 'lunch': return '점심';
      case 'dinner': return '저녁';
      case 'snack': return '간식';
      default: return '식사';
    }
  }

  String _fmt12h(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return '--:--';
    try {
      final p = hhmm.split(':');
      final h = int.parse(p[0]); final m = p[1];
      final prefix = h < 12 ? '오전' : '오후';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$prefix $h12:$m';
    } catch (_) { return hhmm; }
  }

  Widget _pulseDot(Color c) => Container(width: 8, height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)]));

}
