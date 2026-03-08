/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — Todo Service
/// 간결한 할일 관리 CRUD
/// study 문서의 todos 필드에서 읽기/쓰기
/// ═══════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/plan_models.dart';
import 'creature_service.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';

class TodoService {
  static final TodoService _instance = TodoService._internal();
  factory TodoService() => _instance;
  TodoService._internal();

  final _db = FirebaseFirestore.instance;
  static const String _todosDoc = 'users/sJ8Pxusw9gR0tNR44RhkIge7OiG2/data/study';

  /// 4AM 경계 적용 오늘 날짜
  static String _todayDate() => StudyDateUtils.todayKey();

  /// 특정 날짜의 Todo 로드
  Future<TodoDaily?> getTodos(String date) async {
    try {
      final data = await FirebaseService().getStudyData();
      if (data == null) return null;
      final todosMap = _extractTodosMap(data['todos']);
      if (todosMap == null || todosMap[date] == null) return null;
      return TodoDaily.fromMap(
          Map<String, dynamic>.from(todosMap[date] as Map));
    } catch (e) {
      debugPrint('[TodoService] getTodos error: $e');
      return null;
    }
  }

  /// todos 필드가 Map이면 그대로, List면 null 반환 (잘못된 형식 무시)
  Map<String, dynamic>? _extractTodosMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    // List<dynamic> 등 비정상 형태 → 무시
    debugPrint('[TodoService] todos 필드가 Map이 아님: ${raw.runtimeType}');
    return null;
  }

  /// 오늘의 Todo 로드 (4AM 경계)
  Future<TodoDaily?> getTodayTodos() async {
    return getTodos(_todayDate());
  }

  /// Todo 저장 — Optimistic: 캐시 즉시 갱신, Firestore fire-and-forget
  void saveTodos(TodoDaily todos) {
    final map = todos.toMap();
    if (map['createdAt'] == null) {
      map['createdAt'] = DateTime.now().toIso8601String();
    }
    map['updatedAt'] = DateTime.now().toIso8601String();

    // ★ 1) 캐시 즉시 갱신 (write 보호 마킹 포함 — 스트림 덮어쓰기 방지)
    FirebaseService().updateTodosCache(todos.date, map);

    // ★ 2) Firestore study doc fire-and-forget (기존 호환)
    _db.doc(_todosDoc).update({
      'todos.${todos.date}': map,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    }).catchError((_) {
      _db.doc(_todosDoc).set({
        'todos': {todos.date: map},
        'lastModified': DateTime.now().millisecondsSinceEpoch,
        'lastDevice': 'android',
      }, SetOptions(merge: true)).catchError((_) {});
    });

    // ★ 3) Phase C: today 문서에도 todos 동기화 (오늘 날짜만)
    if (todos.date == _todayDate()) {
      final todayList = todos.items.map((t) => {
        'id': t.id,
        'title': t.title,
        'done': t.completed,
        'completedAt': t.completedAt,
      }).toList();
      FirebaseService().updateTodayField('todos', todayList);
    }
  }

  /// 개별 Todo 완료 토글
  Future<void> toggleTodo(String date, String id, bool completed) async {
    final todos = await getTodos(date);
    if (todos == null) return;

    final items = todos.items.map((t) {
      if (t.id == id) {
        return t.copyWith(
          completed: completed,
          completedAt:
              completed ? DateTime.now().toIso8601String() : null,
        );
      }
      return t;
    }).toList();

    saveTodos(TodoDaily(
      date: todos.date,
      items: items,
      memo: todos.memo,
      createdAt: todos.createdAt,
    ));

    // Creature reward for completing a todo
    if (completed) {
      try { CreatureService().addStudyReward(5); } catch (_) {}
    }
  }

  /// 내일 Todo 준비 (미완료 이월 + 새 항목)
  Future<TodoDaily> prepareTomorrowTodos({
    List<TodoItem> additionalItems = const [],
  }) async {
    final today = _todayDate();
    final todayTodos = await getTodos(today);

    final todayDt = DateFormat('yyyy-MM-dd').parse(today);
    final tomorrowStr =
        DateFormat('yyyy-MM-dd').format(todayDt.add(const Duration(days: 1)));

    final carryOver = (todayTodos?.items ?? [])
        .where((t) => !t.completed)
        .toList();

    int order = 0;
    final items = <TodoItem>[];
    for (final item in carryOver) {
      items.add(item.copyWith(
        completed: false,
        completedAt: null,
        order: order++,
      ));
    }
    for (final item in additionalItems) {
      items.add(TodoItem(
        id: item.id,
        title: item.title,
        order: order++,
      ));
    }

    final tomorrow = TodoDaily(
      date: tomorrowStr,
      items: items,
      createdAt: DateTime.now().toIso8601String(),
    );
    saveTodos(tomorrow);
    return tomorrow;
  }

  /// 최근 N일 완료율 히스토리
  Future<Map<String, double>> getCompletionHistory({int days = 7}) async {
    try {
      final data = await FirebaseService().getStudyData();
      final raw = _extractTodosMap(data?['todos']);
      if (raw == null) return {};

      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(Duration(days: days)));

      final result = <String, double>{};
      for (final entry in raw.entries) {
        if (entry.key.compareTo(cutoff) >= 0) {
          try {
            final td = TodoDaily.fromMap(
                Map<String, dynamic>.from(entry.value as Map));
            result[entry.key] = td.completionRate;
          } catch (_) {}
        }
      }
      return result;
    } catch (e) {
      debugPrint('[TodoService] getCompletionHistory error: $e');
      return {};
    }
  }
}
