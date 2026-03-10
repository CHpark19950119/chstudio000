import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/botanical_theme.dart';
import '../services/library_service.dart';

// ═══════════════════════════════════════════
//  도서관 좌석 배치도 — 단일 열람실 (90° 회전)
//  우측: 메인 7블록 A-G (4열×2행)
//  좌측: H/I/J 블록 (2열×N행)
//  하나의 방, 출입문은 하단 벽
// ═══════════════════════════════════════════

class LibrarySeatMapScreen extends StatefulWidget {
  const LibrarySeatMapScreen({super.key});
  @override
  State<LibrarySeatMapScreen> createState() => _LibrarySeatMapScreenState();
}

class _LibrarySeatMapScreenState extends State<LibrarySeatMapScreen>
    with SingleTickerProviderStateMixin {
  final _lib = LibraryService();
  LibraryRoom? _room;
  bool _loading = true;
  late AnimationController _pulseCtrl;
  Timer? _refreshTimer;
  int? _tappedSeat;
  Offset? _tappedOffset;
  Timer? _bubbleTimer;
  final Map<int, Offset> _seatCenters = {};
  final TransformationController _txCtrl = TransformationController();

  // 항상 라이트 모드 (밤에도 잘 보이게)
  static const _bg = Color(0xFFF5F0E8);
  static const _t1 = Color(0xFF1A1714);
  static const _t2 = Color(0xFF5C5048);
  static const _t3 = Color(0xFF9A8E82);

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else { setState(fn); }
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetch());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _bubbleTimer?.cancel();
    _txCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    _safeSetState(() => _loading = true);
    final r = await _lib.fetch(force: true);
    _safeSetState(() { _room = r; _loading = false; });
  }

  void _onTapDown(TapDownDetails d) {
    if (_seatCenters.isEmpty || _room == null) return;
    for (final e in _seatCenters.entries) {
      if ((e.value - d.localPosition).distance < 18) {
        final st = _room!.seats[e.key];
        if (st == null) continue;
        _bubbleTimer?.cancel();
        _safeSetState(() { _tappedSeat = e.key; _tappedOffset = e.value; });
        _bubbleTimer = Timer(const Duration(seconds: 2), () {
          _safeSetState(() => _tappedSeat = null);
        });
        break;
      }
    }
  }

  static const _cInUse     = Color(0xFFFF9F43);
  static const _cAvailable = Color(0xFF48DBFB);
  static const _cStanding  = Color(0xFFA29BFE);
  static const _cDisabled  = Color(0xFFFECA57);
  static const _cUnavail   = Color(0xFF636E72);

  Color _seatColor(SeatStatus s) {
    switch (s) {
      case SeatStatus.inUse:       return _cInUse;
      case SeatStatus.available:   return _cAvailable;
      case SeatStatus.standing:    return _cStanding;
      case SeatStatus.disabled:    return _cDisabled;
      case SeatStatus.unavailable: return _cUnavail;
    }
  }

  String _seatLabel(SeatStatus s) {
    switch (s) {
      case SeatStatus.available:   return '이용가능';
      case SeatStatus.standing:    return '스탠드';
      case SeatStatus.disabled:    return '장애인';
      case SeatStatus.unavailable: return '이용불가';
      case SeatStatus.inUse:       return '이용중';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        foregroundColor: _t1,
        title: Text('일반열람실', style: BotanicalTypo.heading(size: 17, color: _t1)),
        actions: [
          if (_room != null)
            Center(child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _cAvailable.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
              child: Text('잔여 ${_room!.available}석',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                  color: _cAvailable)),
            )),
          IconButton(
            icon: Icon(_loading ? Icons.hourglass_empty : Icons.refresh_rounded,
              color: _t2, size: 22),
            onPressed: _loading ? null : _fetch),
        ],
      ),
      body: _loading && _room == null
        ? const Center(child: CircularProgressIndicator())
        : _room == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: _t3),
              const SizedBox(height: 12),
              Text('데이터를 불러올 수 없습니다', style: TextStyle(color: _t3)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _fetch, child: const Text('재시도')),
            ]))
          : Column(children: [
              _summaryBar(),
              const SizedBox(height: 4),
              Expanded(child: _mapArea()),
              _legendBar(),
              _timeStampBar(),
            ]),
    );
  }

  Widget _summaryBar() {
    final r = _room!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withOpacity(0.04))),
      child: Row(children: [
        _miniInfo('전체', '${r.total}', _t2),
        _miniDiv(),
        _miniInfo('사용', '${r.used}', _cInUse),
        _miniDiv(),
        _miniInfo('잔여', '${r.available}', _cAvailable),
        _miniDiv(),
        _miniInfo('이용률', r.rate, BotanicalColors.gold),
        if (r.waiting > 0) ...[_miniDiv(), _miniInfo('대기', '${r.waiting}', Colors.orange)],
      ]),
    );
  }

  Widget _miniInfo(String l, String v, Color c) => Expanded(
    child: Column(children: [
      Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c,
        fontFeatures: const [ui.FontFeature.tabularFigures()])),
      const SizedBox(height: 2),
      Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _t3)),
    ]));

  Widget _miniDiv() => Container(
    width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.black.withOpacity(0.06));

  Widget _mapArea() {
    return Stack(children: [
      GestureDetector(
        onTapDown: (d) {
          final inv = Matrix4.inverted(_txCtrl.value);
          _onTapDown(TapDownDetails(
            localPosition: MatrixUtils.transformPoint(inv, d.localPosition)));
        },
        child: InteractiveViewer(
          transformationController: _txCtrl,
          minScale: 0.5, maxScale: 4.0,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(100),
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => CustomPaint(
              painter: _FloorPainter(
                room: _room!,
                pulse: _pulseCtrl.value,
                seatCenters: _seatCenters),
              size: const Size(390, 910),
            ),
          ),
        ),
      ),
      if (_tappedSeat != null && _tappedOffset != null) _bubble(),
    ]);
  }

  Widget _bubble() {
    final st = _room?.seats[_tappedSeat!];
    if (st == null) return const SizedBox.shrink();
    final c = _seatColor(st);
    final sp = MatrixUtils.transformPoint(_txCtrl.value, _tappedOffset!);
    return Positioned(
      left: sp.dx - 55, top: sp.dy - 48,
      child: IgnorePointer(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xDDFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.6), width: 1.5),
          boxShadow: [BoxShadow(color: c.withOpacity(0.3), blurRadius: 12)]),
        child: Text('#$_tappedSeat ${_seatLabel(st)}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      )),
    );
  }

  Widget _legendBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      // 이용가능: 밝은 사각형
      _legendItem('이용가능', BoxDecoration(
        color: _cAvailable, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 14),
      // 이용중: 빗금 사각형
      _legendItem('이용중', BoxDecoration(
        color: _cInUse.withOpacity(0.45), borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 14),
      // 스탠드: 원형
      _legendItem('스탠드', const BoxDecoration(
        color: _cAvailable, shape: BoxShape.circle)),
    ]),
  );

  Widget _legendItem(String label, BoxDecoration deco) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, decoration: deco),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600, color: _t2)),
    ],
  );

  Widget _timeStampBar() {
    if (_room == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${_room!.fetchedAt.hour.toString().padLeft(2, '0')}:${_room!.fetchedAt.minute.toString().padLeft(2, '0')} 기준',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: _t3)),
    );
  }
}

