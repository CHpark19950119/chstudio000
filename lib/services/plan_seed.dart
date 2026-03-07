/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — StudyPlan Firestore 시딩 유틸리티
/// plan_data.dart 정적 데이터 → Firestore studyPlan 1회 변환
/// ═══════════════════════════════════════════════════════════
///
/// 사용법 (한 번만 실행):
///   await PlanSeed.seedToFirestore();
///   → Firestore users/{uid}/data/study → studyPlan 필드에 기록
///
/// 이후 plan_data.dart는 폴백/읽기 전용으로만 유지

import 'package:flutter/foundation.dart';
import '../data/plan_data.dart';
import '../models/plan_models.dart';
import 'plan_service.dart';

class PlanSeed {
  PlanSeed._();

  /// plan_data.dart → StudyPlan 변환
  static StudyPlan buildFromStatic() {
    // ── 연간 목표 ──
    final annualGoals = <String, AnnualGoal>{};
    for (final entry in StudyPlanData.annualGoals.entries) {
      annualGoals[entry.key] = AnnualGoal(
        title: entry.value,
        priority: _goalPriority(entry.key),
        status: 'active',
      );
    }

    // ── 기간 (Periods) ──
    final periods = StudyPlanData.periods.map((p) {
      final now = DateTime.now();
      final end = DateTime.tryParse(p.end);
      final start = DateTime.tryParse(p.start);
      String status = 'upcoming';
      if (end != null && end.isBefore(now)) {
        status = 'completed';
      } else if (start != null && !start.isAfter(now)) {
        status = 'active';
      }

      return PlanPeriodDyn(
        id: p.id,
        name: p.name,
        start: p.start,
        end: p.end,
        goal: p.goal,
        totalDays: p.totalDays,
        status: status,
        subPeriods: p.subPeriods.map((sp) {
          final spEnd = DateTime.tryParse(sp.end);
          final spStart = DateTime.tryParse(sp.start);
          String spStatus = 'upcoming';
          if (spEnd != null && spEnd.isBefore(now)) {
            spStatus = 'completed';
          } else if (spStart != null && !spStart.isAfter(now)) {
            spStatus = 'active';
          }

          return PlanSubPeriodDyn(
            id: sp.id,
            name: sp.name,
            start: sp.start,
            end: sp.end,
            days: sp.days,
            instructor: sp.instructor,
            primaryGoal: sp.primaryGoal,
            goals: sp.goals,
            checkpoints: sp.checkpoints,
            status: spStatus,
          );
        }).toList(),
        subjects: p.subjects.map((s) {
          return PlanSubjectDyn(
            title: s.title,
            tag: s.tag,
            instructor: s.instructor,
            period: s.period,
            curriculum: s.curriculum,
          );
        }).toList(),
      );
    }).toList();

    // ── D-Day ──
    final ddays = StudyPlanData.ddays.map((d) {
      return DDayEvent(
        id: d.id,
        name: d.name,
        date: d.date,
        primary: d.primary,
        enabled: d.enabled,
      );
    }).toList();

    // ── 전략 방향 ──
    final strategy = StrategicDirection(
      diagnosis: StudyPlanData.strategicDirection['diagnosis'] ?? '',
      lastEvaluated: '2026-02-28',
      nextEvaluation: '2026-06-15',
      notes: Map<String, String>.from(StudyPlanData.strategicDirection)
        ..remove('diagnosis'),
    );

    // ── 시나리오 ──
    final scenarios = StudyPlanData.scenarios.map((s) {
      return ScenarioBranch(
        id: s.id,
        condition: s.condition,
        trigger: s.trigger,
        actions: s.actions,
        nextPeriod: s.nextPeriod,
      );
    }).toList();

    return StudyPlan(
      version: StudyPlanData.version,
      title: StudyPlanData.title,
      updatedBy: 'seed',
      annualGoals: annualGoals,
      periods: periods,
      ddays: ddays,
      strategy: strategy,
      scenarios: scenarios,
    );
  }

  /// Firestore에 시딩 (1회 실행)
  static Future<bool> seedToFirestore({bool force = false}) async {
    try {
      // 이미 시딩된 경우 스킵 (force가 아니면)
      if (!force) {
        final existing = await PlanService().getStudyPlan();
        if (existing != null) {
          debugPrint('[PlanSeed] ⚠️ 이미 studyPlan 존재 — 스킵');
          return false;
        }
      }

      final plan = buildFromStatic();
      await PlanService().saveStudyPlan(plan);

      debugPrint('[PlanSeed] ✅ studyPlan 시딩 완료 '
          '(${plan.periods.length}개 기간, ${plan.ddays.length}개 D-Day)');
      return true;
    } catch (e) {
      debugPrint('[PlanSeed] ❌ 시딩 실패: $e');
      return false;
    }
  }

  /// 목표 우선순위 매핑
  static int _goalPriority(String key) {
    switch (key) {
      case 'A': return 1;
      case 'B': return 2;
      case 'C': return 3;
      case 'D': return 4;
      default: return 99;
    }
  }
}
