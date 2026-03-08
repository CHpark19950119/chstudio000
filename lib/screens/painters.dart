import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 종이 질감 배경 페인터
class PaperGrainPainter extends CustomPainter {
  final bool dark;
  PaperGrainPainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withOpacity(0.012)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 800; i++) {
      canvas.drawCircle(
        Offset(rand.nextDouble() * size.width, rand.nextDouble() * size.height),
        rand.nextDouble() * 1.2, paint);
    }
  }
  @override
  bool shouldRepaint(covariant PaperGrainPainter old) => old.dark != dark;
}

/// Cyber Grid 배경 페인터 — 홈스크린 등에서 사용
class CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    const gap = 18.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ═══════════════════════════════════════════════════
///  Water Wave Painter — 캘린더 셀 워터탱크 파도
///  웹앱 cal-water-tank + cal-wave 재현
/// ═══════════════════════════════════════════════════
class WaterWavePainter extends CustomPainter {
  final double fillPercent; // 0.0 ~ 1.0
  final double phase;       // 애니메이션 phase (0.0 ~ 1.0)
  final Color waterColor;
  final Color waveColor;

  WaterWavePainter({
    required this.fillPercent,
    required this.phase,
    this.waterColor = const Color(0xFF38BDF8),
    this.waveColor = const Color(0xFF38BDF8),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fillPercent <= 0) return;

    final waterHeight = size.height * fillPercent.clamp(0.0, 0.88);
    final waterTop = size.height - waterHeight;

    // ── 1. 물 채우기 (그라데이션) ──
    final waterRect = Rect.fromLTWH(0, waterTop, size.width, waterHeight);
    final waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          waterColor.withOpacity(0.25),
          waterColor.withOpacity(0.45),
        ],
      ).createShader(waterRect);

    // 둥근 하단 클리핑
    final rrect = RRect.fromLTRBAndCorners(
      0, waterTop, size.width, size.height,
      bottomLeft: const Radius.circular(11),
      bottomRight: const Radius.circular(11),
    );
    canvas.drawRRect(rrect, waterPaint);

    // ── 2. 뒷 파도 (느린, 투명) ──
    _drawWave(canvas, size, waterTop, phase * 0.7,
      amplitude: 2.5, frequency: 2.0,
      color: waveColor.withOpacity(0.30));

    // ── 3. 앞 파도 (빠른, 진한) ──
    _drawWave(canvas, size, waterTop, phase,
      amplitude: 3.0, frequency: 2.5,
      color: waveColor.withOpacity(0.50));

    // ── 4. 수면 하이라이트 ──
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.35),
          Colors.white.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(
        size.width * 0.08, waterTop - 1,
        size.width * 0.84, 2));
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.08, waterTop - 0.5, size.width * 0.84, 1.5),
      highlightPaint);
  }

  void _drawWave(Canvas canvas, Size size, double waterTop, double p, {
    required double amplitude,
    required double frequency,
    required Color color,
  }) {
    final path = Path()..moveTo(0, waterTop);
    for (double x = 0; x <= size.width; x += 1) {
      final y = waterTop +
          math.sin((x / size.width * frequency * math.pi) + p * math.pi * 2) * amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter old) =>
      old.fillPercent != fillPercent || old.phase != phase;
}

/// ═══════════════════════════════════════════════════
///  24시간 타임라인 그리드 페인터
/// ═══════════════════════════════════════════════════
class TimelineGridPainter extends CustomPainter {
  final int startHour;
  final int endHour;
  final double rowHeight;
  final Color lineColor;
  final Color textColor;

  TimelineGridPainter({
    required this.startHour,
    required this.endHour,
    required this.rowHeight,
    this.lineColor = const Color(0x15000000),
    this.textColor = const Color(0x60000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    for (int h = startHour; h <= endHour; h++) {
      final y = (h - startHour) * rowHeight;
      final isPeriod = h % 6 == 0;

      if (isPeriod) {
        canvas.drawLine(Offset(44, y), Offset(size.width, y),
          linePaint..strokeWidth = 1.5..color = lineColor.withOpacity(0.3));
      } else {
        double x = 44;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + 4, y), dashPaint);
          x += 8;
        }
      }

      final tp = TextPainter(
        text: TextSpan(
          text: h.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: isPeriod ? FontWeight.w700 : FontWeight.w500,
            color: isPeriod ? textColor.withOpacity(0.8) : textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(34 - tp.width, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant TimelineGridPainter old) => false;
}


// ═══════════════════════════════════════════════════════════════
//  ★ 작업4: 홈 대시보드 모션 이펙트용 페인터
// ═══════════════════════════════════════════════════════════════


/// ── A) Breathing Glow (숨쉬는 발광) ──
/// D-Day 카드 외곽에 부드러운 빛 파동 효과
class BreathingGlowPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color glowColor;
  final double borderRadius;

  BreathingGlowPainter({
    required this.progress,
    required this.glowColor,
    this.borderRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = (math.sin(progress * math.pi * 2) + 1) / 2; // 0~1 oscillation
    final maxSpread = 12.0;
    final spread = maxSpread * intensity;

    for (int i = 3; i >= 0; i--) {
      final layerSpread = spread * (i / 3.0);
      final opacity = (0.08 * intensity * (1 - i / 4.0)).clamp(0.0, 0.15);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-layerSpread, -layerSpread,
          size.width + layerSpread * 2, size.height + layerSpread * 2),
        Radius.circular(borderRadius + layerSpread));
      canvas.drawRRect(rrect, Paint()
        ..color = glowColor.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + layerSpread));
    }
  }

