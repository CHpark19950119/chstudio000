part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 데일리 로그 블록 타임라인
/// ═══════════════════════════════════════════════════
extension _HomeDailyLog on _HomeScreenState {
  // ══════════════════════════════════════════
  //  데일리 로그 — 블록 프로그레스 바 (비율 기반)
  //  Premium animated block segments
  // ══════════════════════════════════════════

  Widget _locationSummaryCard() {
    final segments = <_DaySegment>[];

    // ★ B2/B4 FIX: 모든 이벤트를 시간순으로 수집한 뒤 정렬
    // 하루는 기상~취침까지만 표시 (수면시간은 별도 통계)

    // 1) 이벤트 수집 (시간이 있는 것만)
    final events = <({String time, String type})>[];
    if (_wake != null) events.add((time: _wake!, type: 'wake'));
    if (_outing != null) events.add((time: _outing!, type: 'outing'));
    if (_studyStart != null) events.add((time: _studyStart!, type: 'studyStart'));
    // ★ v9: 다회 식사 이벤트 (meals가 있으면 레거시 무시)
    if (_todayMeals.isNotEmpty) {
      for (int i = 0; i < _todayMeals.length; i++) {
        final m = _todayMeals[i];
        events.add((time: m.start, type: 'meal_${i}_start'));
        if (m.end != null) events.add((time: m.end!, type: 'meal_${i}_end'));
      }
    } else {
      if (_mealStart != null) events.add((time: _mealStart!, type: 'mealStart'));
      if (_mealEnd != null) events.add((time: _mealEnd!, type: 'mealEnd'));
    }
    if (_studyEnd != null) events.add((time: _studyEnd!, type: 'studyEnd'));
    if (_returnHome != null) events.add((time: _returnHome!, type: 'returnHome'));
    if (_bedTime != null) events.add((time: _bedTime!, type: 'bedTime'));

    // 시간순 정렬 (자정 넘김 처리: 04:00 이전은 +24h)
    int safeMin(String t) {
      final m = _toMin(t);
      return m < 240 ? m + 1440 : m; // 04:00 이전은 다음날로 간주
    }
    events.sort((a, b) => safeMin(a.time).compareTo(safeMin(b.time)));

    // 2) ★ #8 FIX: 이벤트 순서대로 세그먼트 생성 (시간 수정 시 올바른 위치에 배치)
    // 모든 이벤트를 시작/종료 페어로 변환하여 시간순 분포
    
    String _labelBetween(String fromType, String toType) {
      // 두 이벤트 사이의 활동 유형 결정
      // wake 이후 noOuting이면 "재택"으로 표시
      if (fromType == 'wake') return _noOuting ? '재택' : '준비';
      if (fromType == 'outing') return '이동';
      if (fromType == 'studyStart' || fromType.startsWith('meal_') && fromType.endsWith('_end')) return '공부';
      if (fromType.startsWith('meal_') && fromType.endsWith('_start')) return '식사';
      if (fromType == 'mealStart') return '식사';
      if (fromType == 'mealEnd') return '공부';
      if (fromType == 'studyEnd') return '이동';
      if (fromType == 'returnHome') return '자유';
      return _noOuting ? '재택' : '준비';
    }
    
    Color _colorFor(String label) {
      switch (label) {
        case '준비': return const Color(0xFFF59E0B);
        case '재택': return const Color(0xFF5B7ABF);
        case '이동': return const Color(0xFF3B8A6B);
        case '공부': return const Color(0xFF6366F1);
        case '식사': return const Color(0xFFFF8A65);
        case '자유': return const Color(0xFF94A3B8);
        case '취침': return const Color(0xFF6B5DAF);
        default: return const Color(0xFF94A3B8);
      }
    }
    
    String _emojiFor(String label) {
      switch (label) {
        case '준비': return '🌅';
        case '재택': return '🏠';
        case '이동': return '🚶';
        case '공부': return '📖';
        case '식사': return '🍽️';
        case '자유': return '🏠';
        case '취침': return '🛏️';
        default: return '📍';
      }
    }
    
    // 연속 이벤트 페어로 세그먼트 생성
    for (int i = 0; i < events.length; i++) {
      final curr = events[i];
      final String segEnd;
      
      if (i + 1 < events.length) {
        segEnd = events[i + 1].time;
      } else if (curr.type == 'bedTime') {
        // 취침은 시점 마커
        segments.add(_DaySegment(
          start: curr.time, end: curr.time,
          label: '취침', emoji: '🛏️', color: const Color(0xFF6B5DAF)));
        continue;
      } else {
        segEnd = _fmt24Now();
      }
      
      // 시작과 종료가 같으면 스킵
      if (curr.time == segEnd) continue;
      
      // 이벤트 타입에 따라 세그먼트 라벨 결정
      String label;
      switch (curr.type) {
        case 'wake': label = _noOuting ? '재택' : '준비'; break;
        case 'outing': label = '이동'; break;
        case 'studyStart': label = '공부'; break;
        case 'studyEnd':
          // 공부종료 → 다음 이벤트까지 (귀가 전이면 이동, 아니면 자유)
          final nextType = i + 1 < events.length ? events[i + 1].type : '';
          label = nextType == 'returnHome' ? '이동' : '자유';
          break;
        case 'mealStart': label = '식사'; break;
        case 'mealEnd':
          // 식사종료 → 다음까지 (공부/자유 등)
          final nextT = i + 1 < events.length ? events[i + 1].type : '';
          label = nextT == 'studyEnd' || nextT == 'returnHome' ? '공부' : (_noOuting ? '재택' : '준비');
          break;
        case 'returnHome': label = '자유'; break;
        case 'bedTime': label = '취침'; break;
        default:
          // meal_N_start, meal_N_end 등
          if (curr.type.endsWith('_start')) { label = '식사'; }
          else if (curr.type.endsWith('_end')) {
            final nextT = i + 1 < events.length ? events[i + 1].type : '';
            label = nextT.contains('study') || nextT.contains('meal') ? '공부' : (_noOuting ? '재택' : '준비');
          }
          else { label = _noOuting ? '재택' : '준비'; }
      }
      
      segments.add(_DaySegment(
        start: curr.time, end: segEnd,
        label: label, emoji: _emojiFor(label), color: _colorFor(label)));
    }

    // ★ B4 FIX: 세그먼트를 시작 시간순으로 최종 정렬
    segments.sort((a, b) => safeMin(a.start).compareTo(safeMin(b.start)));

    // 중복/겹침 제거: 동일 시작시간 세그먼트 중 라벨이 같은 것 제거
    final seen = <String>{};
    segments.removeWhere((seg) {
      final key = '${seg.start}_${seg.label}';
      if (seen.contains(key)) return true;
      seen.add(key);
      return false;
    });

    if (segments.isEmpty) return const SizedBox.shrink();

    // ★ B2 FIX: 자정 넘김을 고려한 duration 계산
    final startMin = safeMin(segments.first.start);
    final endMin = safeMin(_fmt24Now());
    final totalRange = (endMin - startMin).clamp(1, 1440);

    // 각 세그먼트 duration 계산 (자정 넘김 보정)
    final durations = segments.map((seg) {
      final s = safeMin(seg.start);
      final e = seg.end == seg.start ? s + 1 : safeMin(seg.end);
      return (e - s).clamp(0, 1440);
    }).toList();
    final totalDur = durations.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border.withOpacity(0.12)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 헤더 ──
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF6366F1).withOpacity(0.15),
                const Color(0xFF8B5CF6).withOpacity(0.08)]),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.timeline_rounded, size: 14, color: Color(0xFF6366F1))),
          const SizedBox(width: 8),
          Text('데일리 로그', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: _textMain)),
          const Spacer(),
          // ── 수정 버튼 ──
          GestureDetector(
            onTap: () => _editTimeField('wake', '기상', _wake),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(_dk ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_rounded, size: 11, color: const Color(0xFF6366F1).withOpacity(0.7)),
                const SizedBox(width: 3),
                Text('수정', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: const Color(0xFF6366F1).withOpacity(0.7))),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _accent.withOpacity(_dk ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${segments.first.start} ~ ${_fmt24Now()}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: _accent, fontFeatures: const [FontFeature.tabularFigures()]))),
        ]),
        const SizedBox(height: 16),

        // ── 블록 프로그레스 바 (비율 기반) ──
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (ctx, animVal, _) {
            return Column(children: [
              // 시간 마커 (시작, 끝)
              Row(children: [
                Text(segments.first.start,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                Text(_fmt24Now(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _accent, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 4),
              // 메인 블록 바
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: List.generate(segments.length, (i) {
                      final ratio = totalDur > 0 ? durations[i] / totalDur : 1.0 / segments.length;
                      final seg = segments[i];
                      // 애니메이션: 좌→우로 순차 등장
                      final segStart = i / segments.length;
                      final segProgress = ((animVal - segStart) / (1.0 - segStart)).clamp(0.0, 1.0);
                      return Expanded(
                        flex: (ratio * 1000).round().clamp(1, 1000),
                        child: Opacity(
                          opacity: segProgress,
                          child: Container(
                            margin: EdgeInsets.only(
                              left: i == 0 ? 0 : 1.5,
                              right: i == segments.length - 1 ? 0 : 1.5),
                            decoration: BoxDecoration(
                              color: seg.color.withOpacity(_dk ? 0.75 : 0.85),
                              borderRadius: BorderRadius.horizontal(
                                left: i == 0 ? const Radius.circular(12) : Radius.zero,
                                right: i == segments.length - 1 ? const Radius.circular(12) : Radius.zero),
                              boxShadow: [BoxShadow(
                                color: seg.color.withOpacity(0.2),
                                blurRadius: 4, offset: const Offset(0, 2))]),
                            child: Center(child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(seg.emoji,
                                  style: const TextStyle(fontSize: 13)))))),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ]);
          },
        ),
        const SizedBox(height: 14),

        // ── 디테일 리스트 ──
        ...List.generate(segments.length, (i) {
          final seg = segments[i];
          final dur = durations[i];
          final durStr = dur >= 60
            ? '${dur ~/ 60}시간${dur % 60 > 0 ? " ${dur % 60}분" : ""}'
            : '${dur}분';
          final pct = totalDur > 0 ? (dur / totalDur * 100).round() : 0;

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 500 + i * 80),
            curve: Curves.easeOutCubic,
            builder: (ctx, val, child) {
              return Opacity(
                opacity: val,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - val)),
                  child: child),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                // 색상 바
                Container(width: 3, height: 36,
                  decoration: BoxDecoration(
                    color: seg.color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                // 이모지
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: seg.color.withOpacity(_dk ? 0.1 : 0.08),
                    borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(seg.emoji, style: const TextStyle(fontSize: 14)))),
                const SizedBox(width: 8),
                // 활동명 + 시간
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(seg.label, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
                    Text('${seg.start} → ${seg.end == seg.start ? seg.start : seg.end}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                        color: _textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                )),
                // 비율 + 시간 뱃지
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: seg.color.withOpacity(_dk ? 0.1 : 0.08),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(durStr, style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800, color: seg.color,
                      fontFeatures: const [FontFeature.tabularFigures()]))),
                  const SizedBox(height: 2),
                  Text('$pct%', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: _textMuted.withOpacity(0.7))),
                ]),
              ]),
            ),
          );
        }),

        // ── 시간 집계 요약 ──
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            ...(() {
              // 카테고리별 합산
              final catMin = <String, int>{};
              for (int i = 0; i < segments.length; i++) {
                final key = segments[i].label;
                catMin[key] = (catMin[key] ?? 0) + durations[i];
              }
              // 이동, 공부, 자유 순서로 표시
              final display = <MapEntry<String, int>>[];
              for (final k in ['이동', '공부', '자유', '준비', '재택', '식사']) {
                if (catMin.containsKey(k)) display.add(MapEntry(k, catMin[k]!));
              }
              if (display.isEmpty) return <Widget>[];
              return display.asMap().entries.map((entry) {
                final e = entry.value;
                final isLast = entry.key == display.length - 1;
                final emoji = e.key == '이동' ? '🚶' : e.key == '공부' ? '📖' : e.key == '자유' ? '🏠' : e.key == '준비' ? '🌅' : e.key == '재택' ? '🏠' : '🍽️';
                final h = e.value ~/ 60; final m = e.value % 60;
                final timeStr = h > 0 ? '${h}h${m > 0 ? " ${m}m" : ""}' : '${m}m';
                return Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(emoji, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(timeStr, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _textMain,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                ]));
              }).toList();
            })(),
          ]),
        ),

        // ── ★ 데일리 메모 섹션 ──
        if (_dailyMemos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.03) : const Color(0xFFFFFBF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB07D3A).withOpacity(0.1))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('📝', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text('오늘의 메모', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _textMain)),
                const Spacer(),
                Text('${_dailyMemos.length}개', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
              ]),
              const SizedBox(height: 8),
              ..._dailyMemos.map((memo) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: memo.startsWith('📌')
                          ? const Color(0xFFB07D3A)
                          : _textMuted.withOpacity(0.4),
                        shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(memo, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: _textSub, height: 1.4))),
                  GestureDetector(
                    onTap: () async {
                      _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 12,
                        color: _textMuted.withOpacity(0.4)))),
                ]),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  String _fmt24Now() => DateFormat('HH:mm').format(DateTime.now());

  int _toMin(String hhmm) {
    try {
      // ISO 8601 형식 처리 (2026-02-24T12:30:00.000)
      if (hhmm.contains('T')) {
        final dt = DateTime.parse(hhmm);
        return dt.hour * 60 + dt.minute;
      }
      final p = hhmm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) { return 0; }
  }

}