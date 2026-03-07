import 'package:flutter/material.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/creature_service.dart';

/// 세션 완료 결과 다이얼로그
void showFocusResultDialog({
  required BuildContext context,
  required FocusCycle cycle,
  required bool dk,
  required Color textMain,
  required Color textSub,
  required Color textMuted,
  required int cradleFocusSec,
  required int cradleRestSec,
  required int cradleRestCount,
  required bool magnetEnabled,
}) {
  final c = BotanicalColors.subjectColor(cycle.subject);
  final usedCradle = magnetEnabled && (cradleFocusSec + cradleRestSec > 30);

  int concentrationRate = 100;
  if (usedCradle) {
    final total = cradleFocusSec + cradleRestSec;
    concentrationRate = total > 0 ? ((cradleFocusSec / total) * 100).round().clamp(0, 100) : 100;
  }

  // 집중도 보너스
  int bonus = 0;
  if (usedCradle) {
    if (concentrationRate >= 90) bonus = 5;
    else if (concentrationRate >= 80) bonus = 3;
    else if (concentrationRate >= 70) bonus = 1;
  }
  if (bonus > 0) {
    try { CreatureService().addStudyReward(bonus); } catch (_) {}
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dCtx) => AlertDialog(
      backgroundColor: dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        const Text('🎉', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('세션 완료!', style: BotanicalTypo.heading(size: 20, color: textMain)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('순공 ${cycle.effectiveMin}분', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 8),
            Text('${SubjectConfig.subjects[cycle.subject]?.emoji ?? '📚'} ${cycle.subject}',
              style: BotanicalTypo.body(size: 14, color: textSub)),
            const SizedBox(height: 8),
            Text('공부 ${cycle.studyMin}분 · 강의 ${cycle.lectureMin}분 · 휴식 ${cycle.restMin}분',
              style: BotanicalTypo.label(size: 12, color: textMuted)),
          ]),
        ),
        if (usedCradle) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _concentrationColor(concentrationRate).withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _concentrationColor(concentrationRate).withOpacity(0.2))),
            child: Column(children: [
              Text('집중도', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: textMuted)),
              const SizedBox(height: 4),
              Text('$concentrationRate%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                color: _concentrationColor(concentrationRate))),
              if (bonus > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('보너스 +$bonus EXP',
                    style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11,
                      fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx),
          child: Text('확인', style: TextStyle(
            fontWeight: FontWeight.w700, color: c)),
        ),
      ],
    ),
  );
}

Color _concentrationColor(int rate) {
  if (rate >= 90) return const Color(0xFF10B981);
  if (rate >= 70) return const Color(0xFFFBBF24);
  if (rate >= 50) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}
