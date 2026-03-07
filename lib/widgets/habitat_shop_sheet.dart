import 'package:flutter/material.dart';
import '../theme/botanical_theme.dart';
import '../game/habitat_item.dart';

/// All shop items — sprite-based + legacy pixel art
const shopItems = [
  // Sprite-based items
  {'id': 'desk', 'name': '책상', 'cost': 0, 'reqLevel': 1},
  {'id': 'plant', 'name': '화분', 'cost': 20, 'reqLevel': 1},
  {'id': 'coffee', 'name': '머그컵', 'cost': 15, 'reqLevel': 1},
  {'id': 'teapot', 'name': '주전자', 'cost': 20, 'reqLevel': 1},
  {'id': 'lamp', 'name': '탁상램프', 'cost': 30, 'reqLevel': 2},
  {'id': 'star_light', 'name': '촛대', 'cost': 25, 'reqLevel': 2},
  {'id': 'shelf', 'name': '선반', 'cost': 30, 'reqLevel': 2},
  {'id': 'table', 'name': '테이블', 'cost': 30, 'reqLevel': 2},
  {'id': 'chair', 'name': '의자', 'cost': 40, 'reqLevel': 3},
  {'id': 'painting', 'name': '액자(소)', 'cost': 40, 'reqLevel': 3},
  {'id': 'decor_table', 'name': '장식테이블', 'cost': 35, 'reqLevel': 3},
  {'id': 'bookshelf_s', 'name': '책장(소)', 'cost': 50, 'reqLevel': 3},
  {'id': 'floor_lamp', 'name': '바닥램프', 'cost': 60, 'reqLevel': 4},
  {'id': 'guitar', 'name': '라디오', 'cost': 60, 'reqLevel': 4},
  {'id': 'bookshelf_l', 'name': '책장(대)', 'cost': 80, 'reqLevel': 5},
  {'id': 'painting_l', 'name': '액자(대)', 'cost': 80, 'reqLevel': 5},
  {'id': 'tv_table', 'name': 'TV테이블', 'cost': 50, 'reqLevel': 5},
  {'id': 'soft_chair', 'name': '안락의자', 'cost': 100, 'reqLevel': 6},
  {'id': 'dresser', 'name': '서랍장', 'cost': 90, 'reqLevel': 6},
  {'id': 'sofa', 'name': '소파', 'cost': 120, 'reqLevel': 8},
  {'id': 'tv', 'name': 'TV', 'cost': 150, 'reqLevel': 10},
  // Legacy pixel art items
  {'id': 'trophy', 'name': '트로피', 'cost': 100, 'reqLevel': 10},
  {'id': 'campfire', 'name': '벽난로', 'cost': 120, 'reqLevel': 10},
  {'id': 'cherry', 'name': '곰인형', 'cost': 200, 'reqLevel': 20},
  {'id': 'rainbow', 'name': '지구본', 'cost': 300, 'reqLevel': 25},
  {'id': 'castle', 'name': '졸업장', 'cost': 500, 'reqLevel': 30},
];

class HabitatShopSheet extends StatelessWidget {
  final int coins;
  final List<String> ownedItems;
  final int level;
  final Future<bool> Function(String itemId, int cost) onBuy;

  const HabitatShopSheet({
    super.key,
    required this.coins,
    required this.ownedItems,
    required this.level,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final dk = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: dk ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('SHOP', style: BotanicalTypo.heading(
              size: 20, weight: FontWeight.w900, color: dk ? Colors.white : Colors.black)),
            const SizedBox(width: 8),
            Text('${shopItems.length} items', style: TextStyle(
              fontSize: 11, color: dk ? Colors.white30 : Colors.grey)),
            const Spacer(),
            _coinBadge(coins),
          ]),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.75),
          itemCount: shopItems.length,
          itemBuilder: (ctx, i) {
            final item = shopItems[i];
            final id = item['id'] as String;
            final name = item['name'] as String;
            final cost = item['cost'] as int;
            final reqLevel = item['reqLevel'] as int;
            final owned = ownedItems.contains(id);
            final locked = level < reqLevel;
            final canBuy = !owned && !locked && coins >= cost;

            return GestureDetector(
              onTap: () async {
                if (owned || locked || coins < cost) return;
                final ok = await onBuy(id, cost);
                if (ok && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$name 구매 완료!')));
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: owned
                    ? (dk ? Colors.green.withOpacity(0.1) : Colors.green.withOpacity(0.05))
                    : locked
                      ? (dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade100)
                      : (dk ? Colors.white.withOpacity(0.06) : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: owned
                    ? Colors.green.withOpacity(0.3)
                    : (dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06)))),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // Item preview
                  SizedBox(
                    width: 48, height: 48,
                    child: _itemPreview(id, locked),
                  ),
                  const SizedBox(height: 6),
                  Text(name, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: locked ? Colors.grey : (dk ? Colors.white70 : Colors.black87))),
                  const SizedBox(height: 4),
                  if (owned)
                    const Icon(Icons.check_circle, size: 14, color: Colors.green)
                  else if (locked)
                    Text('LV.$reqLevel', style: const TextStyle(fontSize: 10, color: Colors.grey))
                  else
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFBBF24), shape: BoxShape.circle)),
                      Text(' $cost', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: canBuy ? const Color(0xFFFFD700) : Colors.red.shade300)),
                    ]),
                ]),
              ),
            );
          },
        )),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ]),
    );
  }

  Widget _itemPreview(String id, bool locked) {
    final def = spriteItemMap[id];
    if (def != null) {
      // Sprite-based preview
      return Opacity(
        opacity: locked ? 0.3 : 1.0,
        child: Image.asset(
          'assets/habitat/${def.assetPath}',
          width: 48, height: 48,
          filterQuality: FilterQuality.none,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
            CustomPaint(painter: MiniItemPainter(itemId: id)),
        ),
      );
    }
    // Legacy pixel art
    return Opacity(
      opacity: locked ? 0.3 : 1.0,
      child: CustomPaint(painter: MiniItemPainter(itemId: id)),
    );
  }

  Widget _coinBadge(int coins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 16, height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFFBBF24), shape: BoxShape.circle),
          child: const Center(child: Text('C', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF4A2F1B)))),
        ),
        const SizedBox(width: 4),
        Text('$coins', style: BotanicalTypo.number(
          size: 16, weight: FontWeight.w800, color: const Color(0xFFFFD700))),
      ]),
    );
  }
}
