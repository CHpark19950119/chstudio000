import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/focus_service.dart';
import '../../services/cradle_service.dart';
import 'focus_result_sheet.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with TickerProviderStateMixin {
  final _fs = FocusService();
  final _cradle = CradleService();
  StreamSubscription? _cradleSub;
  bool _cradleAutoStarted = false;

  late AnimationController _pulseCtrl;
  late AnimationController _staggerCtrl;
  late AnimationController _heroCountCtrl;

  String _subj = '자료해석';
  String _mode = 'study';

  List<FocusCycle> _todaySessions = [];
  Map<String, int> _weeklyData = {};
  bool _recordsLoading = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;

  // theme-aware colors — no hardcoding
  Color get _bg => _dk ? const Color(0xFF111015) : const Color(0xFFF6F4F0);
  Color get _card => _dk ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.65);
  Color get _cardBorder => _dk ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.04);
  Color get _t1 => _dk ? const Color(0xFFF2ECE4) : const Color(0xFF1A1714);
  Color get _t2 => _dk ? const Color(0xFFB8A898) : const Color(0xFF5C5048);
  Color get _t3 => _dk ? const Color(0xFF7A6E62) : const Color(0xFF9A8E82);
  Color get _accent => BotanicalColors.subjectColor(_subj);

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
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _heroCountCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
    if (_fs.isRunning) {
      final st = _fs.getCurrentState();
      _subj = st.subject;
      _mode = st.mode;
      _enterImmersive();
    }
    SubjectConfig.load();

    _fs.onCradleChanged(_cradle.isOnCradle);
    if (!_cradle.isEnabled && _cradle.isCalibrated) {
      _cradle.start();
      _cradleAutoStarted = true;
    }
    _cradleSub = _cradle.cradleStream.listen((on) {
      if (on) HapticFeedback.mediumImpact();
      if (!on && _fs.isRunning) HapticFeedback.heavyImpact();
      _fs.onCradleChanged(on);
    });

    _todaySessions = _fs.todaySessions;
    _loadRecords();
  }

  @override
  void dispose() {
    _cradleSub?.cancel();
    if (_cradleAutoStarted && !_cradle.isEnabled) _cradle.stop();
    _pulseCtrl.dispose();
    _staggerCtrl.dispose();
    _heroCountCtrl.dispose();
    _exitImmersive();
    super.dispose();
  }

  void _enterImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  static const _focusCh = MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');

  void _minimizeToHome() {
    _exitImmersive();
    _focusCh.invokeMethod('moveTaskToBack')
        .catchError((_) => SystemNavigator.pop(animated: true));
  }

  void _lockScreen() {
    _exitImmersive();
    _focusCh.invokeMethod('lockScreen').then((ok) {
      if (ok != true) {
        // Device admin not enabled — show hint
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기기 관리자 권한을 허용하세요'), duration: Duration(seconds: 3)));
        }
      }
    }).catchError((_) {
      // Fallback: just minimize
      _focusCh.invokeMethod('moveTaskToBack').catchError((_) {});
    });
  }

  Future<void> _loadRecords() async {
    _safeSetState(() => _recordsLoading = true);
    try {
      final w = await _fs.getWeeklyStudyMinutes();
      await _fs.refreshTodaySessions();
      _safeSetState(() {
        _weeklyData = w;
        _todaySessions = _fs.todaySessions;
        _recordsLoading = false;
      });
    } catch (_) {
      _safeSetState(() => _recordsLoading = false);
    }
  }

  // ── glass card ──
  Widget _frost({
    required Widget child,
    double blur = 16,
    double radius = 24,
    EdgeInsets padding = const EdgeInsets.all(20),
    Color? borderColor,
    Color? fillColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor ?? _card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? _cardBorder),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── stagger helpers ──
  Widget _stagger(int i, Widget child) {
    final begin = (i * 0.10).clamp(0.0, 0.6);
    final end = (begin + 0.5).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final v = anim.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _fs,
      builder: (context, _) {
        if (_fs.isRunning) return _immersiveView();
        // Session ended — pop back to home
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        });
        return Scaffold(backgroundColor: _bg, body: const SizedBox.shrink());
      },
    );
  }

  Widget _setupView() {
    if (!_staggerCtrl.isAnimating && _staggerCtrl.isCompleted) {
      _staggerCtrl.reset();
      _staggerCtrl.forward();
      _heroCountCtrl.reset();
      _heroCountCtrl.forward();
    }
    final goalMin = 480;
    final pct = (_fs.todayStudyMinutes / goalMin).clamp(0.0, 1.0);
    final totalEff = _todaySessions.fold<int>(0, (s, c) => s + c.effectiveMin);

    return RefreshIndicator(
      onRefresh: _loadRecords,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          // ── Header row ──
          _stagger(0, Row(children: [
            Text('포커스', style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: _t1)),
            const Spacer(),
            GestureDetector(
              onTap: _manageSubjects,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _t3.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.tune_rounded, size: 18, color: _t3),
              ),
            ),
          ])),
          const SizedBox(height: 20),

          // ── Hero: floating gradient time ──
          _stagger(0, Center(child: AnimatedBuilder(
            animation: _heroCountCtrl,
            builder: (_, __) {
              final curve = Curves.easeOutCubic.transform(_heroCountCtrl.value);
              final mins = (_fs.todayStudyMinutes * curve).round();
              final h = mins ~/ 60;
              final m = mins % 60;
              return ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [_accent, _accent.withOpacity(0.4), _dk ? Colors.white54 : Colors.black38],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ).createShader(r),
                child: Text(
                  h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m',
                  style: const TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: -3, height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()]),
                ),
              );
            },
          ))),
          const SizedBox(height: 10),
          _stagger(0, Center(child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(_dk ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(10)),
                child: Text('${_fs.todaySessionCount}세션', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: _accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 8),
              Text('순공시간', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: _t3)),
            ],
          ))),
          const SizedBox(height: 16),
          _stagger(0, AnimatedBuilder(
            animation: _heroCountCtrl,
            builder: (_, __) {
              final v = Curves.easeOutCubic.transform(_heroCountCtrl.value);
              return Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(height: 3, child: LinearProgressIndicator(
                    value: pct * v,
                    backgroundColor: _dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                    valueColor: AlwaysStoppedAnimation(_accent.withOpacity(0.60)),
                  )),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${(pct * 100).toInt()}% of 8h', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600, color: _t3.withOpacity(0.45),
                    fontFeatures: const [FontFeature.tabularFigures()]))),
              ]);
            },
          )),
          const SizedBox(height: 28),

          // ── Subject chips ──
          _stagger(1, _secLabel('SUBJECT')),
          const SizedBox(height: 10),
          _stagger(1, SizedBox(height: 38, child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: SubjectConfig.subjects.entries.map((e) {
              final sel = _subj == e.key;
              final c = BotanicalColors.subjectColor(e.key);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _subj = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? c.withOpacity(_dk ? 0.18 : 0.10) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? c.withOpacity(0.45) : _t3.withOpacity(0.12),
                        width: sel ? 1.5 : 1),
                      boxShadow: sel ? [BoxShadow(color: c.withOpacity(0.10), blurRadius: 10)] : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(e.key, style: TextStyle(
                        fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? c : _t2)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ))),
          const SizedBox(height: 24),

          // ── Mode ──
          _stagger(2, _secLabel('MODE')),
          const SizedBox(height: 10),
          _stagger(2, Row(children: [
            Expanded(child: _modeChip('📖', '집중', '순공 100%', 'study')),
            const SizedBox(width: 10),
            Expanded(child: _modeChip('🎧', '강의', '순공 50%', 'lecture')),
          ])),
          const SizedBox(height: 20),

          // ── Cradle settings card ──
          _stagger(3, _cradleCard()),
          const SizedBox(height: 28),

          // ── Start button ──
          _stagger(4, _startButton()),
          const SizedBox(height: 36),

          // ── Records divider ──
          Row(children: [
            Expanded(child: Container(height: 1,
              color: _dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04))),
          ]),
          const SizedBox(height: 24),

          // ── Weekly chart ──
          _frost(
            blur: 14,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _secLabel('WEEKLY'),
              const SizedBox(height: 14),
              SizedBox(height: 100, child: _weeklyChart()),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Today summary ──
          _frost(
            blur: 12,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderColor: _accent.withOpacity(0.08),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [_accent, _accent.withOpacity(0.45)],
                ).createShader(r),
                child: Text(_fmtMin(totalEff), style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white,
                  letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 8),
              Text('순공', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: _accent.withOpacity(0.5))),
              const Spacer(),
              _miniStat('📖', _todaySessions.fold<int>(0, (s, c) => s + c.studyMin)),
              const SizedBox(width: 6),
              _miniStat('🎧', _todaySessions.fold<int>(0, (s, c) => s + c.lectureMin)),
              const SizedBox(width: 6),
              _miniStat('☕', _todaySessions.fold<int>(0, (s, c) => s + c.restMin)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Sessions header ──
          Row(children: [
            _secLabel('TODAY'),
            const Spacer(),
            Text('${_todaySessions.length}세션', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: _t3,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 10),

          if (_recordsLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_todaySessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.hourglass_empty_rounded, size: 36, color: _t3.withOpacity(0.18)),
                const SizedBox(height: 10),
                Text('아직 기록이 없어요', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: _t3.withOpacity(0.4))),
              ])),
            )
          else
            ..._todaySessions.reversed.toList().asMap().entries.map(
                (e) => _sessionTile(e.value, _todaySessions.length - e.key)),
        ],
      ),
    );
  }

  Widget _secLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(t, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w800,
      color: _t3.withOpacity(0.55), letterSpacing: 2.5)),
  );

  Widget _modeChip(String emoji, String label, String desc, String m) {
    final sel = _mode == m;
    final c = m == 'study' ? const Color(0xFF6366F1) : BotanicalColors.subjectData;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: _frost(
        blur: sel ? 14 : 8,
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        borderColor: sel ? c.withOpacity(0.35) : _cardBorder,
        fillColor: sel ? c.withOpacity(_dk ? 0.10 : 0.05) : _card,
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: sel ? c : _t1)),
            Text(desc, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w500, color: _t3)),
          ]),
          const Spacer(),
          if (sel) Container(width: 7, height: 7, decoration: BoxDecoration(
            shape: BoxShape.circle, color: c,
            boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 6)])),
        ]),
      ),
    );
  }

  Widget _cradleCard() {
    final cal = _cradle.isCalibrated;
    final en = _cradle.isEnabled;
    final on = _cradle.isOnCradle;

    if (!cal) {
      // Not calibrated
      return _frost(
        blur: 12, radius: 16,
        padding: const EdgeInsets.all(16),
        borderColor: Colors.orange.withOpacity(0.15),
        fillColor: Colors.orange.withOpacity(_dk ? 0.04 : 0.02),
        child: Row(children: [
          const Text('📐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('거치대를 설정하세요', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _t1)),
            const SizedBox(height: 2),
            Text('거치대 각도를 등록하면 자동 감지됩니다', style: TextStyle(
              fontSize: 10, color: _t3)),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showCradleCalibration,
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

    // Calibrated
    final statusColor = on ? const Color(0xFF10B981) : (en ? _t3.withOpacity(0.6) : _t3.withOpacity(0.4));
    final statusMsg = on ? '거치 감지됨' : (en ? '대기 중' : '감지 OFF');

    return _frost(
      blur: 12, radius: 16,
      padding: const EdgeInsets.all(16),
      borderColor: statusColor.withOpacity(0.12),
      fillColor: statusColor.withOpacity(_dk ? 0.03 : 0.02),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(on ? '✅' : '📐', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('거치대 등록됨', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _t1)),
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
                fontSize: 10, color: _t3, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ])),
          GestureDetector(
            onTap: _showCradleCalibration,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _t3.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8)),
              child: Text('재등록', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _t3)),
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

  Widget _startButton() {
    return GestureDetector(
      onTap: _start,
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
                  _accent.withOpacity(_dk ? 0.18 : 0.12),
                  _accent.withOpacity(_dk ? 0.08 : 0.04),
                ],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _accent.withOpacity(0.25)),
              boxShadow: [
                BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withOpacity(0.22),
                  boxShadow: [BoxShadow(color: _accent.withOpacity(0.15), blurRadius: 12)]),
                child: Icon(Icons.play_arrow_rounded, size: 22, color: _accent),
              ),
              const SizedBox(width: 10),
              Text('시작', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: _accent, letterSpacing: 0.5)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String emoji, int min) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(7)),
      child: Text('$emoji ${min}m', style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700, color: _t2,
        fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  Widget _weeklyChart() {
    if (_weeklyData.isEmpty) {
      return Center(child: Text('데이터 로딩...', style: TextStyle(fontSize: 11, color: _t3.withOpacity(0.4))));
    }
    final entries = _weeklyData.entries.toList();
    final maxVal = entries.map((e) => e.value).reduce(max).clamp(1, 9999);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: entries.map((e) {
        final isToday = e.key == today;
        final ratio = e.value / maxVal;
        final dt = DateTime.parse(e.key);
        final wd = ['월','화','수','목','금','토','일'][dt.weekday - 1];
        final bc = isToday ? _accent : _accent.withOpacity(_dk ? 0.20 : 0.14);

        return Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (e.value > 0)
              Text(_fmtMin(e.value), style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w700,
                color: isToday ? _accent : _t3.withOpacity(0.6),
                fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              height: (ratio * 56).clamp(3.0, 56.0),
              decoration: BoxDecoration(
                color: bc,
                borderRadius: BorderRadius.circular(4),
                boxShadow: isToday ? [
                  BoxShadow(color: _accent.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 2)),
                ] : null,
              ),
            ),
            const SizedBox(height: 5),
            Text(wd, style: TextStyle(
              fontSize: 9, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              color: isToday ? _accent : _t3.withOpacity(0.6))),
          ]),
        ));
      }).toList(),
    );
  }

  Widget _sessionTile(FocusCycle c, int idx) {
    final sc = BotanicalColors.subjectColor(c.subject);
    return GestureDetector(
      onLongPress: () => _confirmDeleteSession(c),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(child: Row(children: [
          Container(width: 3, decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [sc, sc.withOpacity(0.2)]),
            borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: _frost(
            blur: 10, radius: 14,
            padding: const EdgeInsets.all(12),
            borderColor: sc.withOpacity(0.06),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sc.withOpacity(_dk ? 0.12 : 0.06),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('${SubjectConfig.subjects[c.subject]?.emoji ?? '📚'} ${c.subject}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sc)),
                  ),
                  const Spacer(),
                  Text('#$idx', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                    color: _t3.withOpacity(0.3), fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 5),
                Text('${_fmtTime(c.startTime)} → ${c.endTime != null ? _fmtTime(c.endTime) : '...'}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _t2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 3),
                Text('공부 ${c.studyMin}m · 강의 ${c.lectureMin}m · 휴식 ${c.restMin}m',
                  style: TextStyle(fontSize: 9, color: _t3)),
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
                            color: segC.withOpacity(_dk ? 0.45 : 0.30)));
                      }).toList()))),
                ],
              ])),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmtMin(c.effectiveMin), style: TextStyle(
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

  void _confirmDeleteSession(FocusCycle c) {
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: _dk ? const Color(0xFF18181E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('삭제할까요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _t1)),
      content: Text(
        '${c.subject} · ${_fmtTime(c.startTime)}~${c.endTime != null ? _fmtTime(c.endTime) : '...'} · 순공 ${c.effectiveMin}분',
        style: TextStyle(fontSize: 12, color: _t2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: Text('취소', style: TextStyle(color: _t3))),
        TextButton(onPressed: () async {
          Navigator.pop(dCtx);
          await _fs.deleteFocusCycle(c.date, c.id);
          _safeSetState(() {
            _todaySessions = _fs.todaySessions;
          });
        }, child: const Text('삭제', style: TextStyle(
          color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ],
    ));
  }


  // ══════════════════════════════════════════
  //  Immersive Focus View
  // ══════════════════════════════════════════

  Widget _immersiveView() {
    final st = _fs.getCurrentState();
    final sc = BotanicalColors.subjectColor(st.subject);
    final isRest = st.mode == 'rest';
    final dc = isRest ? Colors.orange : sc;
    final mE = st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕';
    final mL = st.mode == 'study' ? '집중공부' : st.mode == 'lecture' ? '강의듣기' : '휴식';

    return PopScope(
      canPop: isRest,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmEnd(); },
      child: Scaffold(
        backgroundColor: const Color(0xFF08080C),
        body: Stack(children: [
          // ambient glow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.22,
            left: MediaQuery.of(context).size.width * 0.5 - 120,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 240, height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    dc.withOpacity(0.05 + _pulseCtrl.value * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          SafeArea(child: Column(children: [
            // ── top bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.07))),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => _showSubjectPicker(st.subject),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sc.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: sc.withOpacity(0.25))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(SubjectConfig.subjects[st.subject]?.emoji ?? '📚',
                              style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 5),
                            Text(st.subject, style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: sc)),
                            Icon(Icons.unfold_more_rounded, size: 13, color: sc.withOpacity(0.5)),
                          ]),
                        ),
                      ),
                      const Spacer(),
                      _cradleDot(),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10)),
                        child: Text('순공 ${st.effectiveTimeFormatted}', style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981),
                          fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            // ── stats strip ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _imStat('📖', '${st.totalStudyMin}m'),
                      _imDiv(),
                      _imStat('🎧', '${st.totalLectureMin}m'),
                      _imDiv(),
                      _imStat('☕', '${st.totalRestMin}m'),
                      _imDiv(),
                      _imStat('⏱️', st.sessionTimeFormatted),
                    ]),
                  ),
                ),
              ),
            ),

            // ── center ring ──
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final op = isRest ? 0.4 + _pulseCtrl.value * 0.6 : 0.7 + _pulseCtrl.value * 0.3;
                  return Text('$mE $mL', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: dc.withOpacity(op), letterSpacing: 2));
                },
              ),
              const SizedBox(height: 18),
              SizedBox(width: 240, height: 240, child: Stack(alignment: Alignment.center, children: [
                if (!isRest) AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(width: 240, height: 240,
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: sc.withOpacity(0.07 + _pulseCtrl.value * 0.05),
                        blurRadius: 44, spreadRadius: 12),
                    ])),
                ),
                CustomPaint(size: const Size(240, 240),
                  painter: _RingPainter(progress: st.cycleProgress, color: dc)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(st.mainTimerFormatted, style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w200, color: Colors.white,
                    letterSpacing: -1, fontFamily: 'monospace',
                    fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Text('seg ${st.segmentTimeFormatted}', style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.25),
                    fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ])),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: dc.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                  child: Text('사이클 ${st.cycleCount + 1}', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: dc.withOpacity(0.7))),
                ),
                const SizedBox(width: 10),
                Text('${(st.cycleProgress * 90).round()}/90분', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3),
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ]))),

            // ── sub timer ──
            if (!isRest) _subTimerBar(sc),
            const SizedBox(height: 10),

            // ── cycle bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: st.cycleProgress.clamp(0.0, 1.0), minHeight: 3,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation(dc.withOpacity(0.55)))),
            ),
            const SizedBox(height: 10),

            // ── bottom controls ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _imModeBtn('📖', '공부', 'study', sc, st.mode),
                const SizedBox(width: 6),
                _imModeBtn('🎧', '강의', 'lecture', const Color(0xFF3B7A57), st.mode),
                const SizedBox(width: 6),
                _imModeBtn('☕', '휴식', 'rest', Colors.orange, st.mode),
                const SizedBox(width: 6),
                _imBathroomBtn(),
                const SizedBox(width: 6),
                _imActionBtn(Icons.lock_rounded, const Color(0xFF8B5CF6), _lockScreen),
                const SizedBox(width: 6),
                _imActionBtn(Icons.home_rounded, Colors.blueAccent, _minimizeToHome),
                const SizedBox(width: 6),
                _imActionBtn(Icons.stop_rounded, Colors.redAccent, _confirmEnd, size: 24),
              ]),
            ),
            const SizedBox(height: 22),
          ])),

          if (_fs.cradlePaused) _cradleOverlay(),
        ]),
      ),
    );
  }

  Widget _imStat(String e, String v) => Text('$e $v', style: TextStyle(
    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.6),
    fontFeatures: const [FontFeature.tabularFigures()]));
  Widget _imDiv() => Container(width: 1, height: 20, color: Colors.white.withOpacity(0.05));

  Widget _cradleDot() {
    final on = _fs.isOnCradle;
    final c = on ? const Color(0xFF10B981) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          shape: BoxShape.circle, color: c,
          boxShadow: on ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 5)] : null)),
        const SizedBox(width: 4),
        Text(on ? '거치' : '미감지', style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }

  Widget _imModeBtn(String emoji, String label, String m, Color c, String cur) {
    final sel = cur == m;
    return Expanded(child: GestureDetector(
      onTap: sel ? null : () => _fs.switchMode(m),
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(duration: const Duration(milliseconds: 180), height: 48,
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(0.18) : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: sel ? Border.all(color: c.withOpacity(0.45), width: 1.5)
                  : Border.all(color: Colors.white.withOpacity(0.05))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              Text(label, style: TextStyle(fontSize: 9, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? c : Colors.white.withOpacity(0.35))),
            ]))))));
  }

  Widget _imBathroomBtn() {
    final on = _fs.isBathroomBreak;
    final sec = _fs.bathroomSec;
    return GestureDetector(
      onTap: on ? null : _showBathroomDialog,
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(duration: const Duration(milliseconds: 180),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: on ? Colors.teal.withOpacity(0.22) : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: on ? Border.all(color: Colors.teal.withOpacity(0.45), width: 1.5)
                  : Border.all(color: Colors.white.withOpacity(0.05))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(on ? '⏳' : '🚻', style: const TextStyle(fontSize: 14)),
              if (on)
                Text('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.tealAccent,
                    fontFeatures: [FontFeature.tabularFigures()]))
              else
                Text('화장실', style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.35))),
            ])))));
  }

  Widget _imActionBtn(IconData icon, Color c, VoidCallback onTap, {double size = 22}) {
    return GestureDetector(onTap: onTap,
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(0.22))),
            child: Icon(icon, color: c, size: size)))));
  }

  Widget _subTimerBar(Color sc) {
    final elapsed = _fs.problemElapsedSec;
    final mm = elapsed ~/ 60;
    final ss = elapsed % 60;
    final str = '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    final laps = _fs.problemLaps;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            decoration: BoxDecoration(
              color: sc.withOpacity(0.05), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sc.withOpacity(0.10))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('⏱️', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text('문제', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                const Spacer(),
                if (laps.isNotEmpty)
                  Text('${laps.length}문제', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: sc.withOpacity(0.7))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text(_fs.subTimerActive ? str : '--:--', style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w300,
                  color: _fs.subTimerActive ? sc : Colors.white.withOpacity(0.15),
                  fontFamily: 'monospace', letterSpacing: 2,
                  fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (!_fs.subTimerActive) { _fs.toggleSubTimer(); }
                    else if (_fs.problemStart != null) {
                      _fs.toggleSubTimer(); _fs.toggleSubTimer();
                    }
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sc.withOpacity(_fs.subTimerActive ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sc.withOpacity(0.25))),
                    child: Text(_fs.subTimerActive ? '다음' : '시작', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: sc)),
                  ),
                ),
                if (_fs.subTimerActive) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () { _fs.toggleSubTimer(); HapticFeedback.lightImpact(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                      child: const Text('정지', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent))),
                  ),
                ],
              ]),
              if (laps.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: laps.reversed.take(5).toList().asMap().entries.map((e) {
                  final lap = e.value;
                  final i = laps.length - e.key;
                  return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('#$i', style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.25))),
                    Text('${lap.seconds ~/ 60}:${(lap.seconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.5), fontFamily: 'monospace',
                        fontFeatures: const [FontFeature.tabularFigures()])),
                  ]));
                }).toList()),
              ],
            ]),
          ))),
    );
  }

  Widget _cradleOverlay() {
    final sec = _fs.cradleRestSec;
    final mm = sec ~/ 60; final ss = sec % 60;
    final rate = _fs.concentrationRate;
    return Positioned.fill(child: Container(
      color: Colors.black.withOpacity(0.75),
      child: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('☕', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 14),
        const Text('휴식 중', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('거치대에 올려놓으면 재개', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
        const SizedBox(height: 18),
        Text('${mm.toString().padLeft(2,'0')}:${ss.toString().padLeft(2,'0')}',
          style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 34,
            fontWeight: FontWeight.w300, fontFamily: 'monospace',
            fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 20),
        if (_fs.cradleFocusSec + _fs.cradleRestSec > 30)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('집중도 ', style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text('$rate%', style: TextStyle(
                color: _concColor(rate), fontSize: 15, fontWeight: FontWeight.w800)),
              Text(' · ${_fs.cradleRestCount}회', style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ]),
          ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: () { _fs.onCradleChanged(true); HapticFeedback.mediumImpact(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35))),
            child: const Text('수동 재개', style: TextStyle(
              color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      ])))));
  }

  Color _concColor(int r) {
    if (r >= 90) return const Color(0xFF10B981);
    if (r >= 70) return const Color(0xFFFBBF24);
    if (r >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  // ══════════════════════════════════════════
  //  Actions
  // ══════════════════════════════════════════

  Future<void> _start() async {
    await _fs.startSession(subject: _subj, mode: _mode);
    _enterImmersive();
  }

  void _confirmEnd() {
    final st = _fs.getCurrentState();
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: const Color(0xFF18181E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('세션 종료', style: TextStyle(color: Colors.white, fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _eRow('순공', st.effectiveTimeFormatted),
        _eRow('공부', '${st.totalStudyMin}분'),
        _eRow('강의', '${st.totalLectureMin}분'),
        _eRow('휴식', '${st.totalRestMin}분'),
        _eRow('세션', st.sessionTimeFormatted),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: const Text('계속', style: TextStyle(color: Colors.white54))),
        TextButton(onPressed: () async {
          Navigator.pop(dCtx);
          final cycle = await _fs.endSession();
          _exitImmersive();
          _loadRecords();
          if (mounted) showFocusResultDialog(
            context: context, cycle: cycle, dk: _dk,
            textMain: _t1, textSub: _t2, textMuted: _t3,
            cradleFocusSec: _fs.cradleFocusSec,
            cradleRestSec: _fs.cradleRestSec,
            cradleRestCount: _fs.cradleRestCount,
            magnetEnabled: _cradle.isEnabled);
        }, child: const Text('종료', style: TextStyle(
          color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  Widget _eRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(fontSize: 12, color: Colors.white38)),
      Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()])),
    ]));

  void _showBathroomDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _dk ? const Color(0xFF1C2028) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Text('🚻', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Text('화장실', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _t1)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _brOption(ctx, '💧', '소변', '2분'),
        const SizedBox(height: 8),
        _brOption(ctx, '🚽', '대변', '5분'),
      ]),
    ));
  }

  Widget _brOption(BuildContext ctx, String emoji, String label, String time) {
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); _fs.startBathroomBreak(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(_dk ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.withOpacity(0.15))),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _t1)),
            Text(time, style: TextStyle(fontSize: 10, color: _t3)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _t3),
        ]),
      ),
    );
  }

  void _showSubjectPicker(String cur) {
    showModalBottomSheet(context: context,
      backgroundColor: const Color(0xFF14141A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8,
            children: SubjectConfig.subjects.entries.map((e) {
              final sel = cur == e.key;
              final c = BotanicalColors.subjectColor(e.key);
              return GestureDetector(
                onTap: () { if (!sel) _fs.changeSubject(e.key); if (context.mounted) Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? c.withOpacity(0.18) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: sel ? Border.all(color: c.withOpacity(0.45), width: 1.5) : null),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(e.value.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(e.key, style: TextStyle(fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? c : Colors.white.withOpacity(0.65))),
                  ]),
                ),
              );
            }).toList()),
          const SizedBox(height: 14),
        ]),
      )));
  }

  void _showCradleCalibration() {
    bool calibrating = false;
    bool done = false;
    String calType = 'normal'; // 'normal' or 'charging'
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setBS) {
        return SafeArea(child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: _t3.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('거치대 각도 캘리브레이션', style: BotanicalTypo.heading(size: 17, color: _t1)),
            const SizedBox(height: 6),
            Text('거치대에 올려놓고 시작 — 이 각도에서만 활성화됩니다', style: TextStyle(fontSize: 12, color: _t3)),
            const SizedBox(height: 16),
            // ── 모드 선택: 일반 / 충전 ──
            if (!calibrating && !done) ...[
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setBS(() => calType = 'normal'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: calType == 'normal' ? BotanicalColors.primary.withOpacity(0.12) : _t3.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: calType == 'normal' ? BotanicalColors.primary.withOpacity(0.35) : Colors.transparent)),
                    child: Column(children: [
                      Text('📐', style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text('일반', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: calType == 'normal' ? BotanicalColors.primary : _t3)),
                      Text(_cradle.isCalibrated ? '등록됨' : '미등록', style: TextStyle(fontSize: 9,
                        color: _cradle.isCalibrated ? const Color(0xFF10B981) : _t3.withOpacity(0.5))),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => setBS(() => calType = 'charging'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: calType == 'charging' ? Colors.orange.withOpacity(0.12) : _t3.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: calType == 'charging' ? Colors.orange.withOpacity(0.35) : Colors.transparent)),
                    child: Column(children: [
                      const Text('🔌', style: TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text('충전용', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: calType == 'charging' ? Colors.orange : _t3)),
                      Text(_cradle.isChargingCalibrated ? '등록됨' : '미등록', style: TextStyle(fontSize: 9,
                        color: _cradle.isChargingCalibrated ? const Color(0xFF10B981) : _t3.withOpacity(0.5))),
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
              Text('기준 각도가 저장되었습니다', style: TextStyle(fontSize: 12, color: _t3)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _safeSetState(() {}); },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w700)))),
            ] else if (calibrating) ...[
              const SizedBox(height: 8),
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 16),
              Text('측정 중... 폰을 움직이지 마세요', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _t1)),
              const SizedBox(height: 6),
              Text(calType == 'charging' ? '충전 상태 각도를 측정합니다 (5초)' : '5초간 가속도계 데이터를 수집합니다',
                style: TextStyle(fontSize: 11, color: _t3)),
              const SizedBox(height: 24),
            ] else ...[
              Icon(calType == 'charging' ? Icons.battery_charging_full_rounded : Icons.phone_android_rounded,
                size: 48, color: _t3.withOpacity(0.5)),
              const SizedBox(height: 12),
              Text(calType == 'charging'
                ? '충전 케이블을 꽂은 상태로\n거치대에 올려놓고 아래 버튼을 누르세요'
                : '폰을 거치대에 올려놓고\n아래 버튼을 누르세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _t2, height: 1.5)),
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

  void _manageSubjects() {
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setBS) {
        final subjects = SubjectConfig.subjects;
        return SafeArea(child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: _t3.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Row(children: [
              Text('과목 관리', style: BotanicalTypo.heading(size: 15, color: _t1)),
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
                  child: Text('초기화', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: Colors.orange))),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _addSubjectDlg(ctx, setBS),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: BotanicalColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 14, color: BotanicalColors.primary),
                    Text(' 추가', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: BotanicalColors.primary)),
                  ])),
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
                  Text(e.key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _t1)),
                  const Spacer(),
                  GestureDetector(onTap: () => _editSubjectDlg(e.key, e.value, ctx, setBS),
                    child: Padding(padding: const EdgeInsets.all(5),
                      child: Icon(Icons.edit_rounded, size: 16, color: _t3))),
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

  static const _sColors = [
    0xFF6366F1,0xFF10B981,0xFFF59E0B,0xFFEF4444,0xFF3B82F6,
    0xFF8B5CF6,0xFFEC4899,0xFF14B8A6,0xFFF97316,0xFF06B6D4];

  void _editSubjectDlg(String old, SubjectInfo info, BuildContext ctx, StateSetter setBS) {
    final nc = TextEditingController(text: old);
    final ec = TextEditingController(text: info.emoji);
    int sc = info.colorValue;
    showDialog(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('수정', style: TextStyle(fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nc, decoration: const InputDecoration(labelText: '과목명', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: ec, decoration: const InputDecoration(labelText: '이모지', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: _sColors.map((c) => GestureDetector(
          onTap: () => setD(() => sc = c),
          child: Container(width: 28, height: 28, decoration: BoxDecoration(
            color: Color(c), borderRadius: BorderRadius.circular(6),
            border: sc == c ? Border.all(color: Colors.white, width: 2.5) : null)),
        )).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          final n = nc.text.trim(); final e = ec.text.trim();
          if (n.isEmpty) return;
          await SubjectConfig.updateSubject(old, n, e.isEmpty ? '📚' : e, sc);
          if (_subj == old) _subj = n;
          if (dCtx.mounted) Navigator.pop(dCtx);
          setBS(() {}); setState(() {});
        }, child: const Text('저장')),
      ])));
  }

  void _addSubjectDlg(BuildContext ctx, StateSetter setBS) {
    final nc = TextEditingController();
    final ec = TextEditingController(text: '📚');
    int sc = _sColors.first;
    showDialog(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('추가', style: TextStyle(fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nc, decoration: const InputDecoration(labelText: '과목명', hintText: '국어')),
        const SizedBox(height: 10),
        TextField(controller: ec, decoration: const InputDecoration(labelText: '이모지'),
          style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: _sColors.map((c) => GestureDetector(
          onTap: () => setD(() => sc = c),
          child: Container(width: 28, height: 28, decoration: BoxDecoration(
            color: Color(c), borderRadius: BorderRadius.circular(6),
            border: sc == c ? Border.all(color: Colors.white, width: 2.5) : null)),
        )).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          final n = nc.text.trim(); final e = ec.text.trim();
          if (n.isEmpty) return;
          await SubjectConfig.addSubject(n, e.isEmpty ? '📚' : e, sc);
          if (dCtx.mounted) Navigator.pop(dCtx);
          setBS(() {}); setState(() {});
        }, child: const Text('추가')),
      ])));
  }

  // ── helpers ──
  String _fmtMin(int m) {
    final h = m ~/ 60; final r = m % 60;
    if (h > 0 && r > 0) return '${h}h ${r}m';
    if (h > 0) return '${h}h';
    return '${r}m';
  }

  String _fmtTime(String? raw) {
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
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    p.color = color.withOpacity(0.10);
    canvas.drawArc(rect, -pi / 2, 2 * pi, false, p);
    if (progress > 0) {
      p.shader = SweepGradient(
        colors: [color.withOpacity(0.35), color],
        transform: const GradientRotation(-pi / 2),
      ).createShader(rect);
      canvas.drawArc(rect, -pi / 2, 2 * pi * progress.clamp(0.0, 1.0), false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
