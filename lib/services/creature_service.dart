import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'local_cache_service.dart';

class CreatureService {
  static final CreatureService _i = CreatureService._();
  factory CreatureService() => _i;
  CreatureService._();

  Map<String, dynamic>? _cache;

  int maxExpForLevel(int level) => (100 * level * 1.3).toInt();

  int stageForLevel(int level) {
    if (level >= 30) return 4;
    if (level >= 20) return 3;
    if (level >= 10) return 2;
    if (level >= 3) return 1;
    return 0;
  }

  String stageLabel(int stage) {
    const labels = ['EGG', 'BABY', 'JUNIOR', 'MASTER', 'LEGEND'];
    return labels[stage.clamp(0, 4)];
  }

  Map<String, dynamic> defaultCreature() => {
    'name': '\uBB49\uCE58', // 뭉치
    'level': 1,
    'exp': 0,
    'coins': 0,
    'stage': 0,
    'ownedItems': <String>[],
    'placedItems': <Map<String, dynamic>>[],
    'mood': 'neutral',
  };

  Future<Map<String, dynamic>> getCreature() async {
    if (_cache != null) return Map<String, dynamic>.from(_cache!);
    try {
      final data = await FirebaseService().getStudyData();
      final c = data?['creature'];
      if (c != null && c is Map) {
        _cache = Map<String, dynamic>.from(c);
        return Map<String, dynamic>.from(_cache!);
      }
    } catch (e) {
      debugPrint('[Creature] load fail: $e');
    }
    return defaultCreature();
  }

  Future<void> _save(Map<String, dynamic> creature) async {
    _cache = Map<String, dynamic>.from(creature);
    try {
      await FirebaseService().updateField('creature', creature);
      LocalCacheService().markWrite();
    } catch (e) {
      debugPrint('[Creature] save fail: $e');
    }
  }

  Future<Map<String, dynamic>> addStudyReward(int studyMinutes) async {
    final creature = await getCreature();
    int exp = creature['exp'] as int? ?? 0;
    int level = creature['level'] as int? ?? 1;
    int coins = creature['coins'] as int? ?? 0;
    final earnedExp = studyMinutes * 2;
    final earnedCoins = studyMinutes;

    exp += earnedExp;
    coins += earnedCoins;

    bool leveledUp = false;
    while (exp >= maxExpForLevel(level)) {
      exp -= maxExpForLevel(level);
      level++;
      coins += 50;
      leveledUp = true;
    }

    creature['exp'] = exp;
    creature['level'] = level;
    creature['coins'] = coins;
    creature['stage'] = stageForLevel(level);

    await _save(creature);
    debugPrint('[Creature] +${earnedExp}EXP +${earnedCoins}C lv$level${leveledUp ? " LEVEL UP!" : ""}');

    return {
      'earnedExp': earnedExp,
      'earnedCoins': earnedCoins,
      'leveledUp': leveledUp,
      'newLevel': level,
    };
  }

  Future<bool> buyItem(String itemId, int cost) async {
    final creature = await getCreature();
    if ((creature['coins'] as int? ?? 0) < cost) return false;

    creature['coins'] = (creature['coins'] as int) - cost;
    final owned = List<String>.from(creature['ownedItems'] ?? []);
    if (!owned.contains(itemId)) owned.add(itemId);
    creature['ownedItems'] = owned;

    await _save(creature);
    return true;
  }

  Future<void> placeItem(String itemId, double x, double y) async {
    final creature = await getCreature();
    final placed = List<Map<String, dynamic>>.from(
      (creature['placedItems'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
    placed.removeWhere((i) => i['id'] == itemId);
    placed.add({'id': itemId, 'x': x, 'y': y});
    creature['placedItems'] = placed;
    await _save(creature);
  }

  Future<void> removeItem(String itemId) async {
    final creature = await getCreature();
    final placed = List<Map<String, dynamic>>.from(
      (creature['placedItems'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
    );
    placed.removeWhere((i) => i['id'] == itemId);
    creature['placedItems'] = placed;
    await _save(creature);
  }

  Future<void> setName(String name) async {
    final creature = await getCreature();
    creature['name'] = name;
    await _save(creature);
  }

  void invalidateCache() => _cache = null;
}