  @override
  bool shouldRepaint(covariant BreathingGlowPainter old) =>
      old.progress != progress || old.glowColor != glowColor;
}


/// ── B) Floating Particles (떠다니는 입자) ──
/// 보태니컬 분위기의 배경 파티클
class FloatingParticlesPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0 (반복)
  final List<Color> particleColors;
  final int count;

  FloatingParticlesPainter({
    required this.progress,
    this.particleColors = const [Color(0xFFFBBF24), Color(0xFF6EE7B7)],
    this.count = 7,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    for (int i = 0; i < count; i++) {
      final baseX = rand.nextDouble() * size.width;
      final speed = 0.6 + rand.nextDouble() * 0.4;
      final phase = (progress * speed + i * 0.13) % 1.0;

      // 위로 올라가는 Y 계산
      final y = size.height * (1.0 - phase);
      final x = baseX + math.sin(phase * math.pi * 3 + i) * 15;

      // 투명도: 중간에 가장 밝고 양 끝에서 사라짐
      final fadeCurve = math.sin(phase * math.pi);
      final opacity = (0.35 * fadeCurve).clamp(0.0, 0.4);
      if (opacity < 0.02) continue;

      final radius = 2.0 + rand.nextDouble() * 2.5;
      final color = particleColors[i % particleColors.length].withOpacity(opacity);

      canvas.drawCircle(Offset(x, y), radius, Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }

  @override
  bool shouldRepaint(covariant FloatingParticlesPainter old) =>
      old.progress != progress;
}


/// ── C) Morphing Blob (변형 블롭) ──
/// "이 디자인은 꼭 사용할것" — blob morph 애니메이션 재현
class MorphingBlobPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0 (8초 주기)
  final Color blobColor;
  final Color? secondaryColor;

  MorphingBlobPainter({
    required this.progress,
    required this.blobColor,
    this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.85;

    // 8개 제어점으로 blob 형태 생성
    final path = Path();
    final points = <Offset>[];
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * math.pi * 2;
      final wobble = math.sin(progress * math.pi * 2 + i * 0.9) * baseR * 0.15;
      final r = baseR + wobble;
      points.add(Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r));
    }

    // Catmull-Rom 스플라인으로 부드러운 blob
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length; i++) {
      final p0 = points[(i - 1 + points.length) % points.length];
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      final p3 = points[(i + 2) % points.length];

      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();

    // 그라디언트 채우기
    final gradient = RadialGradient(
      center: Alignment(
        -0.2 + math.sin(progress * math.pi * 2) * 0.3,
        -0.3 + math.cos(progress * math.pi * 2) * 0.2,
      ),
      radius: 1.0,
      colors: [
        blobColor.withOpacity(0.5),
        (secondaryColor ?? blobColor).withOpacity(0.3),
      ],
    );

    canvas.drawPath(path, Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: baseR)));

    // 내부 하이라이트
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));
  }

  @override
  bool shouldRepaint(covariant MorphingBlobPainter old) =>
      old.progress != progress;
}


/// ── D) Shimmer Scan Line (스캔 라인) ──
/// 카드 위 반투명 하이라이트 스윕 효과
class ShimmerScanPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final double borderRadius;

  ShimmerScanPainter({
    required this.progress,
    this.borderRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 카드 영역 클리핑
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius)));

    // 좌→우 스캔 라인
    final scanX = -size.width * 0.3 + progress * (size.width * 1.6);
    final scanWidth = size.width * 0.3;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(scanX, 0, scanWidth, size.height));

    canvas.drawRect(
      Rect.fromLTWH(scanX, 0, scanWidth, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant ShimmerScanPainter old) =>
      old.progress != progress;
}


/// ── F) Pulse Ring (펄스 링) ──
/// 포커스 진행 시 동심원 확산 효과
class PulseRingPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color ringColor;
  final int ringCount;

  PulseRingPainter({
    required this.progress,
    required this.ringColor,
    this.ringCount = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy);

    for (int i = 0; i < ringCount; i++) {
      final ringPhase = (progress + i / ringCount) % 1.0;
      final r = maxR * 0.3 + maxR * 0.7 * ringPhase;
      final opacity = (1.0 - ringPhase) * 0.3;
      if (opacity < 0.01) continue;

      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = ringColor.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1.0 - ringPhase));
    }
  }

  @override
  bool shouldRepaint(covariant PulseRingPainter old) =>
      old.progress != progress;
}