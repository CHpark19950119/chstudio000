import 'dart:ui';
import 'package:flutter/material.dart' show CustomPainter, Size, FilterQuality;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'pixel_palette.dart';

/// ═══════════════════════════════════════════════════════
/// Habitat item definitions — sprite assets + legacy pixel art
/// ═══════════════════════════════════════════════════════

/// Sprite-based item definition
class SpriteItemDef {
  final String id;
  final String name;
  final String assetPath; // relative to assets/habitat/
  final int srcW, srcH;  // source pixel dimensions
  final int cost;
  final int reqLevel;

  const SpriteItemDef({
    required this.id, required this.name, required this.assetPath,
    required this.srcW, required this.srcH,
    this.cost = 0, this.reqLevel = 1,
  });
}

/// All sprite-based items
const spriteItemDefs = <SpriteItemDef>[
  SpriteItemDef(id: 'bookshelf_l', name: '책장(대)', assetPath: 'Furniture/BookShelfs_Large.png', srcW: 24, srcH: 24, cost: 80, reqLevel: 5),
  SpriteItemDef(id: 'bookshelf_s', name: '책장(소)', assetPath: 'Furniture/BookShelfs_Small.png', srcW: 16, srcH: 24, cost: 50, reqLevel: 3),
  SpriteItemDef(id: 'lamp', name: '탁상램프', assetPath: 'Furniture/TableLamp.png', srcW: 8, srcH: 8, cost: 30, reqLevel: 2),
  SpriteItemDef(id: 'floor_lamp', name: '바닥램프', assetPath: 'Furniture/FloorLamp.png', srcW: 8, srcH: 24, cost: 60, reqLevel: 4),
  SpriteItemDef(id: 'chair', name: '의자', assetPath: 'Furniture/Chair.png', srcW: 8, srcH: 16, cost: 40, reqLevel: 3),
  SpriteItemDef(id: 'sofa', name: '소파', assetPath: 'Furniture/Sofa.png', srcW: 24, srcH: 16, cost: 120, reqLevel: 8),
  SpriteItemDef(id: 'soft_chair', name: '안락의자', assetPath: 'Furniture/SoftChair.png', srcW: 16, srcH: 16, cost: 100, reqLevel: 6),
  SpriteItemDef(id: 'table', name: '테이블', assetPath: 'Furniture/Table_Single.png', srcW: 16, srcH: 8, cost: 30, reqLevel: 2),
  SpriteItemDef(id: 'plant', name: '화분', assetPath: 'Furniture/Plant.png', srcW: 8, srcH: 8, cost: 20, reqLevel: 1),
  SpriteItemDef(id: 'coffee', name: '머그컵', assetPath: 'Furniture/Mug.png', srcW: 8, srcH: 8, cost: 15, reqLevel: 1),
  SpriteItemDef(id: 'star_light', name: '촛대', assetPath: 'Furniture/Candle.png', srcW: 8, srcH: 8, cost: 25, reqLevel: 2),
  SpriteItemDef(id: 'painting', name: '액자(소)', assetPath: 'Furniture/Painting_Small.png', srcW: 8, srcH: 8, cost: 40, reqLevel: 3),
  SpriteItemDef(id: 'painting_l', name: '액자(대)', assetPath: 'Furniture/Painting_Large.png', srcW: 16, srcH: 16, cost: 80, reqLevel: 5),
  SpriteItemDef(id: 'guitar', name: '라디오', assetPath: 'Furniture/Radio.png', srcW: 8, srcH: 8, cost: 60, reqLevel: 4),
  SpriteItemDef(id: 'teapot', name: '주전자', assetPath: 'Furniture/Teapot.png', srcW: 8, srcH: 8, cost: 20, reqLevel: 1),
  SpriteItemDef(id: 'tv', name: 'TV', assetPath: 'Furniture/Television.png', srcW: 16, srcH: 16, cost: 150, reqLevel: 10),
  SpriteItemDef(id: 'tv_table', name: 'TV테이블', assetPath: 'Furniture/TelevisionTable.png', srcW: 16, srcH: 8, cost: 50, reqLevel: 5),
  SpriteItemDef(id: 'decor_table', name: '장식테이블', assetPath: 'Furniture/DecorTable.png', srcW: 8, srcH: 8, cost: 35, reqLevel: 3),
  SpriteItemDef(id: 'dresser', name: '서랍장', assetPath: 'Furniture/Dresser.png', srcW: 16, srcH: 16, cost: 90, reqLevel: 6),
  SpriteItemDef(id: 'shelf', name: '선반', assetPath: 'Furniture/Shelf_Single.png', srcW: 8, srcH: 8, cost: 30, reqLevel: 2),
  SpriteItemDef(id: 'desk', name: '책상', assetPath: 'Furniture/DecorTable.png', srcW: 8, srcH: 8, cost: 0, reqLevel: 1),
];

