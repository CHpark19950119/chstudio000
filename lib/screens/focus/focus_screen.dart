import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/focus_service.dart';
import '../../services/focus_mode_service.dart';
import '../../services/magnet_service.dart';
import 'focus_result_sheet.dart';
import 'focus_history_screen.dart';

// ══════════════════════════════════════════
//  FocusScreen — ListenableBuilder 기반
//  setState 사용 금지 (setupView local state 제외)
// ══════════════════════════════════════════

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with TickerProviderStateMixin {
  final _fs = FocusService();
  final _magnet = MagnetService();
  StreamSubscription? _magnetSub;
  bool _cradleAutoStarted = false;
  late AnimationController _pulseCtrl;

  // Setup-only state (세션 시작 전에만 사용)
  String _subj = '자료해석';
  String _mode = 'study';
  bool _focusMode = true;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    if (_fs.isRunning) {
      final st = _fs.getCurrentState();
      _subj = st.subject;
      _mode = st.mode;
      _enterImmersive();
    }
    SubjectConfig.load();

    // 자석 거치대
    _fs.onCradleChanged(_magnet.isOnCradle);
    if (!_magnet.isEnabled) {
      _magnet.start();
      _cradleAutoStarted = true;
    }
    _magnetSub = _magnet.cradleStream.listen((onCradle) {
      if (onCradle) HapticFeedback.mediumImpact();
      if (!onCradle && _fs.isRunning) HapticFeedback.heavyImpact();
      _fs.onCradleChanged(onCradle);
    });
  }

  @override
  void dispose() {
    _magnetSub?.cancel();
    if (_cradleAutoStarted && !_magnet.isEnabled) _magnet.stop();
    _pulseCtrl.dispose();
    _exitImmersive();
    super.dispose();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _minimizeToHome() {
    _exitImmersive();
    const platform = MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');
    platform.invokeMethod('moveTaskToBack').catchError((_) {
      SystemNavigator.pop(animated: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _fs,
      builder: (context, _) {
        final isResting = _fs.isRunning && _fs.currentMode == 'rest';
        return PopScope(
          canPop: !_fs.isRunning || isResting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _fs.isRunning && !isResting) _confirmEnd();
          },
          child: _fs.isRunning ? _buildFullscreenFocus() : _buildSetupView(),
        );
      },
    );
  }

  // ══════════════════════════════════════════
  //  설정 뷰 (세션 시작 전)
  // ══════════════════════════════════════════

  Widget _buildSetupView() {
    final subjColor = BotanicalColors.subjectColor(_subj);
    return Scaffold(
      backgroundColor: _dk ? const Color(0xFF0F1117) : const Color(0xFFF8F6F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('집중 세션', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _textMain),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: Icon(Icons.history_rounded, size: 22, color: _textMuted),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const FocusHistoryScreen())),
          ),
        ],
      ),
      body: Stack(children: [
        // 보태니컬 배경
        Positioned.fill(child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: _dk
                ? [const Color(0xFF0F1117), const Color(0xFF161822), const Color(0xFF0F1117)]
                : [const Color(0xFFF8F6F2), const Color(0xFFFCF9F3), const Color(0xFFF4EEE4)],
            ),
          ),
        )),
        Positioned(top: -60, right: -40,
          child: Container(width: 180, height: 180,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [subjColor.withOpacity(0.08), subjColor.withOpacity(0)])))),
        Positioned(bottom: 80, left: -60,
          child: Container(width: 140, height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [BotanicalColors.primary.withOpacity(0.06), Colors.transparent])))),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── 선택 과목 프리뷰 헤더 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    subjColor.withOpacity(_dk ? 0.12 : 0.08),
                    subjColor.withOpacity(_dk ? 0.04 : 0.02)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: subjColor.withOpacity(0.15))),
              child: Column(children: [
                Text(SubjectConfig.subjects[_subj]?.emoji ?? '📚',
                  style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(_subj, style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: subjColor)),
                const SizedBox(height: 4),
                Text(_mode == 'study' ? '📖 집중공부 · 순공 100%' : '🎧 강의듣기 · 순공 50%',
                  style: TextStyle(fontSize: 12, color: _textMuted)),
              ]),
            ),

            // ── 과목 선택 ──
            Row(children: [
              Text('과목 선택', style: BotanicalTypo.heading(size: 16, color: _textMain)),
              const Spacer(),
              GestureDetector(
                onTap: _manageSubjects,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: BotanicalColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_note_rounded, size: 16, color: BotanicalColors.primary),
                    const SizedBox(width: 4),
                    Text('관리', style: BotanicalTypo.label(size: 12, weight: FontWeight.w600,
                      color: BotanicalColors.primary)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: SubjectConfig.subjects.entries.map((e) {
                final sel = _subj == e.key;
                final c = BotanicalColors.subjectColor(e.key);
                return GestureDetector(
                  onTap: () => setState(() => _subj = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: sel
                      ? BotanicalDeco.selectedChip(c, _dk)
                      : BotanicalDeco.unselectedChip(_dk),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(e.key, style: BotanicalTypo.body(
                        size: 13, weight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? c : _textMain)),
                    ]),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // ── 학습 모드 ──
            Text('학습 모드', style: BotanicalTypo.heading(size: 16, color: _textMain)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _modeCard('📖', '집중공부', '순공 100%', 'study', BotanicalColors.primary)),
              const SizedBox(width: 10),
              Expanded(child: _modeCard('🎧', '강의듣기', '순공 50%', 'lecture', BotanicalColors.subjectData)),
            ]),

            const SizedBox(height: 20),

            // ── 앱 집중모드 ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BotanicalDeco.card(_dk),
              child: SwitchListTile(
                title: Text('앱 집중모드', style: BotanicalTypo.body(
                  size: 14, weight: FontWeight.w600, color: _textMain)),
                subtitle: Text('SNS · 영상 앱 자동 차단', style: BotanicalTypo.label(
                  size: 11, color: _textMuted)),
                value: _focusMode,
                onChanged: (v) => setState(() => _focusMode = v),
                activeColor: BotanicalColors.error,
                contentPadding: EdgeInsets.zero, dense: true,
              ),
            ),

            const SizedBox(height: 32),

            // ── 시작 버튼 ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _start,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subjColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  shadowColor: subjColor.withOpacity(0.3)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.play_arrow_rounded, size: 26),
                  const SizedBox(width: 8),
                  Text('세션 시작', style: BotanicalTypo.heading(size: 17, color: Colors.white)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }

  Widget _modeCard(String emoji, String title, String sub, String m, Color c) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: sel
          ? BotanicalDeco.selectedChip(c, _dk, radius: 16)
          : BotanicalDeco.unselectedChip(_dk, radius: 16),
        child: Column(children: [
          Text('$emoji $title', style: BotanicalTypo.body(size: 13, weight: FontWeight.w700,
            color: sel ? c : _textMain)),
          const SizedBox(height: 4),
          Text(sub, style: BotanicalTypo.label(size: 11, color: _textMuted)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  전체화면 몰입형 포커스
  // ══════════════════════════════════════════

  Widget _buildFullscreenFocus() {
    final st = _fs.getCurrentState();
    final subjColor = BotanicalColors.subjectColor(st.subject);
    final modeEmoji = st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕';
    final modeLabel = st.mode == 'study' ? '집중공부' : st.mode == 'lecture' ? '강의듣기' : '휴식 중';
    final isResting = st.mode == 'rest';

    return Scaffold(
      backgroundColor: isResting ? const Color(0xFF1A1A2E) : const Color(0xFF0A0A12),
      body: Stack(children: [
        SafeArea(
          child: Column(children: [
            // ── 상단 바 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => _showSubjectPicker(st.subject),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: subjColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: subjColor.withOpacity(0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(SubjectConfig.subjects[st.subject]?.emoji ?? '📚',
                        style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(st.subject, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: subjColor)),
                      const SizedBox(width: 4),
                      Icon(Icons.unfold_more_rounded, size: 14, color: subjColor.withOpacity(0.6)),
                    ]),
                  ),
                ),
                const Spacer(),
                _cradleIndicator(),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text('순공 ${st.effectiveTimeFormatted}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: subjColor.withOpacity(0.9))),
                ),
              ]),
            ),

            // ── 메인 타이머 ──
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final opacity = isResting
                        ? 0.4 + _pulseCtrl.value * 0.6
                        : 0.7 + _pulseCtrl.value * 0.3;
                      return Text('$modeEmoji $modeLabel',
                        style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600,
                          color: (isResting ? Colors.orange : subjColor).withOpacity(opacity),
                          letterSpacing: 2));
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    st.mainTimerFormatted,
                    style: TextStyle(
                      fontSize: 72, fontWeight: FontWeight.w200, color: Colors.white,
                      letterSpacing: -2, fontFamily: 'monospace',
                      shadows: [
                        Shadow(color: subjColor.withOpacity(0.3), blurRadius: 40),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '세그먼트 ${st.segmentTimeFormatted}',
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35),
                      letterSpacing: 1),
                  ),
                  const SizedBox(height: 32),
                  _cycleBar(st, subjColor),
                ]),
              ),
            ),

            // ── 문제 서브타이머 ──
            if (!isResting) _problemSubTimer(subjColor),

            // ── 하단 통계 ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _miniStat('📖', '${st.totalStudyMin}m', '공부'),
                _divider(),
                _miniStat('🎧', '${st.totalLectureMin}m', '강의'),
                _divider(),
                _miniStat('☕', '${st.totalRestMin}m', '휴식'),
                _divider(),
                _miniStat('⏱️', st.sessionTimeFormatted, '세션'),
              ]),
            ),
            const SizedBox(height: 16),

            // ── 모드 전환 버튼 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                _modeBtn('📖', '공부', 'study', subjColor, st.mode),
                const SizedBox(width: 10),
                _modeBtn('🎧', '강의', 'lecture', const Color(0xFF3B7A57), st.mode),
                const SizedBox(width: 10),
                _modeBtn('☕', '휴식', 'rest', Colors.orange, st.mode),
                const SizedBox(width: 10),
                _bathroomBtn(),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _minimizeToHome,
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blue.withOpacity(0.3))),
                    child: const Icon(Icons.home_rounded, color: Colors.blueAccent, size: 24),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _confirmEnd,
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.withOpacity(0.3))),
                    child: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 26),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        ),
        if (_fs.cradlePaused) _cradleRestOverlay(),
      ]),
    );
  }

  // ── 위젯 빌더 ──

  Widget _cycleBar(FocusTimerState st, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('사이클 ${st.cycleCount + 1}',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
          Text('${(st.cycleProgress * 90).round()}/90분',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.4))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: st.cycleProgress.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation(c.withOpacity(0.7)),
          ),
        ),
      ]),
    );
  }

  Widget _problemSubTimer(Color subjColor) {
    final elapsed = _fs.problemElapsedSec;
    final mm = elapsed ~/ 60;
    final ss = elapsed % 60;
    final timerStr = '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    final laps = _fs.problemLaps;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: subjColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: subjColor.withOpacity(0.12))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('⏱️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('문제 타이머', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.5), letterSpacing: 1)),
          const Spacer(),
          if (laps.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: subjColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
              child: Text('${laps.length}문제',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: subjColor.withOpacity(0.8))),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(
            _fs.subTimerActive ? timerStr : '--:--',
            style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w300,
              color: _fs.subTimerActive ? subjColor : Colors.white.withOpacity(0.2),
              fontFamily: 'monospace', letterSpacing: 2),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              if (!_fs.subTimerActive) {
                _fs.toggleSubTimer();
              } else {
                // 랩 기록 + 리셋
                if (_fs.problemStart != null) {
                  final sec = DateTime.now().difference(_fs.problemStart!).inSeconds;
                  if (sec >= 3) {
                    _fs.toggleSubTimer(); // records lap
                    _fs.toggleSubTimer(); // restarts
                  } else {
                    _fs.toggleSubTimer();
                    _fs.toggleSubTimer();
                  }
                }
              }
              HapticFeedback.lightImpact();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: subjColor.withOpacity(_fs.subTimerActive ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: subjColor.withOpacity(0.3))),
              child: Text(
                _fs.subTimerActive ? '다음 문제' : '시작',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: subjColor)),
            ),
          ),
          if (_fs.subTimerActive) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _fs.toggleSubTimer(); // stop + record
                HapticFeedback.lightImpact();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
                child: const Text('정지',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: Colors.redAccent)),
              ),
            ),
          ],
        ]),
        if (laps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: laps.reversed.take(5).toList().asMap().entries.map((e) {
                final lap = e.value;
                final idx = laps.length - e.key;
                final lm = lap.seconds ~/ 60;
                final ls = lap.seconds % 60;
                return Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('#$idx', style: TextStyle(
                      fontSize: 9, color: Colors.white.withOpacity(0.3))),
                    Text('${lm}:${ls.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.6), fontFamily: 'monospace')),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _cradleIndicator() {
    final magnitude = _magnet.lastMagnitude;
    final on = _fs.isOnCradle;
    final Color c;
    final String label;
    if (on) {
      c = const Color(0xFF10B981);
      label = '거치대';
    } else if (magnitude > 0) {
      c = const Color(0xFFEF4444);
      label = '분리됨';
    } else {
      c = Colors.grey;
      label = '자석 ∅';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c,
            boxShadow: on ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)] : null)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }

  Widget _cradleRestOverlay() {
    final restSec = _fs.cradleRestSec;
    final mm = restSec ~/ 60;
    final ss = restSec % 60;
    final rate = _fs.concentrationRate;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('☕', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text('휴식 중',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('거치대에 올려놓으면 자동 재개됩니다',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
              const SizedBox(height: 20),
              Text('${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Color(0xFFFBBF24), fontSize: 36,
                  fontWeight: FontWeight.w300, fontFamily: 'monospace')),
              const SizedBox(height: 24),
              if (_fs.cradleFocusSec + _fs.cradleRestSec > 30)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('집중도 ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    Text('$rate%',
                      style: TextStyle(
                        color: _concentrationColor(rate),
                        fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(' · 휴식 ${_fs.cradleRestCount}회',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () {
                  _fs.onCradleChanged(true); // force cradle on
                  HapticFeedback.mediumImpact();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4))),
                  child: const Text('수동 재개',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String emoji, String val, String label) {
    return Column(children: [
      Text('$emoji $val', style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        fontSize: 10, color: Colors.white.withOpacity(0.3))),
    ]);
  }

  Widget _divider() => Container(
    width: 1, height: 28,
    color: Colors.white.withOpacity(0.06));

  Widget _modeBtn(String emoji, String label, String m, Color c, String current) {
    final sel = current == m;
    return Expanded(
      child: GestureDetector(
        onTap: sel ? null : () => _fs.switchMode(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            color: sel ? c.withOpacity(0.2) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: sel ? Border.all(color: c.withOpacity(0.5), width: 1.5) : null),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            Text(label, style: TextStyle(
              fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? c : Colors.white.withOpacity(0.4))),
          ]),
        ),
      ),
    );
  }

  Widget _bathroomBtn() {
    final active = _fs.isBathroomBreak;
    final sec = _fs.bathroomSec;
    return GestureDetector(
      onTap: active ? null : _showBathroomDialog,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: active ? Colors.teal.withOpacity(0.25) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: active ? Border.all(color: Colors.teal.withOpacity(0.5), width: 1.5) : null),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(active ? '⏳' : '🚻', style: const TextStyle(fontSize: 16)),
          if (active)
            Text('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.tealAccent))
          else
            Text('화장실', style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.4))),
        ]),
      ),
    );
  }

  Color _concentrationColor(int rate) {
    if (rate >= 90) return const Color(0xFF10B981);
    if (rate >= 70) return const Color(0xFFFBBF24);
    if (rate >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  // ══════════════════════════════════════════
  //  액션 핸들러
  // ══════════════════════════════════════════

  Future<void> _start() async {
    await _fs.startSession(subject: _subj, mode: _mode);
    if (_focusMode) {
      final fm = FocusModeService();
      await fm.requestPermissions();
      await fm.activate();
    }
    _enterImmersive();
  }

  void _confirmEnd() {
    final st = _fs.getCurrentState();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('세션 종료', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _endStatRow('순공시간', st.effectiveTimeFormatted),
          _endStatRow('집중공부', '${st.totalStudyMin}분'),
          _endStatRow('강의듣기', '${st.totalLectureMin}분'),
          _endStatRow('휴식시간', '${st.totalRestMin}분'),
          _endStatRow('세션경과', st.sessionTimeFormatted),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('계속하기', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              final cycle = await _fs.endSession();
              _exitImmersive();
              try { await FocusModeService().deactivate(); } catch (_) {}
              if (mounted) {
                showFocusResultDialog(
                  context: context,
                  cycle: cycle,
                  dk: _dk,
                  textMain: _textMain,
                  textSub: _textSub,
                  textMuted: _textMuted,
                  cradleFocusSec: _fs.cradleFocusSec,
                  cradleRestSec: _fs.cradleRestSec,
                  cradleRestCount: _fs.cradleRestCount,
                  magnetEnabled: _magnet.isEnabled,
                );
              }
            },
            child: const Text('종료', style: TextStyle(color: Colors.redAccent,
              fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _endStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white54)),
        Text(value, style: const TextStyle(fontSize: 14,
          fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    );
  }

  void _showBathroomDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dk ? const Color(0xFF1E2130) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('🚻', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Text('화장실', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: _textMain)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _bathroomOption(ctx, '💧', '소변', '2분', 2),
          const SizedBox(height: 10),
          _bathroomOption(ctx, '🚽', '대변', '5분', 5),
        ]),
      ),
    );
  }

  Widget _bathroomOption(BuildContext ctx, String emoji, String label, String time, int minutes) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _fs.startBathroomBreak();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _dk ? Colors.teal.withOpacity(0.1) : Colors.teal.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.withOpacity(0.2))),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: _textMain)),
            Text(time, style: TextStyle(fontSize: 11, color: _textMuted)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _textMuted),
        ]),
      ),
    );
  }

  void _showSubjectPicker(String currentSubj) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('과목 변경', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10,
              children: SubjectConfig.subjects.entries.map((e) {
                final sel = currentSubj == e.key;
                final c = BotanicalColors.subjectColor(e.key);
                return GestureDetector(
                  onTap: () {
                    if (!sel) _fs.changeSubject(e.key);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? c.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: sel ? Border.all(color: c.withOpacity(0.5), width: 1.5) : null),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(e.key, style: TextStyle(
                        fontSize: 14, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? c : Colors.white.withOpacity(0.7))),
                    ]),
                  ),
                );
              }).toList()),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  void _manageSubjects() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBS) {
          final subjects = SubjectConfig.subjects;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom +
                        MediaQuery.of(ctx).padding.bottom + 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: _textMuted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  Text('과목 관리', style: BotanicalTypo.heading(size: 16, color: _textMain)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final ok = await showDialog<bool>(context: ctx,
                        builder: (_) => AlertDialog(
                          title: const Text('기본값 복원'),
                          content: const Text('과목 목록을 기본값으로 되돌리시겠습니까?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('복원')),
                          ]));
                      if (ok == true) {
                        await SubjectConfig.resetToDefaults();
                        setBS(() {});
                        setState(() {});
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8)),
                      child: Text('초기화', style: BotanicalTypo.label(size: 11,
                        weight: FontWeight.w600, color: Colors.orange)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _addSubjectDialog(ctx, setBS),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: BotanicalColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 16, color: BotanicalColors.primary),
                        const SizedBox(width: 4),
                        Text('추가', style: BotanicalTypo.label(size: 12,
                          weight: FontWeight.w600, color: BotanicalColors.primary)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                ...subjects.entries.map((e) {
                  final c = Color(e.value.colorValue);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.withOpacity(0.12))),
                    child: Row(children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Text(e.key, style: BotanicalTypo.body(size: 14, weight: FontWeight.w700,
                        color: _textMain)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _editSubjectDialog(e.key, e.value, ctx, setBS),
                        child: Padding(padding: const EdgeInsets.all(6),
                          child: Icon(Icons.edit_rounded, size: 18, color: _textMuted)),
                      ),
                      GestureDetector(
                        onTap: () async {
                          await SubjectConfig.removeSubject(e.key);
                          await Future.delayed(const Duration(milliseconds: 200));
                          setBS(() {});
                          setState(() {});
                        },
                        child: Padding(padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.delete_outline_rounded, size: 18,
                            color: Colors.redAccent)),
                      ),
                    ]),
                  );
                }),
              ]),
            ),
          );
        },
      ),
    );
  }

  static const _subjectColors = [
    0xFF6366F1, 0xFF10B981, 0xFFF59E0B, 0xFFEF4444, 0xFF3B82F6,
    0xFF8B5CF6, 0xFFEC4899, 0xFF14B8A6, 0xFFF97316, 0xFF06B6D4,
  ];

  void _editSubjectDialog(String oldName, SubjectInfo info, BuildContext ctx, StateSetter setBS) {
    final nameCtrl = TextEditingController(text: oldName);
    final emojiCtrl = TextEditingController(text: info.emoji);
    int selectedColor = info.colorValue;
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('과목 수정'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: '과목명', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: emojiCtrl,
              decoration: const InputDecoration(labelText: '이모지', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _subjectColors.map((c) => GestureDetector(
                onTap: () => setDlg(() => selectedColor = c),
                child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color(c), borderRadius: BorderRadius.circular(8),
                    border: selectedColor == c
                      ? Border.all(color: Colors.white, width: 3) : null,
                    boxShadow: selectedColor == c
                      ? [BoxShadow(color: Color(c).withOpacity(0.5), blurRadius: 8)] : null)),
              )).toList()),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final emoji = emojiCtrl.text.trim();
                if (name.isEmpty) return;
                await SubjectConfig.updateSubject(oldName, name, emoji.isEmpty ? '📚' : emoji, selectedColor);
                if (_subj == oldName) _subj = name;
                if (dCtx.mounted) Navigator.pop(dCtx);
                setBS(() {});
                setState(() {});
              },
              child: const Text('저장')),
          ],
        ),
      ),
    );
  }

  void _addSubjectDialog(BuildContext ctx, StateSetter setBS) {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController(text: '📚');
    int selectedColor = _subjectColors.first;
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('과목 추가'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: '과목명', hintText: '국어')),
            const SizedBox(height: 12),
            TextField(controller: emojiCtrl,
              decoration: const InputDecoration(labelText: '이모지', hintText: '📚'),
              style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _subjectColors.map((c) => GestureDetector(
                onTap: () => setDlg(() => selectedColor = c),
                child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color(c), borderRadius: BorderRadius.circular(8),
                    border: selectedColor == c
                      ? Border.all(color: Colors.white, width: 3) : null,
                    boxShadow: selectedColor == c
                      ? [BoxShadow(color: Color(c).withOpacity(0.5), blurRadius: 8)] : null)),
              )).toList()),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final emoji = emojiCtrl.text.trim();
                if (name.isEmpty) return;
                await SubjectConfig.addSubject(name, emoji.isEmpty ? '📚' : emoji, selectedColor);
                if (dCtx.mounted) Navigator.pop(dCtx);
                setBS(() {});
                setState(() {});
              },
              child: const Text('추가')),
          ],
        ),
      ),
    );
  }
}