// ═══════════════════════════════════════════
//  Floor Painter — 단일 열람실 + 좌측 복도
//  열람실: 우측 A-G + 좌측 H/I/J
//  열람실 입구: 좌측 벽 (I-J 사이)
//  복도: 열람실 좌측 벽 바깥, 세로 방향
//  출입문: 복도 하단
// ═══════════════════════════════════════════

class _FloorPainter extends CustomPainter {
  final LibraryRoom room;
  final double pulse;
  final Map<int, Offset> seatCenters;

  _FloorPainter({
    required this.room,
    required this.pulse, required this.seatCenters,
  });

  // 항상 라이트 모드
  static const _bg     = Color(0xFFF5F0E8);
  static const _floor  = Color(0xFFEDE5D4);
  static const _wall   = Color(0xFFB0A080);
  static const _wallIn = Color(0xFFCCC0A4);
  static const _desk   = Color(0xFFC4A872);
  static const _deskLt = Color(0xFFD4BC8A);
  static const _deskEd = Color(0xFFAA9060);
  static const _aisleC = Color(0xFFE8DFC8);
  static const _corrFl = Color(0xFFF0E8D6);
  static const _tileL  = Color(0xFFDDD4C0);
  static const _dimTx  = Color(0xFFA09880);
  static const _labelC = Color(0xFF7A6E5A);

