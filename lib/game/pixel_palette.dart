import 'dart:ui';

const Map<int, Color> masterPalette = {
  0:  Color(0x00000000),
  1:  Color(0xFFFFF8E7), // cream light
  2:  Color(0xFFFFE4B5), // cream
  3:  Color(0xFFDEB887), // cream dark
  4:  Color(0xFF8B6914), // wood light
  5:  Color(0xFF6B4423), // wood mid
  6:  Color(0xFF4A2F1B), // wood dark
  7:  Color(0xFF2D1A0E), // wood shadow
  8:  Color(0xFF87CEEB), // sky light
  9:  Color(0xFF5BA3D9), // sky mid
  10: Color(0xFF1A1A3A), // night
  11: Color(0xFF0A0A1A), // deep night
  12: Color(0xFF4CAF50), // green light
  13: Color(0xFF2E7D32), // green mid
  14: Color(0xFF1B5E20), // green dark
  15: Color(0xFFFF6B35), // orange
  16: Color(0xFFE53935), // red
  17: Color(0xFFB71C1C), // dark red
  18: Color(0xFFFBBF24), // gold
  19: Color(0xFFF59E0B), // amber
  20: Color(0xFFFF8F00), // dark amber
  21: Color(0xFFB39DDB), // lavender
  22: Color(0xFF7C6DF5), // purple main
  23: Color(0xFF5B4FC7), // purple dark
  24: Color(0xFF3A2E8B), // purple shadow
  25: Color(0xFFFFFFFF), // white
  26: Color(0xFFE0E0E0), // light gray
  27: Color(0xFF9E9E9E), // mid gray
  28: Color(0xFF616161), // dark gray
  29: Color(0xFF212121), // near black
  30: Color(0xFFF9A8C9), // pink
  31: Color(0xFF81D4FA), // ice blue
};

const double pxScale = 4.0;

void drawSprite(Canvas canvas, List<List<int>> sprite, double x, double y, {double scale = 1.0}) {
  final s = pxScale * scale;
  for (int row = 0; row < sprite.length; row++) {
    final line = sprite[row];
    for (int col = 0; col < line.length; col++) {
      final idx = line[col];
      if (idx == 0) continue;
      final color = masterPalette[idx];
      if (color == null) continue;
      canvas.drawRect(
        Rect.fromLTWH(x + col * s, y + row * s, s, s),
        Paint()..color = color,
      );
    }
  }
}

void drawPixel(Canvas canvas, double x, double y, int colorIdx, {double scale = 1.0}) {
  if (colorIdx == 0) return;
  final color = masterPalette[colorIdx];
  if (color == null) return;
  final s = pxScale * scale;
  canvas.drawRect(Rect.fromLTWH(x, y, s, s), Paint()..color = color);
}

void fillRect(Canvas canvas, double x, double y, double w, double h, int colorIdx, {double alpha = 1.0}) {
  final color = masterPalette[colorIdx];
  if (color == null) return;
  canvas.drawRect(
    Rect.fromLTWH(x * pxScale, y * pxScale, w * pxScale, h * pxScale),
    Paint()..color = alpha < 1.0 ? color.withOpacity(alpha) : color,
  );
}

void strokeRect(Canvas canvas, double x, double y, double w, double h, int colorIdx) {
  final color = masterPalette[colorIdx];
  if (color == null) return;
  final s = pxScale;
  final p = Paint()..color = color;
  canvas.drawRect(Rect.fromLTWH(x * s, y * s, w * s, s), p); // top
  canvas.drawRect(Rect.fromLTWH(x * s, (y + h - 1) * s, w * s, s), p); // bottom
  canvas.drawRect(Rect.fromLTWH(x * s, y * s, s, h * s), p); // left
  canvas.drawRect(Rect.fromLTWH((x + w - 1) * s, y * s, s, h * s), p); // right
}

void hLine(Canvas canvas, double x, double y, double len, int colorIdx, {double alpha = 1.0}) {
  fillRect(canvas, x, y, len, 1, colorIdx, alpha: alpha);
}

void vLine(Canvas canvas, double x, double y, double len, int colorIdx) {
  fillRect(canvas, x, y, 1, len, colorIdx);
}
