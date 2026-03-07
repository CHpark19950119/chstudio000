import 'dart:ui' as ui;
import 'package:flame/components.dart';

/// Full-screen background image for the habitat.
/// Selects image based on time of day:
///   dawn   04:00 ~ 06:59
///   day    07:00 ~ 16:59
///   evening 17:00 ~ 19:59
///   night  20:00 ~ 03:59
class HabitatBackground extends Component with HasGameRef {
  late Sprite _bgSprite;

  static String _bgAsset() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 7) return 'dawn.png';
    if (hour >= 7 && hour < 17) return 'day.png';
    if (hour >= 17 && hour < 20) return 'evening.png';
    return 'night.png';
  }

  @override
  Future<void> onLoad() async {
    final image = await gameRef.images.load(_bgAsset());
    _bgSprite = Sprite(image);
  }

  @override
  void render(ui.Canvas canvas) {
    _bgSprite.render(canvas, size: gameRef.size);
  }
}
