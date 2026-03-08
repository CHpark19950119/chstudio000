import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'habitat_background.dart';
import 'creature_component.dart';
import 'habitat_item.dart';
import 'pixel_palette.dart';

class HabitatGame extends FlameGame {
  final Map<String, dynamic> creatureData;
  bool editMode;
  Function(String id, double x, double y)? onItemMoved;

  late CreatureComponent creature;
  bool _hasFireplace = false;

  HabitatGame({required this.creatureData, this.editMode = false, this.onItemMoved});

  @override
  ui.Color backgroundColor() => const ui.Color(0xFF1A0E05);

  @override
  Future<void> onLoad() async {
    images.prefix = 'assets/habitat/';

    final hour = DateTime.now().hour;
    final w = size.x;
    final h = size.y;

    // Layer 1: background image
    add(HabitatBackground());

    // Layer 2: placed items
    final placed = creatureData['placedItems'];
    if (placed is List) {
      for (final item in placed) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final x = (item['x'] as num?)?.toDouble() ?? 0.5;
          final y = (item['y'] as num?)?.toDouble() ?? 0.7;
          if (id == 'campfire') _hasFireplace = true;
          add(HabitatItemComponent(
            itemId: id,
            position: Vector2(x * w, y * h),
            editable: editMode,
            onMoved: (mid, px, py) {
              onItemMoved?.call(mid, px / w, py / h);
            },
          ));
        }
      }
    }

    // Layer 3: NPCs
    // Cat on the carpet area
    add(_LibraryCat(position: Vector2(w * 0.28, h * 0.70)));
    // Owl on the right bookshelf
    add(_ShelfOwl(position: Vector2(w * 0.82, h * 0.12)));

    // Layer 4: player creature — on carpet (~67% height)
    final stage = (creatureData['stage'] as num?)?.toInt() ?? 0;
    final mood = creatureData['mood']?.toString() ?? 'neutral';
    creature = CreatureComponent(stage: stage, mood: mood);
    creature.position = Vector2(w * 0.45, h * 0.67);
    add(creature);

    // Layer 5: magical particles
    add(_MagicalParticles(hour: hour, hasFireplace: _hasFireplace));

    // Layer 6: candle flicker overlay
    add(_CandleFlickerOverlay(hour: hour, hasFireplace: _hasFireplace));
  }

  void triggerHappy() {
    creature.triggerHappy();
  }
}

/// ── Sleeping library cat on the carpet ──
class _LibraryCat extends PositionComponent with HasGameRef {
  double _timer = 0;

  _LibraryCat({required Vector2 position})
      : super(position: position, size: Vector2(40, 24));

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
  }

  @override
  void render(ui.Canvas c) {
    final breath = math.sin(_timer * 1.5) * 1.2;
    final s = 8.0;

    // Body
    c.drawOval(
      ui.Rect.fromCenter(center: ui.Offset(s * 2.5, s * 1.5 + breath * 0.3),
          width: s * 4.5, height: s * 2.2 + breath * 0.5),
      ui.Paint()..color = const ui.Color(0xFFE8A050));
    // Stripes
    final stripeP = ui.Paint()..color = const ui.Color(0xB0C07030)..strokeWidth = 1;
    for (int i = 0; i < 3; i++) {
      final sx = s * 1.2 + i * s * 1.0;
      c.drawLine(ui.Offset(sx, s * 0.7 + breath * 0.2),
          ui.Offset(sx + 1, s * 2.2 + breath * 0.3), stripeP);
    }
    // Head
    c.drawCircle(ui.Offset(s * 0.3, s * 0.8), s * 0.9,
        ui.Paint()..color = const ui.Color(0xFFE8A050));
    // Ears
    final ear = ui.Path()..moveTo(-s * 0.3, s * 0.2)..lineTo(-s * 0.1, -s * 0.4)..lineTo(s * 0.2, s * 0.1);
    c.drawPath(ear, ui.Paint()..color = const ui.Color(0xFFE8A050));
    final ear2 = ui.Path()..moveTo(s * 0.3, s * 0.1)..lineTo(s * 0.6, -s * 0.3)..lineTo(s * 0.9, s * 0.2);
    c.drawPath(ear2, ui.Paint()..color = const ui.Color(0xFFE8A050));
    c.drawPath(ui.Path()..moveTo(-s * 0.15, s * 0.15)..lineTo(-s * 0.05, -s * 0.15)..lineTo(s * 0.1, s * 0.1),
        ui.Paint()..color = const ui.Color(0xFFF9A8C9));
    // Closed eyes
    c.drawLine(ui.Offset(-s * 0.1, s * 0.7), ui.Offset(s * 0.15, s * 0.6),
        ui.Paint()..color = const ui.Color(0xFF333333)..strokeWidth = 1.5..strokeCap = ui.StrokeCap.round);
    c.drawLine(ui.Offset(s * 0.35, s * 0.65), ui.Offset(s * 0.6, s * 0.55),
        ui.Paint()..color = const ui.Color(0xFF333333)..strokeWidth = 1.5..strokeCap = ui.StrokeCap.round);
    // Nose
    c.drawCircle(ui.Offset(s * 0.15, s * 0.95), 1.2,
        ui.Paint()..color = const ui.Color(0xFFF9A8C9));
    // Tail
    final tail = ui.Path()
      ..moveTo(s * 4.5, s * 1.5)
      ..quadraticBezierTo(s * 5.5, s * 0.3 + math.sin(_timer * 0.8) * 2, s * 5.0, -s * 0.2);
    c.drawPath(tail, ui.Paint()
      ..color = const ui.Color(0xFFE8A050)..style = ui.PaintingStyle.stroke
      ..strokeWidth = s * 0.35..strokeCap = ui.StrokeCap.round);
    // Front paw
    c.drawOval(ui.Rect.fromLTWH(-s * 0.3, s * 1.8, s * 0.8, s * 0.5),
        ui.Paint()..color = const ui.Color(0xFFE8A050));
  }
}

