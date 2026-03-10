import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart' show CustomPainter, Size;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/sprite.dart';  // SpriteSheet, SpriteAnimation
import 'pixel_palette.dart';

// ═══════════════════════════════════════════
//  3D Voxel creature — sprite sheet animation
// ═══════════════════════════════════════════

class CreatureComponent extends PositionComponent with HasGameRef, TapCallbacks {
  int stage;
  String mood;
  double _baseY = 0;
  double _timer = 0;
  double _stateTimer = 0;
  double _walkDir = 1;
  _CState _state = _CState.idle;
  final _rng = math.Random();
  final List<_PxParticle> _particles = [];

  SpriteAnimationComponent? _animComp;

  CreatureComponent({required this.stage, required this.mood});

  @override
  Future<void> onLoad() async {
    // prefix = 'assets/habitat/' → '../image/' resolves to 'assets/image/'
    final image = await gameRef.images.load('../image/creature_3d_sheet_128.png');

    final sheet = SpriteSheet(image: image, srcSize: Vector2(128, 128));

    // Build 36-frame animation (6×6 grid, 10fps)
    final frames = <SpriteAnimationFrame>[];
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 6; col++) {
        frames.add(SpriteAnimationFrame(sheet.getSprite(row, col), 0.1));
      }
    }
    final anim = SpriteAnimation(frames);

    final scale = _scaleForStage();
    final sz = 128.0 * scale;
    size = Vector2(sz, sz);

    _animComp = SpriteAnimationComponent(
      animation: anim,
      size: Vector2(sz, sz),
    );
    add(_animComp!);

    _baseY = position.y;
  }

  double _scaleForStage() {
    switch (stage.clamp(0, 4)) {
      case 0: return 0.5;
      case 1: return 0.65;
      case 2: return 0.8;
      case 3: return 1.0;
      case 4: return 1.2;
      default: return 0.5;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    _stateTimer += dt;

    switch (_state) {
      case _CState.idle:
        position.y = _baseY + math.sin(_timer * 1.5) * 3;
        if (_stateTimer > 3 + _rng.nextDouble() * 3) {
          _state = _CState.walk;
          _stateTimer = 0;
          _walkDir = _rng.nextBool() ? 1 : -1;
          _updateFlip();
        }
        if (_stateTimer > 2 && _rng.nextDouble() < 0.003) {
          _state = _CState.jump;
          _stateTimer = 0;
        }
        final h = DateTime.now().hour;
        if (h >= 22 || h < 4) {
          _state = _CState.sleep;
          _animComp?.animation?.stepTime = 0.3; // slow
        }
        break;
      case _CState.walk:
        position.x += _walkDir * 20 * dt;
        position.y = _baseY + math.sin(_timer * 4) * 1.5;
        final gw = gameRef.size.x;
        if (position.x < gw * 0.15) { _walkDir = 1; _updateFlip(); }
        if (position.x > gw * 0.75) { _walkDir = -1; _updateFlip(); }
        if (_stateTimer > 2 + _rng.nextDouble() * 2) {
          _state = _CState.idle;
          _stateTimer = 0;
        }
        break;
      case _CState.jump:
        position.y = _baseY - math.sin(_stateTimer * 4) * 12;
        if (_stateTimer > 0.8) {
          _state = _CState.idle;
          _stateTimer = 0;
          position.y = _baseY;
        }
        break;
      case _CState.happy:
        position.y = _baseY - math.sin(_stateTimer * 8) * 8;
        if (_stateTimer > 2.0) {
          _state = _CState.idle;
          _stateTimer = 0;
        }
        break;
      case _CState.sleep:
        position.y = _baseY;
        final h = DateTime.now().hour;
        if (h >= 4 && h < 22) {
          _state = _CState.idle;
          _animComp?.animation?.stepTime = 0.1; // normal
        }
        break;
    }

    // Particles
    _particles.removeWhere((p) => p.life <= 0);
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy -= 15 * dt;
      p.life -= dt;
    }
  }

  void _updateFlip() {
    final comp = _animComp;
    if (comp == null) return;
    if (_walkDir < 0 && !comp.isFlippedHorizontally) {
      comp.flipHorizontally();
    } else if (_walkDir > 0 && comp.isFlippedHorizontally) {
      comp.flipHorizontally();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    _state = _CState.jump;
    _stateTimer = 0;
    _spawnParticles(30, 3);
  }

  void triggerHappy() {
    _state = _CState.happy;
    _stateTimer = 0;
    _spawnParticles(18, 10);
  }

  void _spawnParticles(int colorIdx, int count) {
    for (int i = 0; i < count; i++) {
      _particles.add(_PxParticle(
        x: size.x / 2,
        y: size.y / 4,
        vx: (_rng.nextDouble() - 0.5) * 30,
        vy: -15 - _rng.nextDouble() * 20,
        colorIdx: [18, 30, 22, 25, 19][_rng.nextInt(5)],
        life: 0.8 + _rng.nextDouble() * 0.6,
      ));
    }
  }

  @override
  void render(Canvas canvas) {
    // Particles
    for (final p in _particles) {
      final color = masterPalette[p.colorIdx];
      if (color == null) continue;
      canvas.drawCircle(
        Offset(p.x, p.y), 2,
        Paint()..color = color.withOpacity(p.life.clamp(0, 1)),
      );
    }

    // zzZ for sleep
    if (_state == _CState.sleep) {
      final zOff = math.sin(_timer * 2) * 4;
      final zP = Paint()..color = const Color(0x80FFFFFF);
      canvas.drawCircle(Offset(size.x - 8, -4 + zOff), 2, zP);
      canvas.drawCircle(Offset(size.x - 2, -10 + zOff), 1.5,
          Paint()..color = const Color(0x50FFFFFF));
    }

    // LEGEND aura glow
    if (stage == 4) {
      final glowA = 0.15 + 0.10 * math.sin(_timer * 2);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.6,
        Paint()
          ..color = Color.fromARGB((glowA * 255).round(), 255, 215, 0)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      );
    }
  }
}