  static const _cInUse     = Color(0xFFFF9F43);
  static const _cAvailable = Color(0xFF48DBFB);
  static const _cStanding  = Color(0xFFA29BFE);
  static const _cDisabled  = Color(0xFFFECA57);
  static const _cUnavail   = Color(0xFF4A4E54);

  Color _sC(SeatStatus s) {
    switch (s) {
      case SeatStatus.inUse:       return _cInUse;
      case SeatStatus.available:   return _cAvailable;
      case SeatStatus.standing:    return _cStanding;
      case SeatStatus.disabled:    return _cDisabled;
      case SeatStatus.unavailable: return _cUnavail;
    }
  }

  // ── Right side: Main 7 blocks (A-G) ──
  static final _main = <List<List<int>>>[
    [[56,55,54,53],[52,51,50,49]], // A (topmost, inner wall)
    [[48,47,46,45],[44,43,42,41]], // B
    [[40,39,38,37],[36,35,34,33]], // C
    [[32,31,30,29],[28,27,26,25]], // D
    [[24,23,22,21],[20,19,18,17]], // E
    [[16,15,14,13],[12,11,10,9]],  // F
    [[8,7,6,5],[4,3,2,1]],         // G (bottommost)
  ];
  static const _mainLabels = ['A','B','C','D','E','F','G'];

  // ── Left side: H/I/J blocks ──
  static final _side = <List<List<int>>>[
    [[61,62,63,64],[57,58,59,60]],                         // H (4 rows)
    [[72,73,74,75,76,77,78],[65,66,67,68,69,70,71]],       // I (7 rows)
    [[84,83,82],[79,80,81]],                                // J (3 rows)
  ];
  static const _sideLabels = ['H','I','J'];