/// Quick lookup maps
final Map<String, SpriteItemDef> spriteItemMap = {
  for (final d in spriteItemDefs) d.id: d,
};

/// Item display names (Korean) — unified for both sprite and legacy items
final Map<String, String> itemNames = {
  for (final d in spriteItemDefs) d.id: d.name,
  // Legacy pixel-art only items
  'trophy': '트로피',
  'cherry': '곰인형',
  'campfire': '벽난로',
  'rainbow': '지구본',
  'castle': '졸업장',
};

/// ═══════════════════════════════════════════════════════
/// Legacy pixel art data (kept for items without sprite assets)
/// ═══════════════════════════════════════════════════════

const trophy = [
  [0,0,0, 18, 18, 18, 18,0,0,0],
  [0, 18, 18, 19, 19, 19, 19, 18, 18,0],
  [0, 18, 19, 1, 1, 1, 1, 19, 18,0],
  [ 18, 18, 19, 1, 18, 18, 1, 19, 18, 18],
  [ 18,0, 19, 1, 1, 1, 1, 19,0, 18],
  [ 18,0, 18, 19, 19, 19, 19, 18,0, 18],
  [0,0,0, 18, 19, 19, 18,0,0,0],
  [0,0,0,0, 19, 19,0,0,0,0],
  [0,0,0,0, 19, 19,0,0,0,0],
  [0,0,0,0, 19, 19,0,0,0,0],
  [0,0,0, 28, 28, 28, 28,0,0,0],
  [0,0, 6, 6, 6, 6, 6, 6,0,0],
  [0, 6, 5, 5, 5, 5, 5, 5, 6,0],
  [0, 6, 6, 6, 6, 6, 6, 6, 6,0],
];

const teddyBear = [
  [0, 3,0,0,0,0,0,0, 3,0],
  [ 3, 2, 3,0, 3, 3,0, 3, 2, 3],
  [0, 3, 2, 3, 2, 2, 3, 2, 3,0],
  [0,0, 3, 2, 2, 2, 2, 3,0,0],
  [0,0, 3, 29, 2, 2, 29, 3,0,0],
  [0,0, 3, 2, 29, 2, 2, 3,0,0],
  [0, 3, 2, 2, 2, 2, 2, 2, 3,0],
  [ 3, 2, 2, 16, 2, 2, 16, 2, 2, 3],
  [ 3, 2, 2, 2, 2, 2, 2, 2, 2, 3],
  [0, 3, 2, 2, 2, 2, 2, 2, 3,0],
  [0, 3, 2, 3,0,0, 3, 2, 3,0],
  [0,0, 3,0,0,0,0, 3,0,0],
];