enum _CState { idle, walk, jump, happy, sleep }

class _PxParticle {
  double x, y, vx, vy, life;
  int colorIdx;
  _PxParticle({required this.x, required this.y, required this.vx,
    required this.vy, required this.colorIdx, required this.life});
}

// ═══════ Mini painter for float button (first frame of sheet) ═══════
class MiniCreaturePainter extends CustomPainter {
  final int stage;
  MiniCreaturePainter({required this.stage});

  @override
  void paint(Canvas canvas, Size size) {
    // Fallback simple bird icon when sprite sheet not available in CustomPainter
    final p = Paint()..color = const Color(0xFF7C6DF5);
    final cx = size.width / 2, cy = size.height / 2;
    final s = size.width * 0.35;
    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 1.6, height: s * 1.2), p);
    // Head
    canvas.drawCircle(Offset(cx - s * 0.3, cy - s * 0.4), s * 0.45,
        Paint()..color = const Color(0xFF9B8DFF));
    // Eye
    canvas.drawCircle(Offset(cx - s * 0.15, cy - s * 0.45), s * 0.1,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(Offset(cx - s * 0.12, cy - s * 0.47), s * 0.05,
        Paint()..color = const Color(0xFF1A1A2E));
    // Beak
    final beak = Path()
      ..moveTo(cx - s * 0.6, cy - s * 0.35)
      ..lineTo(cx - s * 0.85, cy - s * 0.25)
      ..lineTo(cx - s * 0.6, cy - s * 0.2);
    canvas.drawPath(beak, Paint()..color = const Color(0xFFFF8F00));
    // Wing
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + s * 0.2, cy - s * 0.1),
          width: s * 0.8, height: s * 0.5),
      Paint()..color = const Color(0xFF6B5CE7));
    // Crown for legend
    if (stage == 4) {
      canvas.drawCircle(Offset(cx - s * 0.3, cy - s * 0.8), s * 0.12,
          Paint()..color = const Color(0xFFFFD700));
    }
  }

  @override
  bool shouldRepaint(MiniCreaturePainter old) => old.stage != stage;
}