/// ── Perched library owl ──
class _ShelfOwl extends PositionComponent with HasGameRef {
  double _timer = 0;
  double _blinkTimer = 0;
  bool _blink = false;

  _ShelfOwl({required Vector2 position})
      : super(position: position, size: Vector2(20, 28));

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    _blinkTimer += dt;
    if (_blinkTimer > 4.0) {
      _blink = true;
      if (_blinkTimer > 4.15) _blinkTimer = 0;
    } else {
      _blink = false;
    }
  }

  @override
  void render(ui.Canvas c) {
    final s = 6.0;
    // Body
    c.drawOval(ui.Rect.fromCenter(center: ui.Offset(s * 1.5, s * 2.2), width: s * 2.5, height: s * 3.0),
        ui.Paint()..color = const ui.Color(0xFF8B6914));
    c.drawOval(ui.Rect.fromCenter(center: ui.Offset(s * 1.5, s * 2.6), width: s * 1.6, height: s * 2.0),
        ui.Paint()..color = const ui.Color(0xFFDEB887));
    // Head
    c.drawCircle(ui.Offset(s * 1.5, s * 1.0), s * 1.0,
        ui.Paint()..color = const ui.Color(0xFF8B6914));
    // Ear tufts
    final t1 = ui.Path()..moveTo(s * 0.6, s * 0.2)..lineTo(s * 0.9, -s * 0.5)..lineTo(s * 1.1, s * 0.3);
    c.drawPath(t1, ui.Paint()..color = const ui.Color(0xFF6B4423));
    final t2 = ui.Path()..moveTo(s * 1.9, s * 0.3)..lineTo(s * 2.1, -s * 0.5)..lineTo(s * 2.4, s * 0.2);
    c.drawPath(t2, ui.Paint()..color = const ui.Color(0xFF6B4423));
    // Face disks
    c.drawCircle(ui.Offset(s * 1.0, s * 1.0), s * 0.5,
        ui.Paint()..color = const ui.Color(0xFFDEB887));
    c.drawCircle(ui.Offset(s * 2.0, s * 1.0), s * 0.5,
        ui.Paint()..color = const ui.Color(0xFFDEB887));
    // Eyes
    if (_blink) {
      c.drawLine(ui.Offset(s * 0.75, s * 0.95), ui.Offset(s * 1.25, s * 0.95),
          ui.Paint()..color = const ui.Color(0xFF333333)..strokeWidth = 1.5);
      c.drawLine(ui.Offset(s * 1.75, s * 0.95), ui.Offset(s * 2.25, s * 0.95),
          ui.Paint()..color = const ui.Color(0xFF333333)..strokeWidth = 1.5);
    } else {
      c.drawCircle(ui.Offset(s * 1.0, s * 0.95), s * 0.32,
          ui.Paint()..color = const ui.Color(0xFFFBBF24));
      c.drawCircle(ui.Offset(s * 2.0, s * 0.95), s * 0.32,
          ui.Paint()..color = const ui.Color(0xFFFBBF24));
      c.drawCircle(ui.Offset(s * 1.0, s * 0.95), s * 0.15,
          ui.Paint()..color = const ui.Color(0xFF212121));
      c.drawCircle(ui.Offset(s * 2.0, s * 0.95), s * 0.15,
          ui.Paint()..color = const ui.Color(0xFF212121));
      c.drawCircle(ui.Offset(s * 0.92, s * 0.88), 1.0,
          ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      c.drawCircle(ui.Offset(s * 1.92, s * 0.88), 1.0,
          ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    }
    // Beak
    final beak = ui.Path()
      ..moveTo(s * 1.35, s * 1.25)..lineTo(s * 1.5, s * 1.5)..lineTo(s * 1.65, s * 1.25);
    c.drawPath(beak, ui.Paint()..color = const ui.Color(0xFFFF8F00));
    // Feet
    c.drawLine(ui.Offset(s * 1.0, s * 3.6), ui.Offset(s * 0.7, s * 4.0),
        ui.Paint()..color = const ui.Color(0xFF8B6914)..strokeWidth = 1.5);
    c.drawLine(ui.Offset(s * 1.0, s * 3.6), ui.Offset(s * 1.3, s * 4.0),
        ui.Paint()..color = const ui.Color(0xFF8B6914)..strokeWidth = 1.5);
    c.drawLine(ui.Offset(s * 2.0, s * 3.6), ui.Offset(s * 1.7, s * 4.0),
        ui.Paint()..color = const ui.Color(0xFF8B6914)..strokeWidth = 1.5);
    c.drawLine(ui.Offset(s * 2.0, s * 3.6), ui.Offset(s * 2.3, s * 4.0),
        ui.Paint()..color = const ui.Color(0xFF8B6914)..strokeWidth = 1.5);
  }
}

/// ── Magical ambient particles ──
/// Dust motes in light, golden fireflies at night, fire sparks near fireplace
class _MagicalParticles extends Component with HasGameRef {
  final int hour;
  final bool hasFireplace;
  final _rng = math.Random();
  final List<_Mote> _motes = [];
  double _spawn = 0;

  _MagicalParticles({required this.hour, required this.hasFireplace});
  bool get _isNight => hour >= 20 || hour < 5;
  bool get _isDay => hour >= 7 && hour < 17;

  @override
  void onMount() {
    super.onMount();
    for (int i = 0; i < 6; i++) _motes.add(_newMote());
  }

  _Mote _newMote() {
    final w = gameRef.size.x, h = gameRef.size.y;

    if (_isNight) {
      // Golden fireflies — S-curve motion
      return _Mote(
        x: w * 0.2 + _rng.nextDouble() * w * 0.6,
        y: h * 0.15 + _rng.nextDouble() * h * 0.45,
        vx: (_rng.nextDouble() - 0.5) * 6,
        vy: (_rng.nextDouble() - 0.5) * 3,
        life: 4 + _rng.nextDouble() * 4,
        color: 18, // gold
        baseAlpha: 0.3 + _rng.nextDouble() * 0.3,
        size: 1.0 + _rng.nextDouble() * 0.5,
      );
    } else if (_isDay) {
      // Dust motes in god rays — cream, slow drift
      return _Mote(
        x: w * 0.3 + _rng.nextDouble() * w * 0.4,
        y: h * 0.1 + _rng.nextDouble() * h * 0.3,
        vx: (_rng.nextDouble() - 0.5) * 3,
        vy: 0.3 + _rng.nextDouble() * 0.8,
        life: 5 + _rng.nextDouble() * 5,
        color: 1, // cream
        baseAlpha: 0.12 + _rng.nextDouble() * 0.08,
        size: 0.6 + _rng.nextDouble() * 0.4,
      );
    } else {
      // Dawn/evening — warm amber motes
      return _Mote(
        x: w * 0.15 + _rng.nextDouble() * w * 0.7,
        y: h * 0.1 + _rng.nextDouble() * h * 0.35,
        vx: (_rng.nextDouble() - 0.5) * 4,
        vy: -0.5 + _rng.nextDouble() * 1.5,
        life: 3.5 + _rng.nextDouble() * 3.5,
        color: 19, // amber
        baseAlpha: 0.15 + _rng.nextDouble() * 0.1,
        size: 0.7 + _rng.nextDouble() * 0.3,
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _spawn += dt;
    if (_spawn > 1.0 && _motes.length < 12) {
      _spawn = 0;
      _motes.add(_newMote());
    }

    for (final m in _motes) {
      // Fireflies: sinusoidal S-curve
      if (_isNight) {
        m.x += m.vx * dt + math.sin(m.life * 1.5) * 0.3;
        m.y += m.vy * dt + math.cos(m.life * 1.2) * 0.2;
      } else {
        m.x += m.vx * dt;
        m.y += m.vy * dt;
      }
      m.life -= dt;
      m.alpha = (m.life / m.maxLife).clamp(0.0, 1.0) * m.baseAlpha;
    }
    _motes.removeWhere((m) => m.life <= 0);
  }

  @override
  void render(ui.Canvas canvas) {
    for (final m in _motes) {
      final color = masterPalette[m.color];
      if (color == null) continue;
      final a = m.alpha.clamp(0.0, 1.0);
      canvas.drawCircle(ui.Offset(m.x, m.y), m.size,
          ui.Paint()..color = color.withValues(alpha: a));
      // Firefly glow halo
      if (_isNight && m.size > 0.8) {
        canvas.drawCircle(ui.Offset(m.x, m.y), m.size * 3,
            ui.Paint()..color = color.withValues(alpha: a * 0.15));
      }
    }
  }
}

class _Mote {
  double x, y, vx, vy, life, alpha, baseAlpha, size;
  int color;
  final double maxLife;
  _Mote({required this.x, required this.y, required this.vx, required this.vy,
    required this.life, required this.color, this.baseAlpha = 0.3, this.size = 0.5})
      : maxLife = life, alpha = baseAlpha;
}

/// ── Candle flicker lighting overlay ──
/// Simulates flickering warm light from chandelier and lanterns
class _CandleFlickerOverlay extends Component with HasGameRef {
  final int hour;
  final bool hasFireplace;
  double _timer = 0;
  _CandleFlickerOverlay({required this.hour, required this.hasFireplace});
  bool get _isNight => hour >= 20 || hour < 5;
  bool get _isEvening => hour >= 17 && hour < 20;

  @override
  void update(double dt) { super.update(dt); _timer += dt; }

  @override
  void render(ui.Canvas c) {
    final w = gameRef.size.x, h = gameRef.size.y;

    // Edge vignette
    final va = _isNight ? 0.14 : 0.04;
    c.drawRect(ui.Rect.fromLTWH(0, 0, w, 5),
        ui.Paint()..color = ui.Color.fromARGB((va * 255).toInt(), 0, 0, 0));
    c.drawRect(ui.Rect.fromLTWH(0, h - 5, w, 5),
        ui.Paint()..color = ui.Color.fromARGB((va * 0.7 * 255).toInt(), 0, 0, 0));
    c.drawRect(ui.Rect.fromLTWH(0, 0, 4, h),
        ui.Paint()..color = ui.Color.fromARGB((va * 0.5 * 255).toInt(), 0, 0, 0));
    c.drawRect(ui.Rect.fromLTWH(w - 4, 0, 4, h),
        ui.Paint()..color = ui.Color.fromARGB((va * 0.5 * 255).toInt(), 0, 0, 0));

    // Chandelier flicker (warm glow that pulses)
    if (_isNight || _isEvening) {
      final flicker = 0.06 + math.sin(_timer * 5.5) * 0.015
          + math.sin(_timer * 8.3) * 0.008
          + math.sin(_timer * 13.7) * 0.005;
      // Chandelier center
      c.drawCircle(ui.Offset(w * 0.5, h * 0.1), w * 0.3,
          ui.Paint()..color = ui.Color.fromARGB(
              (flicker * 255).toInt(), 255, 200, 50));
    }

    // Fireplace glow
    if (hasFireplace && (_isNight || _isEvening)) {
      final fpFlicker = 0.08 + math.sin(_timer * 6) * 0.025
          + math.sin(_timer * 9.7) * 0.012;
      c.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()
        ..shader = ui.Gradient.radial(ui.Offset(w * 0.2, h * 0.7), w * 0.35,
            [ui.Color.fromARGB((fpFlicker * 255).toInt(), 255, 107, 53),
             const ui.Color(0x00000000)]));
    }
  }
}