  @override
  void paint(Canvas canvas, Size size) {
    seatCenters.clear();

    // ═══ Constants ═══
    const step = 34.0;      // seat cell size
    const deskTh = 10.0;    // desk thickness
    const blockGap = 26.0;  // between blocks (넉넉하게)
    const roomPad = 30.0;   // room wall → seats (여유)

    // ═══ X Layout ═══
    const corrW = 40.0;     // corridor width
    const corrL = 8.0;
    final corrR = corrL + corrW;

    final roomL = corrR;

    final leftX = roomL + roomPad; // H/I/J blocks
    const sideBlockW = step * 2 + deskTh; // 78
    const aisleW = 46.0;    // internal aisle (넓게)
    final rightX = leftX + sideBlockW + aisleW; // A-G blocks
    const mainCols = 4;
    const mainBlockW = mainCols * step; // 136
    final roomR = rightX + mainBlockW + roomPad;

    // ═══ Y Layout ═══
    const topY = 48.0;
    const mainBlockH = 2 * step + deskTh; // 78
    const mainTotalH = 7 * mainBlockH + 6 * blockGap; // 702
    final roomT = topY - roomPad;
    final roomB = topY + mainTotalH + roomPad;

    // Side blocks centered vertically
    final hH = 4 * step;  // 136
    final iH = 7 * step;  // 238
    final jH = 3 * step;  // 102
    final sideTotalH = hH + iH + jH + 2 * blockGap; // 528
    final sideTopY = topY + (mainTotalH - sideTotalH) / 2;
    final hTopY = sideTopY;
    final iTopY = hTopY + hH + blockGap;
    final jTopY = iTopY + iH + blockGap;

    // Door 1: between H and I (64,60 ~ 72,65)
    final hBottomY = hTopY + hH;
    final door1T = hBottomY;
    final door1B = iTopY;

    // Door 2: between I and J (78,71 ~ 84,79)
    final iBottomY = iTopY + iH;
    final door2T = iBottomY;
    final door2B = jTopY;

    // Corridor
    final corrT = roomT;
    const corrExtend = 90.0;
    final corrB = roomB + corrExtend;

    // ═══ 1. Background ═══
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    // ═══ 2. Room floor ═══
    final roomRect = Rect.fromLTRB(roomL, roomT, roomR, roomB);
    // Subtle gradient floor
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(4)),
      Paint()..shader = ui.Gradient.linear(
        Offset(roomL, roomT), Offset(roomR, roomB),
        [_floor, _floor.withOpacity(0.85)]));
    // Subtle grid lines on floor
    final gridP = Paint()
      ..color = Colors.black.withOpacity(0.018)
      ..strokeWidth = 0.4;
    for (double x = roomL + 20; x < roomR; x += 34) {
      canvas.drawLine(Offset(x, roomT + 4), Offset(x, roomB - 4), gridP);
    }
    for (double y = roomT + 20; y < roomB; y += 34) {
      canvas.drawLine(Offset(roomL + 4, y), Offset(roomR - 4, y), gridP);
    }

    // Internal aisle strip (subtle)
    final aisleL2 = leftX + sideBlockW + 4;
    final aisleR2 = rightX - 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(aisleL2, roomT + 10, aisleR2, roomB - 10),
        const Radius.circular(3)),
      Paint()..color = _aisleC);

    // Corridor floor
    canvas.drawRect(
      Rect.fromLTRB(corrL, corrT, corrR, corrB), Paint()..color = _corrFl);
    // Corridor tile pattern (checkerboard)
    final tileA = Paint()..color = _tileL;
    const tSz = 18.0;
    for (double ty = corrT + 2; ty < corrB - 2; ty += tSz) {
      for (double tx = corrL + 2; tx < corrR - 2; tx += tSz) {
        final ix = ((tx - corrL) / tSz).floor();
        final iy = ((ty - corrT) / tSz).floor();
        if ((ix + iy) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(tx, ty,
            math.min(tSz, corrR - 2 - tx), math.min(tSz, corrB - 2 - ty)), tileA);
        }
      }
    }

    // Carpet texture dots
    final rng = math.Random(42);
    final dotP = Paint()..color = Colors.black.withOpacity(0.010);
    for (int i = 0; i < 500; i++) {
      canvas.drawCircle(
        Offset(roomL + rng.nextDouble() * (roomR - roomL),
               roomT + rng.nextDouble() * (roomB - roomT)),
        rng.nextDouble() * 0.8 + 0.3, dotP);
    }

    // ═══ 3. Seats ═══
    for (int i = 0; i < 7; i++) {
      final blockY = topY + i * (mainBlockH + blockGap);
      _drawMainBlock(canvas, rightX, blockY, _main[i], _mainLabels[i],
        mainCols, step, deskTh);
    }
    _drawSideBlock(canvas, leftX, hTopY, _side[0], _sideLabels[0], step, deskTh);
    _drawSideBlock(canvas, leftX, iTopY, _side[1], _sideLabels[1], step, deskTh);
    _drawSideBlock(canvas, leftX, jTopY, _side[2], _sideLabels[2], step, deskTh);

    // ═══ 4. Room walls ═══
    // Outer wall shadow
    final wallShadow = Paint()
      ..color = Colors.black.withOpacity(0.10)
      ..strokeWidth = 8..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(Offset(roomR + 1, roomT + 4), Offset(roomR + 1, roomB - 4), wallShadow);
    canvas.drawLine(Offset(roomL + 4, roomB + 1), Offset(roomR - 4, roomB + 1), wallShadow);

    final wP = Paint()..color = _wall..strokeWidth = 5..strokeCap = StrokeCap.round;

    // Top wall (room + corridor share top)
    canvas.drawLine(Offset(corrL, roomT), Offset(roomR, roomT), wP);
    // Right wall
    canvas.drawLine(Offset(roomR, roomT), Offset(roomR, roomB), wP);
    // Bottom wall
    canvas.drawLine(Offset(roomL, roomB), Offset(roomR, roomB), wP);

    // Left wall of room (2 door gaps: H-I and I-J)
    canvas.drawLine(Offset(roomL, roomT), Offset(roomL, door1T), wP);
    canvas.drawLine(Offset(roomL, door1B), Offset(roomL, door2T), wP);
    canvas.drawLine(Offset(roomL, door2B), Offset(roomL, roomB), wP);

    // ═══ 5. Corridor walls ═══
    canvas.drawLine(Offset(corrL, corrT), Offset(corrL, corrB), wP);
    canvas.drawLine(Offset(roomL, roomB), Offset(roomL, corrB), wP);

    // Corridor bottom wall with main entrance gap
    final mainEntrCx = (corrL + corrR) / 2;
    const mainEntrHL = 16.0;
    canvas.drawLine(Offset(corrL, corrB), Offset(mainEntrCx - mainEntrHL, corrB), wP);
    canvas.drawLine(Offset(mainEntrCx + mainEntrHL, corrB), Offset(corrR, corrB), wP);

    // Inner wall depth (room top + right)
    final iWP = Paint()..color = _wallIn..strokeWidth = 1.5;
    canvas.drawLine(Offset(roomL + 6, roomT + 6), Offset(roomR - 6, roomT + 6), iWP);
    canvas.drawLine(Offset(roomR - 6, roomT + 6), Offset(roomR - 6, roomB - 6), iWP);

    // ═══ 6. Door markers ═══
    final dfP = Paint()..color = _wall..strokeWidth = 3.5..strokeCap = StrokeCap.round;
    final doorArc = Paint()
      ..color = _labelC.withOpacity(0.15)
      ..style = PaintingStyle.stroke..strokeWidth = 1;

    // Door 1 (H-I gap)
    canvas.drawLine(Offset(roomL - 5, door1T), Offset(roomL + 5, door1T), dfP);
    canvas.drawLine(Offset(roomL - 5, door1B), Offset(roomL + 5, door1B), dfP);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(roomL, door1T), width: 22, height: 22),
      -math.pi / 2, math.pi / 2, false, doorArc);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(roomL, door1B), width: 22, height: 22),
      0, math.pi / 2, false, doorArc);

    // Door 2 (I-J gap)
    canvas.drawLine(Offset(roomL - 5, door2T), Offset(roomL + 5, door2T), dfP);
    canvas.drawLine(Offset(roomL - 5, door2B), Offset(roomL + 5, door2B), dfP);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(roomL, door2T), width: 22, height: 22),
      -math.pi / 2, math.pi / 2, false, doorArc);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(roomL, door2B), width: 22, height: 22),
      0, math.pi / 2, false, doorArc);

    // Main entrance
    canvas.drawLine(Offset(mainEntrCx - mainEntrHL, corrB - 4),
      Offset(mainEntrCx - mainEntrHL, corrB + 5), dfP);
    canvas.drawLine(Offset(mainEntrCx + mainEntrHL, corrB - 4),
      Offset(mainEntrCx + mainEntrHL, corrB + 5), dfP);

    // ═══ 7. Labels ═══
    _drawLabel(canvas, Offset((roomL + roomR) / 2, roomT + 16),
      '안쪽 벽', color: _dimTx, size: 10);

    // Door labels
    final door1Cy = (door1T + door1B) / 2;
    final door2Cy = (door2T + door2B) / 2;
    _drawLabel(canvas, Offset(corrR - 6, door1Cy),
      '문', color: _labelC, size: 8, bold: true);
    _drawLabel(canvas, Offset(corrR - 6, door2Cy),
      '문', color: _labelC, size: 8, bold: true);

    // Corridor label
    _drawLabel(canvas, Offset((corrL + corrR) / 2, (roomB + corrB) / 2),
      '복도', color: _dimTx.withOpacity(0.5), size: 9);

    // Main entrance label + arrow
    _drawLabel(canvas, Offset(mainEntrCx, corrB + 14),
      '출입문', color: _labelC, size: 10, bold: true);
    final mArrow = Path()
      ..moveTo(mainEntrCx, corrB + 26)
      ..lineTo(mainEntrCx - 6, corrB + 36)
      ..lineTo(mainEntrCx + 6, corrB + 36)
      ..close();
    canvas.drawPath(mArrow, Paint()..color = _labelC.withOpacity(0.5));

    // Corridor direction arrows (up toward room entrance)
    final arP = Paint()..color = _labelC.withOpacity(0.25)..style = PaintingStyle.fill;
    final corrCx = (corrL + corrR) / 2;
    for (double y = corrB - 20; y > door2Cy + 20; y -= 30) {
      final arrow = Path()
        ..moveTo(corrCx, y - 5)
        ..lineTo(corrCx - 3, y + 2)
        ..lineTo(corrCx + 3, y + 2)
        ..close();
      canvas.drawPath(arrow, arP);
    }
  }

  // ── Main block: 2 rows × 4 cols, horizontal desk ──
  void _drawMainBlock(Canvas canvas, double x, double y,
      List<List<int>> rows, String label, int cols, double step, double deskTh) {
    final blockW = cols * step;

    // Row 0 (top row)
    for (int c = 0; c < cols; c++) {
      _drawSeat(canvas, Offset(x + c * step + step / 2, y + step / 2), rows[0][c]);
    }

    // Horizontal desk between rows
    final deskY = y + step;
    final dR = RRect.fromLTRBR(x + 2, deskY, x + blockW - 2, deskY + deskTh,
      const Radius.circular(2));
    canvas.drawRRect(dR.shift(const Offset(1, 1)), Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(dR, Paint()
      ..shader = ui.Gradient.linear(
        Offset(x, deskY), Offset(x, deskY + deskTh),
        [_deskLt, _desk]));
    canvas.drawRRect(dR, Paint()
      ..color = _deskEd..style = PaintingStyle.stroke..strokeWidth = 0.6);
    // Grain
    final gP = Paint()..color = _deskEd.withOpacity(0.2)..strokeWidth = 0.3;
    for (double gx = x + 6; gx < x + blockW - 4; gx += 8) {
      canvas.drawLine(Offset(gx, deskY + 1), Offset(gx, deskY + deskTh - 1), gP);
    }

    // Row 1 (bottom row)
    for (int c = 0; c < cols; c++) {
      _drawSeat(canvas, Offset(x + c * step + step / 2, y + step + deskTh + step / 2),
        rows[1][c]);
    }

    // Label (right side)
    _drawLabel(canvas, Offset(x + blockW + 16, y + step + deskTh / 2), label,
      color: _labelC, size: 12, bold: true);
  }

  // ── Side block: 2 cols × N rows, vertical desk ──
  void _drawSideBlock(Canvas canvas, double x, double y,
      List<List<int>> cols, String label, double step, double deskTh) {
    final rows = cols[0].length;

    // Col 0 (left column)
    for (int r = 0; r < rows; r++) {
      _drawSeat(canvas, Offset(x + step / 2, y + r * step + step / 2), cols[0][r]);
    }

    // Vertical desk
    final deskX = x + step;
    final blockH = rows * step;
    final dR = RRect.fromLTRBR(deskX, y + 2, deskX + deskTh, y + blockH - 2,
      const Radius.circular(2));
    canvas.drawRRect(dR.shift(const Offset(1, 1)), Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(dR, Paint()
      ..shader = ui.Gradient.linear(
        Offset(deskX, y), Offset(deskX + deskTh, y),
        [_deskLt, _desk]));
    canvas.drawRRect(dR, Paint()
      ..color = _deskEd..style = PaintingStyle.stroke..strokeWidth = 0.6);
    // Grain
    final gP = Paint()..color = _deskEd.withOpacity(0.2)..strokeWidth = 0.3;
    for (double gy = y + 6; gy < y + blockH - 4; gy += 8) {
      canvas.drawLine(Offset(deskX + 1, gy), Offset(deskX + deskTh - 1, gy), gP);
    }

    // Col 1 (right column)
    for (int r = 0; r < rows; r++) {
      _drawSeat(canvas, Offset(x + step + deskTh + step / 2, y + r * step + step / 2),
        cols[1][r]);
    }

    // Label (above)
    _drawLabel(canvas, Offset(x + step + deskTh / 2, y - 14), label,
      color: _labelC, size: 12, bold: true);
  }

  // ── Seat drawing ──
  // disabled/unavailable → 빈 윤곽만 (faint)
  // available → 밝은 사각형 (눈에 바로 띔)
  // inUse → 어두운 사각형 + 대각선 빗금 (패턴으로 구분)
  // standing → 원형 + 점선 테두리 (모양으로 구분)
  void _drawSeat(Canvas canvas, Offset center, int num) {
    final status = room.seats[num] ?? SeatStatus.unavailable;
    const sz = 26.0;
    const r = 5.0;
    final rect = Rect.fromCenter(center: center, width: sz, height: sz);

    seatCenters[num] = center;

    // ── disabled / unavailable: 빈 자리 윤곽만 ──
    if (status == SeatStatus.disabled || status == SeatStatus.unavailable) {
      final faint = Paint()
        ..color = Colors.black.withOpacity(0.05)
        ..style = PaintingStyle.stroke..strokeWidth = 0.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(r)), faint);
      canvas.drawCircle(center, 1.5,
        Paint()..color = Colors.black.withOpacity(0.06));
      return;
    }

    // ── standing: 원형 + 점선 테두리 + S 뱃지 ──
    if (status == SeatStatus.standing) {
      canvas.drawCircle(center, sz / 2 + 3,
        Paint()..color = _cAvailable.withOpacity(0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(center + const Offset(0.8, 2), sz / 2,
        Paint()..color = Colors.black.withOpacity(0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(center, sz / 2, Paint()..color = _cAvailable);
      canvas.drawCircle(center + const Offset(0, -2.5), sz / 2 - 4,
        Paint()..color = Colors.white.withOpacity(0.15));
      final dashP = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke..strokeWidth = 1.8;
      const dashes = 14;
      for (int i = 0; i < dashes; i++) {
        final a1 = (i / dashes) * 2 * math.pi;
        final a2 = ((i + 0.45) / dashes) * 2 * math.pi;
        final p1 = center + Offset(math.cos(a1) * sz / 2, math.sin(a1) * sz / 2);
        final p2 = center + Offset(math.cos(a2) * sz / 2, math.sin(a2) * sz / 2);
        canvas.drawLine(p1, p2, dashP);
      }
      _drawLabel(canvas, center, '$num',
        color: Colors.white, size: 8.5, bold: true);
      final badge = center + const Offset(10, 10);
      canvas.drawCircle(badge, 6,
        Paint()..color = Colors.white);
      canvas.drawCircle(badge, 6,
        Paint()..color = _cAvailable.withOpacity(0.3)
          ..style = PaintingStyle.stroke..strokeWidth = 0.8);
      _drawLabel(canvas, badge, 'S',
        color: _cAvailable, size: 7, bold: true);
      return;
    }

    // ── available / inUse: 사각형 ──
    final isAvail = status == SeatStatus.available;
    final baseColor = isAvail ? _cAvailable : _cInUse;

    // Glow
    if (isAvail) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(r + 4)),
        Paint()..color = baseColor.withOpacity(0.16 + pulse * 0.10)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + pulse * 3));
    }

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(r))
        .shift(const Offset(1, 2)),
      Paint()..color = Colors.black.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(r)),
      Paint()..color = baseColor.withOpacity(isAvail ? 1.0 : 0.40));

    // Highlight (available)
    if (isAvail) {
      final hl = Rect.fromLTRB(
        rect.left + 4, rect.top + 2, rect.right - 4, rect.top + sz * 0.32);
      canvas.drawRRect(RRect.fromRectAndRadius(hl, const Radius.circular(3)),
        Paint()..color = Colors.white.withOpacity(0.20));
    }

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(r)),
      Paint()..color = baseColor.withOpacity(isAvail ? 0.6 : 0.25)
        ..style = PaintingStyle.stroke..strokeWidth = isAvail ? 1.2 : 0.8);

    // inUse: 대각선 빗금 패턴
    if (!isAvail) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(r)));
      final hatchP = Paint()
        ..color = Colors.white.withOpacity(0.4)
        ..strokeWidth = 1.4;
      for (double d = -sz; d < sz * 2; d += 6) {
        canvas.drawLine(
          Offset(rect.left + d, rect.top),
          Offset(rect.left + d - sz, rect.bottom), hatchP);
      }
      canvas.restore();
    }

    // Number
    _drawLabel(canvas, center, '$num',
      color: Colors.white.withOpacity(isAvail ? 1.0 : 0.55),
      size: 8.5, bold: true);
  }

  void _drawLabel(Canvas canvas, Offset center, String text, {
    required Color color, required double size, bool bold = false,
  }) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center, fontSize: size,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
    ))
      ..pushStyle(ui.TextStyle(
        color: color, fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
        letterSpacing: -0.3))
      ..addText(text);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 50));
    canvas.drawParagraph(p, Offset(center.dx - 25, center.dy - p.height / 2));
  }

  @override
  bool shouldRepaint(_FloorPainter old) => true;
}
