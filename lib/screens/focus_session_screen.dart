import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/focus_timer_service.dart';
import '../services/focus_mode_service.dart';
import '../services/firebase_service.dart';
import '../services/magnet_service.dart';
import '../services/creature_service.dart';

class FocusSessionScreen extends StatefulWidget {
  const FocusSessionScreen({super.key});
  @override
  State<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<FocusSessionScreen>
    with TickerProviderStateMixin {
  String _subj = '자료해석';
  String _mode = 'study';
  bool _focusMode = true;
  final _ft = FocusTimerService();
  Timer? _uiTimer;
  Timer? _bathroomTimer;
  int _bathroomSec = 0;
  String? _prevModeBeforeBathroom;
  late AnimationController _pulseCtrl;

  // ★ #10: 문제 시간 서브 타이머
  DateTime? _problemStart;
  final List<({int seconds, String subject})> _problemLaps = [];
  bool _subTimerActive = false;

  // ★ 자석 거치대
  final _magnet = MagnetService();
  StreamSubscription? _magnetSub;
  bool _isOnCradle = false;
  bool _cradlePaused = false; // 거치대에서 뗐을 때 자동 휴식
  bool _cradleAutoStarted = false; // 포커스 화면에서 자동 활성화 여부
  String? _preModeBeforeCradle; // 거치대 분리 전 모드
  int _cradleFocusSec = 0;    // 거치대 위 집중 시간
  int _cradleRestSec = 0;     // 거치대 분리 휴식 시간
  int _cradleRestCount = 0;   // 휴식 횟수
  final List<int> _cradleRestDurations = [];
  DateTime? _cradleRestStart;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    if (_ft.isRunning) {
      final st = _ft.getCurrentState();
      _subj = st.subject;
      _mode = st.mode;
      _startUiTimer();
      _enterImmersive();
    }
    SubjectConfig.load();

    // 자석 거치대 — 포커스 중에는 항상 활성화 (설정 상태 무관)
    _isOnCradle = _magnet.isOnCradle;
    if (!_magnet.isEnabled) {
      _magnet.start(); // 포커스 세션 동안 자동 시작
      _cradleAutoStarted = true;
    }
    _magnetSub = _magnet.cradleStream.listen(_onCradleChanged);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _bathroomTimer?.cancel();
    _magnetSub?.cancel();
    // 포커스 세션에서 자동 시작한 경우만 종료 (전역 설정 활성화면 유지)
    if (_cradleAutoStarted && !_magnet.isEnabled) {
      _magnet.stop();
    }
    _pulseCtrl.dispose();
    _exitImmersive();
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

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// ★ 바탕화면(홈 스크린)으로 나가기 — 세션은 유지
  void _minimizeToHome() {
    _exitImmersive();
    // moveTaskToBack을 통해 앱을 배경으로 보냄 (세션 계속 진행)
    const platform = MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');
    platform.invokeMethod('moveTaskToBack').catchError((_) {
      // Fallback: SystemNavigator로 백그라운드 전환
      SystemNavigator.pop(animated: true);
    });
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // 거치대 집중/휴식 시간 카운트
      if (_ft.isRunning) {
        if (_isOnCradle && !_cradlePaused) {
          _cradleFocusSec++;
        } else if (_cradlePaused) {
          _cradleRestSec++;
        }
      }
      // 타이머는 build phase 밖에서 실행됨 → 직접 setState
      setState(() {});
    });
  }

  void _onCradleChanged(bool onCradle) {
    if (!_ft.isRunning) return;
    if (onCradle) {
      _onCradleOn();
    } else {
      _onCradleOff();
    }
  }

  void _onCradleOn() {
    debugPrint('[Focus] cradle ON');
    HapticFeedback.mediumImpact();
    // 휴식 기록 종료
    if (_cradleRestStart != null) {
      final dur = DateTime.now().difference(_cradleRestStart!).inSeconds;
      if (dur > 2) _cradleRestDurations.add(dur);
      _cradleRestStart = null;
    }
    // 이전 모드 복귀
    if (_cradlePaused && _preModeBeforeCradle != null) {
      _ft.switchMode(_preModeBeforeCradle!);
      _preModeBeforeCradle = null;
    }
    _safeSetState(() {
      _isOnCradle = true;
      _cradlePaused = false;
    });
  }

  void _onCradleOff() {
    debugPrint('[Focus] cradle OFF');
    HapticFeedback.heavyImpact();
    final curMode = _ft.currentMode;
    // 이미 휴식 중이면 무시
    if (curMode == 'rest') {
      _safeSetState(() => _isOnCradle = false);
      return;
    }
    // 자동 휴식 전환
    _preModeBeforeCradle = curMode;
    _cradleRestStart = DateTime.now();
    _cradleRestCount++;
    _ft.switchMode('rest');
    _safeSetState(() {
      _isOnCradle = false;
      _cradlePaused = true;
    });
  }

  int get _concentrationRate {
    final total = _cradleFocusSec + _cradleRestSec;
    if (total == 0) return 100;
    return (_cradleFocusSec / total * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    // ★ #7: 휴식 모드일 때는 나가기 허용
    final isResting = _ft.isRunning && _ft.currentMode == 'rest';
    return PopScope(
      canPop: !_ft.isRunning || isResting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _ft.isRunning && !isResting) _confirmEnd();
      },
      child: _ft.isRunning ? _buildFullscreenFocus() : _buildSetupView(),
    );
  }

  // ══════════════════════════════════════════
  //  설정 뷰 (세션 시작 전)
  // ══════════════════════════════════════════

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

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
        // 장식 원
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
                  onTap: () => _safeSetState(() => _subj = e.key),
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
                onChanged: (v) => _safeSetState(() => _focusMode = v),
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

  // ══════════════════════════════════════════
  //  🎯 전체화면 몰입형 포커스 모드
  // ══════════════════════════════════════════

  Widget _buildFullscreenFocus() {
    final st = _ft.getCurrentState();
    final subjColor = BotanicalColors.subjectColor(st.subject);
    final modeEmoji = st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕';
    final modeLabel = st.mode == 'study' ? '집중공부' : st.mode == 'lecture' ? '강의듣기' : '휴식 중';
    final isResting = st.mode == 'rest';

    return Scaffold(
      backgroundColor: isResting ? const Color(0xFF1A1A2E) : const Color(0xFF0A0A12),
      body: Stack(children: [
        SafeArea(
        child: Column(children: [
          // ── 상단 바 (최소한) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              // 과목 칩 (탭하면 과목 변경)
              GestureDetector(
                onTap: () => _showSubjectPicker(st.subject),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: subjColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: subjColor.withOpacity(0.3)),
                  ),
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
              // 거치대 인디케이터 (항상 표시)
              _cradleIndicator(),
              const SizedBox(width: 8),
              // 순공시간 뱃지
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

          // ── 메인 타이머 영역 ──
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 모드 인디케이터
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

                // 큰 타이머 숫자
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

                // 세그먼트 시간
                Text(
                  '세그먼트 ${st.segmentTimeFormatted}',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35),
                    letterSpacing: 1),
                ),
                const SizedBox(height: 32),

                // 90분 사이클 바
                _immersiveCycleBar(st, subjColor),
              ]),
            ),
          ),

          // ★ #10: 문제 서브 타이머
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
              _immersiveModeBtn('📖', '공부', 'study', subjColor, st.mode),
              const SizedBox(width: 10),
              _immersiveModeBtn('🎧', '강의', 'lecture', const Color(0xFF3B7A57), st.mode),
              const SizedBox(width: 10),
              _immersiveModeBtn('☕', '휴식', 'rest', Colors.orange, st.mode),
              const SizedBox(width: 10),
              // 화장실 버튼
              _bathroomBtn(st.mode),
              const SizedBox(width: 10),
              // ★ 바탕화면 나가기 버튼
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
              // 종료 버튼
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
      // ★ 거치대 분리 시 휴식 오버레이
      if (_cradlePaused) _cradleRestOverlay(),
      ]),
    );
  }

  // ★ #10: 문제 시간 서브 타이머 위젯
  Widget _problemSubTimer(Color subjColor) {
    final elapsed = _subTimerActive && _problemStart != null
        ? DateTime.now().difference(_problemStart!).inSeconds
        : 0;
    final mm = elapsed ~/ 60;
    final ss = elapsed % 60;
    final timerStr = '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: subjColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: subjColor.withOpacity(0.12))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('⏱️', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('문제 타이머', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.5), letterSpacing: 1)),
          const Spacer(),
          // 랩 기록 수
          if (_problemLaps.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: subjColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
              child: Text('${_problemLaps.length}문제',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: subjColor.withOpacity(0.8))),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          // 서브 타이머 표시
          Text(
            _subTimerActive ? timerStr : '--:--',
            style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w300,
              color: _subTimerActive ? subjColor : Colors.white.withOpacity(0.2),
              fontFamily: 'monospace', letterSpacing: 2),
          ),
          const Spacer(),
          // 시작/랩 버튼
          GestureDetector(
            onTap: () {
              _safeSetState(() {
                if (!_subTimerActive) {
                  // 시작
                  _subTimerActive = true;
                  _problemStart = DateTime.now();
                } else {
                  // 랩 기록 + 리셋
                  if (_problemStart != null) {
                    final sec = DateTime.now().difference(_problemStart!).inSeconds;
                    if (sec >= 3) { // 3초 이상만 기록
                      _problemLaps.add((seconds: sec, subject: _subj));
                    }
                  }
                  _problemStart = DateTime.now();
                }
              });
              HapticFeedback.lightImpact();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: subjColor.withOpacity(_subTimerActive ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: subjColor.withOpacity(0.3))),
              child: Text(
                _subTimerActive ? '다음 문제' : '시작',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: subjColor)),
            ),
          ),
          if (_subTimerActive) ...[
            const SizedBox(width: 8),
            // 정지 버튼
            GestureDetector(
              onTap: () {
                _safeSetState(() {
                  if (_problemStart != null) {
                    final sec = DateTime.now().difference(_problemStart!).inSeconds;
                    if (sec >= 3) {
                      _problemLaps.add((seconds: sec, subject: _subj));
                    }
                  }
                  _subTimerActive = false;
                  _problemStart = null;
                });
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
        // 최근 랩 기록 (최대 3개)
        if (_problemLaps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: _problemLaps.reversed.take(5).toList().asMap().entries.map((e) {
                final lap = e.value;
                final idx = _problemLaps.length - e.key;
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

  // ★ 거치대 상태 인디케이터 (항상 표시)
  Widget _cradleIndicator() {
    // 자기장 감지 중 — 값에 따라 색상 결정
    final magnitude = _magnet.lastMagnitude;
    final on = _isOnCradle;
    final Color c;
    final String label;
    if (on) {
      c = const Color(0xFF10B981);
      label = '거치대';
    } else if (magnitude > 0) {
      c = const Color(0xFFEF4444);
      label = '분리됨';
    } else {
      // 센서 초기화 중 또는 미지원
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

  // ★ 거치대 분리 → 휴식 오버레이
  Widget _cradleRestOverlay() {
    final restSec = _cradleRestStart != null
        ? DateTime.now().difference(_cradleRestStart!).inSeconds
        : 0;
    final mm = restSec ~/ 60;
    final ss = restSec % 60;
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
              // 집중도 뱃지
              if (_cradleFocusSec + _cradleRestSec > 30)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('집중도 ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    Text('$_concentrationRate%',
                      style: TextStyle(
                        color: _concentrationColor(_concentrationRate),
                        fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(' · 휴식 ${_cradleRestCount}회',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 32),
              // 수동 재개 버튼
              GestureDetector(
                onTap: () {
                  // 수동 재개 (거치대 없이)
                  if (_cradleRestStart != null) {
                    final dur = DateTime.now().difference(_cradleRestStart!).inSeconds;
                    if (dur > 2) _cradleRestDurations.add(dur);
                    _cradleRestStart = null;
                  }
                  if (_preModeBeforeCradle != null) {
                    _ft.switchMode(_preModeBeforeCradle!);
                    _preModeBeforeCradle = null;
                  }
                  _safeSetState(() => _cradlePaused = false);
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

  Color _concentrationColor(int rate) {
    if (rate >= 90) return const Color(0xFF10B981);
    if (rate >= 70) return const Color(0xFFFBBF24);
    if (rate >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _immersiveCycleBar(FocusTimerState st, Color c) {
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

  Widget _immersiveModeBtn(String emoji, String label, String m, Color c, String current) {
    final sel = current == m;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!sel) {
            // switchMode의 상태 업데이트(_currentMode, _segmentStart)는 동기적으로 실행됨
            // await 없이 즉시 UI 반영
            _ft.switchMode(m);
            setState(() {});
          }
        },
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

  // ══════════════════════════════════════════
  //  #9: 화장실 버튼 + 타이머
  // ══════════════════════════════════════════

  Widget _bathroomBtn(String currentMode) {
    final active = _bathroomSec > 0;
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
            Text('${_bathroomSec ~/ 60}:${(_bathroomSec % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.tealAccent))
          else
            Text('화장실', style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.4))),
        ]),
      ),
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
        _startBathroomBreak(minutes);
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

  void _startBathroomBreak(int minutes) {
    final st = _ft.getCurrentState();
    _prevModeBeforeBathroom = st.mode;
    if (st.mode != 'rest') {
      _ft.switchMode('rest');
    }
    _bathroomSec = minutes * 60;
    _bathroomTimer?.cancel();
    _bathroomTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      _safeSetState(() => _bathroomSec--);
      if (_bathroomSec <= 0) {
        t.cancel();
        _endBathroomBreak();
      }
    });
    _safeSetState(() {});
  }

  void _endBathroomBreak() {
    _bathroomTimer?.cancel();
    _bathroomSec = 0;
    // 이전 모드 복귀
    final restore = _prevModeBeforeBathroom ?? 'study';
    _prevModeBeforeBathroom = null;
    _ft.switchMode(restore);
    // 진동
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 300), () {
      HapticFeedback.heavyImpact();
    });
    // 스낵바
    if (mounted) {
      _safeSetState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚻 화장실 완료 → ${restore == 'study' ? '📖 공부' : '🎧 강의'} 모드 복귀'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ══════════════════════════════════════════
  //  과목 변경 (세션 중)
  // ══════════════════════════════════════════

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
                    if (!sel) {
                      _ft.changeSubject(e.key);
                      if (mounted) setState(() {});
                    }
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

  // ══════════════════════════════════════════
  //  과목 관리 (추가/삭제)
  // ══════════════════════════════════════════

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
                bottom: sheetBottomPad(ctx, extra: 16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: _textMuted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  Text('과목 관리', style: BotanicalTypo.heading(size: 16, color: _textMain)),
                  const Spacer(),
                  // 초기화 버튼
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
                        _safeSetState(() {});
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
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.withOpacity(0.15))),
                    child: Row(children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.key, style: BotanicalTypo.body(
                        size: 14, weight: FontWeight.w600, color: _textMain))),
                      // 수정 버튼
                      GestureDetector(
                        onTap: () => _editSubjectDialog(ctx, setBS, e.key, e.value),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.edit_outlined, size: 16, color: Colors.blueAccent),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 삭제 버튼
                      GestureDetector(
                        onTap: () async {
                          if (subjects.length <= 1) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('최소 1개 과목은 필요합니다')));
                            return;
                          }
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('과목 삭제'),
                              content: Text('"${e.key}" 과목을 삭제하시겠습니까?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('취소')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('삭제', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await SubjectConfig.removeSubject(e.key);
                            // 현재 선택된 과목이 삭제되면 첫 과목으로 변경
                            if (_subj == e.key && SubjectConfig.subjects.isNotEmpty) {
                              _subj = SubjectConfig.subjects.keys.first;
                            }
                            setBS(() {});
                            if (mounted) _safeSetState(() {});
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.delete_outline_rounded,
                            size: 16, color: Colors.redAccent),
                        ),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 8),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _editSubjectDialog(BuildContext ctx, StateSetter setBS, String oldName, SubjectInfo info) {
    final nameCtrl = TextEditingController(text: oldName);
    final emojiCtrl = TextEditingController(text: info.emoji);
    int selectedColor = info.colorValue;
    final colors = [
      0xFF6366F1, 0xFF10B981, 0xFFF59E0B, 0xFFEF4444, 0xFF3B82F6,
      0xFF8B5CF6, 0xFFEC4899, 0xFF14B8A6, 0xFFF97316, 0xFF06B6D4,
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('과목 수정'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: '과목명', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: emojiCtrl,
              decoration: const InputDecoration(labelText: '이모지', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: colors.map((c) => GestureDetector(
                onTap: () => setDlg(() => selectedColor = c),
                child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color(c), borderRadius: BorderRadius.circular(8),
                    border: selectedColor == c ? Border.all(color: Colors.white, width: 3) : null,
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
                _safeSetState(() {});
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  void _addSubjectDialog(BuildContext ctx, StateSetter setBS) {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController(text: '📚');
    int selectedColor = 0xFF6366F1;
    final colors = [
      0xFF6366F1, 0xFF10B981, 0xFFF59E0B, 0xFFEF4444, 0xFF3B82F6,
      0xFF8B5CF6, 0xFFEC4899, 0xFF14B8A6, 0xFFF97316, 0xFF06B6D4,
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('과목 추가'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '과목명', hintText: '예: 행정법',
                border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emojiCtrl,
              decoration: const InputDecoration(
                labelText: '이모지', hintText: '📚',
                border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: colors.map((c) => GestureDetector(
                onTap: () => setDlg(() => selectedColor = c),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    borderRadius: BorderRadius.circular(8),
                    border: selectedColor == c
                      ? Border.all(color: Colors.white, width: 3) : null,
                    boxShadow: selectedColor == c
                      ? [BoxShadow(color: Color(c).withOpacity(0.5), blurRadius: 8)] : null),
                ),
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
                // SharedPreferences 쓰기 완료 대기
                await Future.delayed(const Duration(milliseconds: 300));
                setBS(() {});
                _safeSetState(() {});
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  포커스 기록 (F7)
  // ══════════════════════════════════════════

  void _openHistory() {
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => const FocusHistoryScreen()));
  }

  // ══════════════════════════════════════════
  //  공통 위젯
  // ══════════════════════════════════════════

  Widget _modeCard(String emoji, String title, String sub, String m, Color c) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () => _safeSetState(() => _mode = m),
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

  // ── 액션 ──

  Future<void> _start() async {
    await _ft.startSession(subject: _subj, mode: _mode);
    if (_focusMode) {
      final fm = FocusModeService();
      await fm.requestPermissions();
      await fm.activate();
    }
    _startUiTimer();
    _enterImmersive();
    _safeSetState(() {});
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (dCtx) {
        final st = _ft.getCurrentState();
        return AlertDialog(
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
                final cycle = await _ft.endSession();
                _uiTimer?.cancel();
                _exitImmersive();
                // 집중모드 해제
                try { await FocusModeService().deactivate(); } catch (_) {}
                if (mounted) {
                  _showEndSummary(cycle);
                }
              },
              child: const Text('종료', style: TextStyle(color: Colors.redAccent,
                fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
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

  void _showEndSummary(FocusCycle cycle) {
    final c = BotanicalColors.subjectColor(cycle.subject);
    final usedCradle = _magnet.isEnabled && (_cradleFocusSec + _cradleRestSec > 30);
    final rate = _concentrationRate;
    // 집중도 보너스
    int bonus = 0;
    if (usedCradle) {
      if (rate >= 90) bonus = 5;
      else if (rate >= 80) bonus = 3;
      else if (rate >= 70) bonus = 1;
    }
    // 보너스 EXP 지급
    if (bonus > 0) {
      try { CreatureService().addStudyReward(bonus); } catch (_) {}
    }
    // 거치대 통계 초기화
    _cradleFocusSec = 0;
    _cradleRestSec = 0;
    _cradleRestCount = 0;
    _cradleRestDurations.clear();
    _cradleRestStart = null;
    _cradlePaused = false;
    _preModeBeforeCradle = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Text('🎉', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('세션 완료!', style: BotanicalTypo.heading(size: 20, color: _textMain)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text('순공 ${cycle.effectiveMin}분', style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, color: c)),
              const SizedBox(height: 8),
              Text('${SubjectConfig.subjects[cycle.subject]?.emoji ?? '📚'} ${cycle.subject}',
                style: BotanicalTypo.body(size: 14, color: _textSub)),
              const SizedBox(height: 8),
              Text('공부 ${cycle.studyMin}분 · 강의 ${cycle.lectureMin}분 · 휴식 ${cycle.restMin}분',
                style: BotanicalTypo.label(size: 12, color: _textMuted)),
            ]),
          ),
          // 거치대 집중도 표시
          if (usedCradle) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _concentrationColor(rate).withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _concentrationColor(rate).withOpacity(0.2))),
              child: Column(children: [
                Text('집중도', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: _textMuted)),
                const SizedBox(height: 4),
                Text('$rate%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                  color: _concentrationColor(rate))),
                if (bonus > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text('보너스 +$bonus EXP',
                      style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11,
                        fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx);
              _safeSetState(() {});
            },
            child: Text('확인', style: TextStyle(
              fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════
//  📋 포커스 기록 화면 (F7: 조회/수정/삭제)
// ══════════════════════════════════════════

class FocusHistoryScreen extends StatefulWidget {
  const FocusHistoryScreen({super.key});
  @override
  State<FocusHistoryScreen> createState() => _FocusHistoryScreenState();
}

class _FocusHistoryScreenState extends State<FocusHistoryScreen> {
  final _fb = FirebaseService();
  String _selectedDate = '';
  List<FocusCycle> _cycles = [];
  bool _loading = true;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;

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
  void initState() {
    super.initState();
    _selectedDate = _today();
    _loadCycles();
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCycles() async {
    _safeSetState(() => _loading = true);
    try {
      _cycles = await _fb.getFocusCycles(_selectedDate);
      _cycles.sort((a, b) => b.startTime.compareTo(a.startTime));
    } catch (_) {
      _cycles = [];
    }
    if (mounted) _safeSetState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final totalEff = _cycles.fold<int>(0, (s, c) => s + c.effectiveMin);
    final totalStudy = _cycles.fold<int>(0, (s, c) => s + c.studyMin);
    final totalLecture = _cycles.fold<int>(0, (s, c) => s + c.lectureMin);
    final totalRest = _cycles.fold<int>(0, (s, c) => s + c.restMin);

    return Scaffold(
      backgroundColor: _dk ? const Color(0xFF1A1210) : const Color(0xFFFCF9F3),
      appBar: AppBar(
        title: Text('포커스 기록', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            tooltip: '수동 세션 추가',
            onPressed: _addManualSession),
        ],
      ),
      body: Column(children: [
        // ── 날짜 선택 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _changeDate(-1)),
            Expanded(child: GestureDetector(
              onTap: _pickDate,
              child: Text(_selectedDate, textAlign: TextAlign.center,
                style: BotanicalTypo.heading(size: 16, color: _textMain)),
            )),
            IconButton(icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _changeDate(1)),
          ]),
        ),

        // ── 일일 요약 ──
        if (_cycles.isNotEmpty) Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BotanicalDeco.card(_dk),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _dayStat('순공', '${totalEff}m', BotanicalColors.primary),
            _dayStat('공부', '${totalStudy}m', BotanicalColors.subjectData),
            _dayStat('강의', '${totalLecture}m', BotanicalColors.subjectVerbal),
            _dayStat('휴식', '${totalRest}m', Colors.orange),
            _dayStat('세션', '${_cycles.length}', _textSub),
          ]),
        ),
        const SizedBox(height: 12),

        // ── 세션 목록 ──
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _cycles.isEmpty
              ? Center(child: Text('이 날짜에 기록이 없습니다',
                  style: BotanicalTypo.body(size: 14, color: _textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _cycles.length,
                  itemBuilder: (_, i) => _cycleCard(_cycles[i]),
                ),
        ),
      ]),
    );
  }

  Widget _dayStat(String label, String val, Color c) {
    return Column(children: [
      Text(val, style: BotanicalTypo.number(size: 18, weight: FontWeight.w700, color: c)),
      Text(label, style: BotanicalTypo.label(size: 10, color: _textMuted)),
    ]);
  }

  Widget _cycleCard(FocusCycle cycle) {
    final c = BotanicalColors.subjectColor(cycle.subject);
    final startTime = _parseTime(cycle.startTime);
    final endTime = cycle.endTime != null ? _parseTime(cycle.endTime!) : '진행중';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(_dk ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(SubjectConfig.subjects[cycle.subject]?.emoji ?? '📚',
            style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cycle.subject, style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w700, color: _textMain)),
            Text('$startTime → $endTime', style: BotanicalTypo.label(
              size: 12, color: _textSub)),
          ])),
          Text('순공 ${cycle.effectiveMin}m', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        ]),
        const SizedBox(height: 8),
        // 세그먼트 바
        if (cycle.segments.isNotEmpty) _segmentBar(cycle),
        const SizedBox(height: 8),
        Row(children: [
          Text('공부 ${cycle.studyMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const SizedBox(width: 10),
          Text('강의 ${cycle.lectureMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const SizedBox(width: 10),
          Text('휴식 ${cycle.restMin}m', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          const Spacer(),
          GestureDetector(
            onTap: () => _editCycle(cycle),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.edit_outlined, size: 18, color: _textMuted)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _deleteCycle(cycle),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent)),
          ),
        ]),
      ]),
    );
  }

  Widget _segmentBar(FocusCycle cycle) {
    final totalMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
    if (totalMin <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(children: cycle.segments.map((s) {
          final w = s.durationMin / totalMin;
          final color = s.mode == 'study' ? BotanicalColors.primary
            : s.mode == 'lecture' ? BotanicalColors.subjectData
            : Colors.orange;
          return Expanded(
            flex: (w * 1000).round().clamp(1, 1000),
            child: Container(
              color: color.withOpacity(0.7),
              margin: const EdgeInsets.only(right: 1)),
          );
        }).toList()),
      ),
    );
  }

  String _parseTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(11, 16) : iso;
    }
  }

  void _changeDate(int delta) {
    final parts = _selectedDate.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
      .add(Duration(days: delta));
    _selectedDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    _loadCycles();
  }

  Future<void> _pickDate() async {
    final parts = _selectedDate.split('-');
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _selectedDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _loadCycles();
    }
  }

  Future<void> _editCycle(FocusCycle cycle) async {
    final subjects = SubjectConfig.subjects;
    String newSubject = cycle.subject;
    int studyMin = cycle.studyMin;
    int lectureMin = cycle.lectureMin;
    int restMin = cycle.restMin;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (_, setDlg) {
          int effMin = studyMin + (lectureMin * 0.5).round();
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('세션 수정'),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('과목 변경', style: BotanicalTypo.label(size: 13, color: _textSub)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: subjects.entries.map((e) {
                  final sel = newSubject == e.key;
                  return GestureDetector(
                    onTap: () => setDlg(() => newSubject = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? Color(e.value.colorValue).withOpacity(0.15) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: sel ? Border.all(color: Color(e.value.colorValue)) : null),
                      child: Text('${e.value.emoji} ${e.key}', style: TextStyle(
                        fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  );
                }).toList()),
              const SizedBox(height: 16),
              // F1: 분 단위 편집 (개선된 슬라이더 + ±버튼)
              _minuteEditor('📖 집중공부', studyMin,
                (v) => setDlg(() => studyMin = v.clamp(0, 600))),
              _minuteEditor('🎧 강의듣기', lectureMin,
                (v) => setDlg(() => lectureMin = v.clamp(0, 600))),
              _minuteEditor('☕ 휴식', restMin,
                (v) => setDlg(() => restMin = v.clamp(0, 120)),
                maxVal: 120),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: BotanicalColors.primarySurface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('순공시간: ', style: BotanicalTypo.label(size: 12, color: _textSub)),
                  Text('${effMin}분', style: BotanicalTypo.label(
                    size: 14, weight: FontWeight.w800, color: BotanicalColors.primary)),
                ]),
              ),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.pop(dCtx, {
                'subject': newSubject,
                'studyMin': studyMin,
                'lectureMin': lectureMin,
                'restMin': restMin,
              }), child: const Text('저장')),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final newEffMin = (result['studyMin'] as int) +
          ((result['lectureMin'] as int) * 0.5).round();
      final updated = FocusCycle(
        id: cycle.id, date: cycle.date,
        startTime: cycle.startTime, endTime: cycle.endTime,
        subject: result['subject'] as String,
        segments: cycle.segments,
        studyMin: result['studyMin'] as int,
        lectureMin: result['lectureMin'] as int,
        effectiveMin: newEffMin,
        restMin: result['restMin'] as int,
      );
      await _fb.saveFocusCycle(cycle.date, updated);

      // studyTimeRecords도 동기화 (차이분 반영)
      final diffEff = newEffMin - cycle.effectiveMin;
      final diffTotal = (result['studyMin'] as int) + (result['lectureMin'] as int) +
          (result['restMin'] as int) - cycle.studyMin - cycle.lectureMin - cycle.restMin;
      if (diffEff != 0 || diffTotal != 0) {
        try {
          final strs = await _fb.getStudyTimeRecords();
          final existing = strs[cycle.date];
          final newEff = (existing?.effectiveMinutes ?? 0) + diffEff;
          final newTotal = (existing?.totalMinutes ?? 0) + diffTotal;
          await _fb.updateStudyTimeRecord(cycle.date, StudyTimeRecord(
            date: cycle.date,
            effectiveMinutes: newEff.clamp(0, 1440),
            totalMinutes: newTotal.clamp(0, 1440),
          ));
        } catch (_) {}
      }
      _loadCycles();
    }
  }

  /// F1: 개선된 분 조절 위젯 (컴팩트: ±5/±15 + 직접 입력)
  Widget _minuteEditor(String label, int value, ValueChanged<int> onChanged,
      {int maxVal = 600}) {
    final h = value ~/ 60;
    final m = value % 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
        child: Row(children: [
          // 라벨
          Expanded(
            flex: 3,
            child: Text(label,
              style: BotanicalTypo.label(size: 12, weight: FontWeight.w700, color: _textSub),
              overflow: TextOverflow.ellipsis)),
          // -15분
          _circAdjBtn('-15', value >= 15
            ? () => onChanged((value - 15).clamp(0, maxVal)) : null),
          const SizedBox(width: 3),
          // -5분
          _circAdjBtn('-5', value >= 5
            ? () => onChanged((value - 5).clamp(0, maxVal)) : null),
          const SizedBox(width: 6),
          // 시간 표시 (탭→직접입력)
          GestureDetector(
            onTap: () => _showMinuteInputDialog(label, value, maxVal, onChanged),
            child: Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BotanicalColors.primary.withOpacity(0.2), width: 1.5)),
              child: Text(
                h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}분',
                textAlign: TextAlign.center,
                style: BotanicalTypo.number(
                  size: 14, weight: FontWeight.w800,
                  color: value > 0 ? BotanicalColors.primary : _textMuted)),
            ),
          ),
          const SizedBox(width: 6),
          // +5분
          _circAdjBtn('+5', () => onChanged((value + 5).clamp(0, maxVal))),
          const SizedBox(width: 3),
          // +15분
          _circAdjBtn('+15', () => onChanged((value + 15).clamp(0, maxVal))),
        ]),
      ),
    );
  }

  Widget _circAdjBtn(String label, VoidCallback? onTap) {
    final isAdd = label.startsWith('+');
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: !enabled
            ? (_dk ? Colors.white.withOpacity(0.02) : Colors.grey.shade100)
            : (isAdd
              ? BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.08)
              : (_dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade200)),
          shape: BoxShape.circle),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
            color: !enabled ? (_dk ? Colors.white24 : Colors.grey.shade400)
              : (isAdd ? BotanicalColors.primary : _textSub)))),
      ),
    );
  }

  /// 직접 분 입력 다이얼로그
  Future<void> _showMinuteInputDialog(String label, int current, int maxVal,
      ValueChanged<int> onChanged) async {
    final hourCtrl = TextEditingController(text: '${current ~/ 60}');
    final minCtrl = TextEditingController(text: '${current % 60}');
    final result = await showDialog<int>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(label, style: BotanicalTypo.heading(size: 16)),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 60, child: TextField(
            controller: hourCtrl, keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: BotanicalTypo.number(size: 28, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0', suffixText: 'h',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(':', style: BotanicalTypo.number(size: 28, weight: FontWeight.w300))),
          SizedBox(width: 60, child: TextField(
            controller: minCtrl, keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: BotanicalTypo.number(size: 28, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0', suffixText: 'm',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
          TextButton(onPressed: () {
            final h = int.tryParse(hourCtrl.text) ?? 0;
            final m = int.tryParse(minCtrl.text) ?? 0;
            Navigator.pop(dCtx, (h * 60 + m).clamp(0, maxVal));
          }, child: const Text('확인')),
        ],
      ),
    );
    if (result != null) onChanged(result);
  }

  /// F1: 수동 세션 추가
  Future<void> _addManualSession() async {
    final subjects = SubjectConfig.subjects;
    String subject = subjects.keys.first;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 30);
    int studyMin = 90;
    int lectureMin = 0;
    int restMin = 0;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (_, setDlg) {
        int effMin = studyMin + (lectureMin * 0.5).round();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('수동 세션 추가'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 과목 선택
            Wrap(spacing: 8, runSpacing: 8,
              children: subjects.entries.map((e) {
                final sel = subject == e.key;
                return GestureDetector(
                  onTap: () => setDlg(() => subject = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? Color(e.value.colorValue).withOpacity(0.15) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: sel ? Border.all(color: Color(e.value.colorValue)) : null),
                    child: Text('${e.value.emoji} ${e.key}', style: TextStyle(
                      fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                  ),
                );
              }).toList()),
            const SizedBox(height: 16),
            // 시간 범위
            Row(children: [
              Text('시작', style: BotanicalTypo.label(size: 12, color: _textSub)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: dCtx, initialTime: startTime);
                  if (t != null) setDlg(() => startTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}',
                    style: BotanicalTypo.label(size: 14, weight: FontWeight.w800, color: _textMain)),
                ),
              ),
              const SizedBox(width: 12),
              Text('종료', style: BotanicalTypo.label(size: 12, color: _textSub)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: dCtx, initialTime: endTime);
                  if (t != null) setDlg(() => endTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}',
                    style: BotanicalTypo.label(size: 14, weight: FontWeight.w800, color: _textMain)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _minuteEditor('📖 집중공부', studyMin,
              (v) => setDlg(() => studyMin = v.clamp(0, 600))),
            _minuteEditor('🎧 강의듣기', lectureMin,
              (v) => setDlg(() => lectureMin = v.clamp(0, 600))),
            _minuteEditor('☕ 휴식', restMin,
              (v) => setDlg(() => restMin = v.clamp(0, 120)),
              maxVal: 120),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: BotanicalColors.primarySurface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10)),
              child: Text('순공시간: ${effMin}분',
                style: BotanicalTypo.label(size: 14, weight: FontWeight.w800,
                  color: BotanicalColors.primary)),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(dCtx, {
              'subject': subject,
              'startTime': startTime,
              'endTime': endTime,
              'studyMin': studyMin,
              'lectureMin': lectureMin,
              'restMin': restMin,
            }), child: const Text('추가')),
          ],
        );
      }),
    );

    if (result == null) return;
    final st = result['startTime'] as TimeOfDay;
    final et = result['endTime'] as TimeOfDay;
    final now = DateTime.now();
    final startDt = DateTime(now.year, now.month, now.day, st.hour, st.minute);
    final endDt = DateTime(now.year, now.month, now.day, et.hour, et.minute);
    final newEffMin = (result['studyMin'] as int) +
        ((result['lectureMin'] as int) * 0.5).round();

    final cycle = FocusCycle(
      id: 'fc_manual_${now.millisecondsSinceEpoch}',
      date: _selectedDate,
      startTime: startDt.toIso8601String(),
      endTime: endDt.toIso8601String(),
      subject: result['subject'] as String,
      segments: [],
      studyMin: result['studyMin'] as int,
      lectureMin: result['lectureMin'] as int,
      effectiveMin: newEffMin,
      restMin: result['restMin'] as int,
    );

    await _fb.saveFocusCycle(_selectedDate, cycle);

    // studyTimeRecords 업데이트
    try {
      final strs = await _fb.getStudyTimeRecords();
      final existing = strs[_selectedDate];
      final totalMin = cycle.studyMin + cycle.lectureMin + cycle.restMin;
      await _fb.updateStudyTimeRecord(_selectedDate, StudyTimeRecord(
        date: _selectedDate,
        effectiveMinutes: (existing?.effectiveMinutes ?? 0) + newEffMin,
        totalMinutes: (existing?.totalMinutes ?? 0) + totalMin,
      ));
    } catch (_) {}

    _loadCycles();
  }

  Future<void> _deleteCycle(FocusCycle cycle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('세션 삭제'),
        content: Text('이 포커스 세션을 삭제하시겠습니까?\n순공 ${cycle.effectiveMin}분이 기록에서 제거됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await FocusTimerService().deleteFocusCycle(cycle.date, cycle.id);
      // studyTimeRecords도 동기화 (삭제분 차감)
      try {
        final strs = await _fb.getStudyTimeRecords();
        final existing = strs[cycle.date];
        if (existing != null) {
          final newEff = (existing.effectiveMinutes - cycle.effectiveMin).clamp(0, 1440);
          final newTotal = (existing.totalMinutes - cycle.studyMin - cycle.lectureMin - cycle.restMin).clamp(0, 1440);
          await _fb.updateStudyTimeRecord(cycle.date, StudyTimeRecord(
            date: cycle.date,
            effectiveMinutes: newEff,
            totalMinutes: newTotal,
          ));
        }
      } catch (_) {}
      _loadCycles();
    }
  }
}