const fireplace = [
  [ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
  [ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  [ 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6],
  [ 6, 5,0,0,0,0,0,0,0,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0,0,0,0,0,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0,0, 15, 15,0,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0, 15, 18, 18, 15,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0, 15, 18, 19, 19, 18, 15,0,0,0,0, 5, 6],
  [ 6, 5,0,0, 15, 18, 18, 18, 18, 15,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0, 15, 15, 15, 15,0,0,0,0,0, 5, 6],
  [ 6, 5, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 5, 6],
  [ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  [ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
  [ 5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4, 5],
];

const fireplaceFlame = [
  [ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
  [ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  [ 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6],
  [ 6, 5,0,0,0,0,0,0,0,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0,0, 15,0, 15,0,0,0,0,0, 5, 6],
  [ 6, 5,0,0,0, 15, 18, 15, 18, 15,0,0,0,0, 5, 6],
  [ 6, 5,0,0, 15, 18, 19, 18, 19, 18, 15,0,0,0, 5, 6],
  [ 6, 5,0,0, 15, 18, 19, 19, 19, 18, 15,0,0,0, 5, 6],
  [ 6, 5,0,0, 15, 18, 18, 18, 18, 18, 15,0,0,0, 5, 6],
  [ 6, 5,0,0,0, 15, 15, 15, 15, 15,0,0,0,0, 5, 6],
  [ 6, 5, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 5, 6],
  [ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  [ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
  [ 5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4, 5],
];

const globe = [
  [0,0,0, 28, 28, 28, 28,0,0,0],
  [0,0, 9, 9, 13, 9, 9, 9,0,0],
  [0, 9, 9, 13, 13, 13, 9, 9, 9,0],
  [ 9, 9, 13, 13, 9, 13, 13, 9, 9, 9],
  [ 9, 13, 13, 9, 9, 9, 13, 13, 9, 9],
  [ 9, 9, 13, 9, 9, 9, 13, 9, 9, 9],
  [0, 9, 9, 13, 13, 13, 9, 9, 9,0],
  [0,0, 9, 9, 13, 9, 9, 9,0,0],
  [0,0,0, 28, 28, 28, 28,0,0,0],
  [0,0,0,0, 28, 28,0,0,0,0],
  [0,0,0, 28, 28, 28, 28,0,0,0],
  [0,0, 28, 27, 27, 27, 27, 28,0,0],
];

const diploma = [
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,0],
  [ 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1],
  [ 1, 2, 29, 29, 29, 29, 29, 29, 29, 2, 2, 1],
  [ 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1],
  [ 1, 2, 2, 29, 29, 29, 29, 29, 2, 2, 2, 1],
  [ 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1],
  [ 1, 2, 2, 2, 18, 18, 2, 2, 2, 2, 2, 1],
  [ 1, 2, 2, 18, 19, 19, 18, 2, 2, 2, 2, 1],
  [ 1, 1, 1, 1, 18, 18, 1, 1, 1, 1, 1, 1],
  [0,0,0,0, 18, 18,0,0,0,0,0,0],
];

/// Legacy pixel sprites map
const Map<String, List<List<int>>> legacyPixelSprites = {
  'trophy': trophy,
  'cherry': teddyBear,
  'campfire': fireplace,
  'rainbow': globe,
  'castle': diploma,
};

const Map<String, List<List<int>>> legacyPixelSpritesAlt = {
  'campfire': fireplaceFlame,
};

/// ─── Flame Component ───
class HabitatItemComponent extends PositionComponent with DragCallbacks, HasGameRef {
  final String itemId;
  bool editable;
  Function(String id, double x, double y)? onMoved;
  Sprite? _sprite;
  double _animTimer = 0;
  bool _altFrame = false;

  HabitatItemComponent({
    required this.itemId,
    required Vector2 position,
    this.editable = false,
    this.onMoved,
  }) : super(position: position, size: Vector2(48, 56));

  @override
  Future<void> onLoad() async {
    final def = spriteItemMap[itemId];
    if (def != null) {
      try {
        final img = await gameRef.images.load(def.assetPath);
        _sprite = Sprite(img);
        final px = gameRef.size.x / 96;
        size = Vector2(def.srcW * px, def.srcH * px);
      } catch (e) {
        // Fallback to pixel art if sprite load fails
        _sprite = null;
      }
    } else {
      // Legacy pixel art — set size based on pixel dimensions
      final pixels = legacyPixelSprites[itemId];
      if (pixels != null) {
        final px = gameRef.size.x / 96;
        final cols = pixels[0].length;
        final rows = pixels.length;
        size = Vector2(cols * px, rows * px);
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (legacyPixelSpritesAlt.containsKey(itemId)) {
      _animTimer += dt;
      if (_animTimer > 0.6) {
        _animTimer = 0;
        _altFrame = !_altFrame;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (_sprite != null) {
      // Sprite-based rendering with nearest-neighbor
      _sprite!.render(canvas, size: size,
        overridePaint: Paint()..filterQuality = FilterQuality.none);
    } else {
      // Legacy pixel art fallback
      final pixels = (_altFrame && legacyPixelSpritesAlt.containsKey(itemId))
          ? legacyPixelSpritesAlt[itemId]!
          : legacyPixelSprites[itemId];
      if (pixels == null) return;
      final px = gameRef.size.x / 96;
      for (int r = 0; r < pixels.length; r++) {
        for (int c = 0; c < pixels[r].length; c++) {
          final idx = pixels[r][c];
          if (idx == 0) continue;
          final color = masterPalette[idx];
          if (color == null) continue;
          canvas.drawRect(
            Rect.fromLTWH(c * px, r * px, px, px),
            Paint()..color = color,
          );
        }
      }
    }

    if (editable) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, 3),
        Paint()..color = const Color(0x5022FF22));
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!editable) return;
    position += event.localDelta;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    if (!editable) return;
    onMoved?.call(itemId, position.x, position.y);
  }
}

/// Mini item painter for shop/inventory — pixel art only items
class MiniItemPainter extends CustomPainter {
  final String itemId;
  MiniItemPainter({required this.itemId});

  @override
  void paint(Canvas canvas, Size size) {
    final sprite = legacyPixelSprites[itemId];
    if (sprite == null) return;
    final rows = sprite.length;
    final cols = sprite[0].length;
    final scale = (size.width / cols).clamp(0.0, size.height / rows);
    final ox = (size.width - cols * scale) / 2;
    final oy = (size.height - rows * scale) / 2;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = sprite[r][c];
        if (idx == 0) continue;
        final color = masterPalette[idx];
        if (color == null) continue;
        canvas.drawRect(
          Rect.fromLTWH(ox + c * scale, oy + r * scale, scale, scale),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MiniItemPainter old) => old.itemId != itemId;
}
