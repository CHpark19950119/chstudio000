import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flame/game.dart';
import '../theme/botanical_theme.dart';
import '../services/creature_service.dart';
import '../game/habitat_game.dart';
import '../game/habitat_item.dart';
import '../widgets/habitat_shop_sheet.dart';

class HabitatScreen extends StatefulWidget {
  const HabitatScreen({super.key});
  @override
  State<HabitatScreen> createState() => _HabitatScreenState();
}

class _HabitatScreenState extends State<HabitatScreen> {
  Map<String, dynamic> _creature = {};
  bool _loading = true;
  bool _editMode = false;
  HabitatGame? _game;
  final _svc = CreatureService();

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(fn); });
    } else {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _svc.getCreature();
    _safeSetState(() {
      _creature = c;
      _loading = false;
      _game = HabitatGame(
        creatureData: _creature,
        editMode: _editMode,
        onItemMoved: (id, x, y) => _svc.placeItem(id, x, y),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
      );
    }

    final level = (_creature['level'] as num?)?.toInt() ?? 1;
    final exp = (_creature['exp'] as num?)?.toInt() ?? 0;
    final coins = (_creature['coins'] as num?)?.toInt() ?? 0;
    final stage = (_creature['stage'] as num?)?.toInt() ?? 0;
    final maxExp = _svc.maxExpForLevel(level);
    final name = _creature['name']?.toString() ?? '\uBB49\uCE58';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(child: Column(children: [
        // header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back_rounded, size: 18, color: Colors.white70)),
            ),
            const SizedBox(width: 12),
            Text('MY HABITAT', style: BotanicalTypo.heading(
              size: 18, weight: FontWeight.w900, color: Colors.white)),
            const Spacer(),
            _coinBadge(coins),
          ]),
        ),

        // game area
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _game != null
              ? GameWidget(game: _game!)
              : const SizedBox(),
          ),
        ),

        // bottom panel
        Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: const BoxDecoration(
            color: Color(0xFF151530),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            // name + level
            Row(children: [
              GestureDetector(
                onTap: _editName,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(name, style: BotanicalTypo.heading(
                    size: 20, weight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_rounded, size: 14, color: Colors.white30),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('LV.$level', style: BotanicalTypo.label(
                  size: 12, weight: FontWeight.w800, color: const Color(0xFF8B5CF6))),
              ),
              const Spacer(),
              Text(_svc.stageLabel(stage), style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700, letterSpacing: 1,
                color: _stageColor(stage))),
            ]),
            const SizedBox(height: 10),

            // EXP bar
            Row(children: [
              Text('EXP', style: BotanicalTypo.label(size: 10, weight: FontWeight.w600, color: Colors.white38)),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (exp / maxExp).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withOpacity(0.08),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
                  minHeight: 6),
              )),
              const SizedBox(width: 8),
              Text('$exp/$maxExp', style: BotanicalTypo.label(
                size: 10, weight: FontWeight.w600, color: Colors.white38)),
            ]),
            const SizedBox(height: 10),

            // evolution dots
            _evolutionDots(stage),
            const SizedBox(height: 14),

            // action buttons
            Row(children: [
              _actionBtn(Icons.inventory_2_rounded, '\uC778\uBCA4\uD1A0\uB9AC', () => _showInventory()),
              const SizedBox(width: 10),
              _actionBtn(Icons.storefront_rounded, '\uC0C1\uC810', () => _openShop()),
              const SizedBox(width: 10),
              _actionBtn(
                _editMode ? Icons.check_rounded : Icons.drag_indicator_rounded,
                _editMode ? '\uC644\uB8CC' : '\uBC30\uCE58',
                () {
                  _safeSetState(() => _editMode = !_editMode);
                  _load();
                },
              ),
            ]),
          ]),
        ),
      ])),
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
          child: Center(child: Text('C', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF4A2F1B)))),
        ),
        const SizedBox(width: 4),
        Text('$coins', style: BotanicalTypo.number(
          size: 14, weight: FontWeight.w800, color: const Color(0xFFFFD700))),
      ]),
    );
  }

  Widget _evolutionDots(int currentStage) {
    const labels = ['EGG', 'BABY', 'JR', 'MST', 'LGD'];
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (int i = 0; i < 5; i++) ...[
        Column(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= currentStage ? _stageColor(i) : Colors.white.withOpacity(0.1),
              boxShadow: i <= currentStage
                ? [BoxShadow(color: _stageColor(i).withOpacity(0.4), blurRadius: 6)]
                : null),
          ),
          const SizedBox(height: 3),
          Text(labels[i], style: TextStyle(
            fontSize: 8, fontWeight: FontWeight.w700,
            color: i <= currentStage ? _stageColor(i) : Colors.white24)),
        ]),
        if (i < 4)
          Container(
            width: 24, height: 2, margin: const EdgeInsets.only(bottom: 12),
            color: i < currentStage ? _stageColor(i) : Colors.white.withOpacity(0.06)),
      ],
    ]);
  }

  Color _stageColor(int stage) {
    const colors = [
      Color(0xFFFFF8E7), Color(0xFFFFE082), Color(0xFF4FC3F7),
      Color(0xFF7E57C2), Color(0xFFFF6F00),
    ];
    return colors[stage.clamp(0, 4)];
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white54)),
        ]),
      ),
    ));
  }

  void _openShop() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HabitatShopSheet(
        coins: (_creature['coins'] as num?)?.toInt() ?? 0,
        ownedItems: List<String>.from(_creature['ownedItems'] ?? []),
        level: (_creature['level'] as num?)?.toInt() ?? 1,
        onBuy: (itemId, cost) async {
          final ok = await _svc.buyItem(itemId, cost);
          if (ok) await _load();
          return ok;
        },
      ),
    );
  }

  void _showInventory() {
    final owned = List<String>.from(_creature['ownedItems'] ?? []);
    final placed = (_creature['placedItems'] as List?)
        ?.map((e) => (e as Map)['id']?.toString() ?? '').toSet() ?? {};

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('\uC778\uBCA4\uD1A0\uB9AC', style: BotanicalTypo.heading(
            size: 18, weight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 16),
          if (owned.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('\uC0C1\uC810\uC5D0\uC11C \uC544\uC774\uD15C\uC744 \uAD6C\uB9E4\uD558\uC138\uC694!',
                style: TextStyle(color: Colors.white38, fontSize: 13)))
          else
            Wrap(spacing: 10, runSpacing: 10, children: owned.map((id) {
              final name = itemNames[id] ?? id;
              final isPlaced = placed.contains(id);
              return GestureDetector(
                onTap: () async {
                  if (isPlaced) {
                    await _svc.removeItem(id);
                  } else {
                    await _svc.placeItem(id, 0.3 + owned.indexOf(id) * 0.1, 0.72);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isPlaced ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isPlaced ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.06))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 32, height: 32,
                      child: _itemIcon(id),
                    ),
                    const SizedBox(height: 4),
                    Text(name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: isPlaced ? Colors.green : Colors.white54)),
                    Text(isPlaced ? '\uBC30\uCE58\uB428' : '\uD0ED\uD558\uC5EC \uBC30\uCE58',
                      style: TextStyle(fontSize: 8, color: Colors.white30)),
                  ]),
                ),
              );
            }).toList()),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
        ]),
      ),
    );
  }

  Widget _itemIcon(String id) {
    final def = spriteItemMap[id];
    if (def != null) {
      return Image.asset(
        'assets/habitat/${def.assetPath}',
        width: 32, height: 32,
        filterQuality: FilterQuality.none,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
          CustomPaint(painter: MiniItemPainter(itemId: id)),
      );
    }
    return CustomPaint(painter: MiniItemPainter(itemId: id));
  }

  void _editName() async {
    final ctrl = TextEditingController(text: _creature['name']?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('\uCE90\uB9AD\uD130 \uC774\uB984', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          maxLength: 10,
          decoration: InputDecoration(
            hintText: '\uC774\uB984 \uC785\uB825',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6)))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('\uCDE8\uC18C', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text('\uC800\uC7A5', style: TextStyle(color: Color(0xFF8B5CF6)))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _svc.setName(result);
      await _load();
    }
  }
}
