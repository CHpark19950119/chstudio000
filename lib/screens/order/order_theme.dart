import 'package:flutter/material.dart';
import '../../models/order_models.dart';
import '../../utils/study_date_utils.dart';

/// ═══════════════════════════════════════════════════════════
/// ORDER — SHARED THEME & UTILITIES
/// "REALM OF ORDER" Design Language
/// ═══════════════════════════════════════════════════════════

class OC {
  OC._();
  // ─ Base ─
  static const bg       = Color(0xFFF6F4F0);
  static const bgSub    = Color(0xFFEDE9E3);
  static const card     = Color(0xFFFFFFFF);
  static const cardHi   = Color(0xFFF9F7F4);
  static const border   = Color(0xFFE8E2DA);

  // ─ Accents ─
  static const accent   = Color(0xFF5B5FE6);
  static const accentLt = Color(0xFF7C7FF2);
  static const accentBg = Color(0xFFEEEEFC);
  static const amber    = Color(0xFFF5A623);
  static const amberBg  = Color(0xFFFFF4E0);
  static const success  = Color(0xFF34C759);
  static const successBg= Color(0xFFE8F9ED);
  static const error    = Color(0xFFEF5350);
  static const errorBg  = Color(0xFFFDEDED);

  // ─ Tier ─
  static const sprint   = Color(0xFFEF6461);
  static const sprintBg = Color(0xFFFDECEB);
  static const race     = Color(0xFF8B5CF6);
  static const raceBg   = Color(0xFFF1ECFE);
  static const marathon = Color(0xFF0EA5E9);
  static const marathonBg= Color(0xFFE6F5FE);

  // ─ Text ─
  static const text1    = Color(0xFF1A1D26);
  static const text2    = Color(0xFF5A6070);
  static const text3    = Color(0xFF9CA3B0);
  static const text4    = Color(0xFFC5CAD4);

  // ─ Stress ─
  static const stressRel= Color(0xFFE74C3C);
  static const stressEsc= Color(0xFFF39C12);
  static const stressAlt= Color(0xFF27AE60);
}

// ═══ TIER HELPERS ═══
Color tierColor(GoalTier t) {
  switch (t) {
    case GoalTier.sprint:  return OC.sprint;
    case GoalTier.race:    return OC.race;
    case GoalTier.marathon: return OC.marathon;
  }
}

Color tierBg(GoalTier t) {
  switch (t) {
    case GoalTier.sprint:  return OC.sprintBg;
    case GoalTier.race:    return OC.raceBg;
    case GoalTier.marathon: return OC.marathonBg;
  }
}

// ═══ SHARED WIDGETS ═══
Widget orderSectionCard({
  required String title, IconData? icon,
  Widget? trailing, required List<Widget> children,
}) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: OC.card, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: OC.border.withOpacity(.5)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04),
        blurRadius: 16, offset: const Offset(0, 6))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: OC.accent),
          const SizedBox(width: 8),
        ],
        Text(title, style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.w800, color: OC.text1)),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
      const SizedBox(height: 14),
      ...children,
    ]),
  );
}

Widget orderChip(String text, Color color, Color bg) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
  child: Text(text, style: TextStyle(fontSize: 10,
    fontWeight: FontWeight.w700, color: color)),
);

Widget sheetHandle() => Container(
  margin: const EdgeInsets.only(top: 12, bottom: 8),
  width: 40, height: 4,
  decoration: BoxDecoration(color: OC.text4, borderRadius: BorderRadius.circular(2)),
);

Widget sheetField(String label, TextEditingController c, String hint,
    {int maxLines = 1}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12,
        fontWeight: FontWeight.w600, color: OC.text2)),
      const SizedBox(height: 4),
      sheetInput(c, hint, maxLines: maxLines),
    ]),
  );
}

Widget sheetInput(TextEditingController c, String hint, {int maxLines = 1}) {
  return TextField(
    controller: c, maxLines: maxLines,
    style: const TextStyle(fontSize: 14, color: OC.text1),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: OC.text4),
      filled: true, fillColor: OC.cardHi,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OC.border)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OC.border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: OC.accent)),
    ),
  );
}

Widget sheetBtn(String text, Color bg, Color fg, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(16),
        boxShadow: bg == OC.accent
            ? [BoxShadow(color: OC.accent.withOpacity(.25),
                blurRadius: 8, offset: const Offset(0, 3))]
            : null),
      child: Center(child: Text(text, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w700, color: fg))),
    ),
  );
}

Widget areaBtn(String label, GoalArea a, GoalArea sel, Function(GoalArea) onTap) {
  final s = a == sel;
  return GestureDetector(
    onTap: () => onTap(a),
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: s ? OC.accentBg : OC.cardHi,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s ? OC.accent : OC.border)),
      child: Center(child: Text(label, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: s ? OC.accent : OC.text3))),
    ),
  );
}

/// 오늘 날짜 문자열 (4AM 경계 적용)
String todayStr() => StudyDateUtils.todayKey();

/// 바텀시트 안전 하단 패딩 계산
/// viewInsets(키보드) + viewPadding(시스템 네비바) 중 큰 값 + 여유
double sheetBottomPad(BuildContext ctx, {double extra = 20}) {
  final mq = MediaQuery.of(ctx);
  final kbOrNav = mq.viewInsets.bottom > 0
      ? mq.viewInsets.bottom    // 키보드 올라옴
      : mq.viewPadding.bottom;  // 시스템 네비바
  return kbOrNav + extra;
}
